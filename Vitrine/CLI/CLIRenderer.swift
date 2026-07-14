import AppKit
import Foundation
import OSLog

/// Drives a single `vitrine render` invocation: read the source file, build the
/// snapshot, render it through the **unchanged** app render path, and write the
/// image (CS-033).
///
/// The render path is `ExportManager` over a `SnapshotCanvas` — byte-for-byte the
/// same pipeline the editor and quick capture use — so a CLI render is pixel-identical
/// to the app for the same options (the CS-033 acceptance "reuse `SnapshotCanvas`/
/// `ExportManager` unchanged"). This type adds only the file I/O around that pipeline;
/// it never re-implements rendering.
///
/// It is `@MainActor` because `ImageRenderer` and Highlightr require AppKit on the
/// main actor. The executable hosts a minimal `NSApplication` (accessory policy, no
/// Dock/menu) so this code can run; nothing here needs the network, screen recording,
/// or Accessibility — code rendering is fully local.
@MainActor
enum CLIRenderer {
    /// One skipped input in the optional batch JSON report.
    private struct SkippedReportEntry: Encodable, Equatable {
        /// Slash-separated input path relative to the batch input folder.
        var path: String
        /// Stable user-facing reason matching the stderr line.
        var reason: String
    }

    /// Runs the full pipeline for `options` and returns a human-readable success
    /// line (the path written and the pixel dimensions), or throws a `CLIError`.
    ///
    /// `fileLoader` is injected so tests can exercise the render-and-write half
    /// without touching the security-scoped file reader; it defaults to the real
    /// `FileInputLoader.load(from:)` used by the editor's drag-and-drop (CS-028), so
    /// the CLI reuses the same text-only, language-inferring loader as the app.
    @discardableResult
    static func run(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile = {
            try FileInputLoader.load(from: $0)
        }
    ) throws -> String {
        let loaded = try loadInput(options, fileLoader: fileLoader)

        // An explicit `--language` overrides the inferred one; otherwise the loader's
        // extension/content inference wins, exactly as the editor does (CS-027/028).
        let language = options.language ?? loaded.language
        let config = options.makeConfig(code: loaded.text, language: language)

        // `--copy`: put the rendered image on the clipboard (the share-now flow). A
        // `--out` given alongside still writes the file too.
        if options.copyToClipboard {
            let copied = ExportManager.copyToPasteboard(
                config, scale: options.effectiveScale, fixedSize: options.fixedSize,
                profile: options.profile)
            guard copied else { throw CLIError.renderFailed }
            Log.export.notice("CLI copied an image to the clipboard")
            if !options.outputPath.isEmpty {
                let outputURL = URL(fileURLWithPath: options.outputPath)
                let dimensions = try renderAndWrite(config, options: options, to: outputURL)
                return
                    "Copied the image to the clipboard and wrote \(outputURL.path) "
                    + "(\(dimensions.width)×\(dimensions.height))\(sidecarNote(options, beside: outputURL))"
            }
            return "Copied the image to the clipboard"
        }

        let outputURL = URL(fileURLWithPath: options.outputPath)
        let dimensions = try renderAndWrite(config, options: options, to: outputURL)

        Log.export.notice(
            "CLI rendered an image (\(options.format.rawValue, privacy: .public))")
        return
            "Rendered \(outputURL.path) "
            + "(\(dimensions.width)×\(dimensions.height))\(sidecarNote(options, beside: outputURL))"
    }

    /// Hands the loaded source to the running app's editor (`--edit`) instead of
    /// rendering: stages the text on the private handoff pasteboard and opens a
    /// `vitrine://edit` URL, which the app reads back into its editor (see
    /// `EditorHandoff`). No image is produced and the general clipboard is untouched.
    ///
    /// `open` is injected so a test can assert the staged URL and pasteboard without
    /// actually launching the app; it defaults to `NSWorkspace.open`, which also wakes
    /// Vitrine if it isn't already running. It returns whether the open succeeded — a
    /// `false` (no app registered for `vitrine://`, Launch Services failure) throws
    /// `CLIError.editorOpenFailed` so the CLI exits non-zero instead of falsely
    /// reporting success to a script.
    @discardableResult
    static func openInEditor(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile = {
            try FileInputLoader.load(from: $0)
        },
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) throws -> String {
        let loaded = try loadInput(options, fileLoader: fileLoader)
        let language = options.language ?? loaded.language
        let url = EditorHandoff.stage(content: loaded.text, language: language)
        guard open(url) else { throw CLIError.editorOpenFailed }
        Log.export.notice("CLI handed the source to the editor (--edit)")
        return "Opened the captured output in Vitrine's editor."
    }

    /// Runs a folder `batch`: renders every readable text file in the input directory
    /// to the output directory, one image per file (CS-094).
    ///
    /// Non-text/unreadable files are skipped (not fatal), so a mixed folder still
    /// produces images for the code in it; the summary reports how many were skipped.
    /// `--recursive` walks nested folders and preserves their relative paths under the
    /// output directory. `--include-ext` / `--exclude-ext` filter regular files by
    /// extension before loading, which keeps known non-code assets out of skipped counts.
    /// `--fail-on-skipped` preserves successful renders but converts any skipped file
    /// into a failing CLI exit for strict CI/docs pipelines.
    /// `--skipped-report` writes a local JSON report before any strict failure is
    /// thrown. Each file goes through the same render-and-write path as `vitrine
    /// render`, so a batched image is pixel-identical to rendering that file alone
    /// with the same options. `directoryLister` is injected so the top-level
    /// file-discovery half is
    /// unit-testable without a real directory tree.
    @discardableResult
    static func runBatch(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile = {
            try FileInputLoader.load(from: $0)
        },
        directoryLister: (URL) throws -> [URL] = {
            try FileManager.default.contentsOfDirectory(
                at: $0, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
        }
    ) throws -> String {
        let inputDirectory = URL(fileURLWithPath: options.inputPath)
        let outputDirectory = URL(fileURLWithPath: options.outputPath)
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            throw CLIError.writeFailed(path: options.outputPath)
        }

        let files = try batchInputFiles(
            in: inputDirectory,
            recursive: options.recursiveBatch,
            includeExtensions: options.batchIncludeExtensions,
            excludeExtensions: options.batchExcludeExtensions,
            directoryLister: directoryLister)

        let ext = options.format.rawValue
        var rendered = 0
        var skipped = 0
        var skippedReport: [SkippedReportEntry] = []
        for file in files {
            let loaded: FileInputLoader.LoadedFile
            do {
                loaded = try fileLoader(file)
            } catch {
                // A binary/unreadable file is skipped, never a fatal batch error —
                // but the automation user gets the filename and reason on stderr, so
                // "skipped 3" in the summary is diagnosable without re-running.
                skipped += 1
                let reason = "not readable text"
                skippedReport.append(
                    skippedReportEntry(for: file, under: inputDirectory, reason: reason))
                reportSkipped(file, reason: reason)
                continue
            }
            let language = options.language ?? loaded.language
            let config = options.makeConfig(code: loaded.text, language: language)
            let outputURL = batchOutputURL(
                for: file, inputDirectory: inputDirectory, outputDirectory: outputDirectory,
                recursive: options.recursiveBatch, fileExtension: ext)
            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try renderAndWrite(config, options: options, to: outputURL)
                rendered += 1
            } catch {
                skipped += 1
                let reason = "render or write failed"
                skippedReport.append(
                    skippedReportEntry(for: file, under: inputDirectory, reason: reason))
                reportSkipped(file, reason: reason)
            }
        }

        Log.export.notice(
            "CLI batch rendered \(rendered, privacy: .public), skipped \(skipped, privacy: .public)"
        )
        let summary =
            "Rendered \(rendered) image\(rendered == 1 ? "" : "s") to \(outputDirectory.path)"
        try writeSkippedReport(skippedReport, path: options.skippedReportPath)
        if skipped > 0, options.failOnSkipped {
            throw CLIError.batchSkipped(rendered: rendered, skipped: skipped)
        }
        return skipped > 0 ? summary + " (skipped \(skipped))" : summary
    }

    /// Lists regular files for batch rendering. Non-recursive mode keeps the legacy
    /// top-level behavior; recursive mode uses FileManager's enumerator so nested
    /// folders can be mirrored under the output directory.
    private static func batchInputFiles(
        in inputDirectory: URL,
        recursive: Bool,
        includeExtensions: Set<String>,
        excludeExtensions: Set<String>,
        directoryLister: (URL) throws -> [URL]
    ) throws -> [URL] {
        let entries: [URL]
        do {
            if recursive {
                guard
                    let enumerator = FileManager.default.enumerator(
                        at: inputDirectory,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles])
                else { throw CLIError.inputUnreadable(path: inputDirectory.path) }
                entries = enumerator.compactMap { $0 as? URL }
            } else {
                entries = try directoryLister(inputDirectory)
            }
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError.inputUnreadable(path: inputDirectory.path)
        }

        return
            entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .filter {
                isIncludedByBatchExtensionFilters(
                    $0, includeExtensions: includeExtensions, excludeExtensions: excludeExtensions)
            }
            .sorted {
                batchRelativePath(for: $0, under: inputDirectory)
                    < batchRelativePath(for: $1, under: inputDirectory)
            }
    }

    /// Applies normalized extension include/exclude sets to a candidate batch file.
    /// Files without an extension are included by default, but an include list narrows
    /// the batch to only named extensions.
    private static func isIncludedByBatchExtensionFilters(
        _ file: URL,
        includeExtensions: Set<String>,
        excludeExtensions: Set<String>
    ) -> Bool {
        let ext = file.pathExtension.lowercased()
        guard includeExtensions.isEmpty || includeExtensions.contains(ext) else { return false }
        return !excludeExtensions.contains(ext)
    }

    /// Builds the output image URL for one batched input. Recursive batches preserve
    /// relative folders; top-level batches keep the historical flat output names.
    private static func batchOutputURL(
        for file: URL,
        inputDirectory: URL,
        outputDirectory: URL,
        recursive: Bool,
        fileExtension ext: String
    ) -> URL {
        let stem =
            recursive
            ? batchRelativePath(for: file, under: inputDirectory)
            : file.lastPathComponent
        return
            outputDirectory
            .appendingPathComponent(stem)
            .deletingPathExtension()
            .appendingPathExtension(ext)
    }

    /// Returns a slash-separated relative path when `file` sits below `root`,
    /// falling back to the filename if the URLs are not parent/child.
    private static func batchRelativePath(for file: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return file.lastPathComponent }
        return String(filePath.dropFirst(prefix.count))
    }

    /// Builds the manifest entry for one skipped file using the same relative-path
    /// logic as recursive output mirroring, so the report is stable across machines.
    private static func skippedReportEntry(
        for file: URL,
        under inputDirectory: URL,
        reason: String
    ) -> SkippedReportEntry {
        SkippedReportEntry(
            path: batchRelativePath(for: file, under: inputDirectory),
            reason: reason)
    }

    /// Writes the optional skipped-files report. An empty requested report is still a
    /// useful CI artifact (`[]`) because it proves the batch scanned without omissions.
    private static func writeSkippedReport(
        _ skippedReport: [SkippedReportEntry],
        path: String?
    ) throws {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data: Data
            if skippedReport.isEmpty {
                data = Data("[]\n".utf8)
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                var encoded = try encoder.encode(skippedReport)
                encoded.append(0x0A)
                data = encoded
            }
            try data.write(to: url, options: .atomic)
        } catch {
            throw CLIError.writeFailed(path: path)
        }
    }

    /// Names a skipped batch file (and why) on stderr. The user chose the input
    /// folder, so echoing a filename from it leaks nothing (unlike the app's
    /// no-paths logging rule for system errors); the summary line stays aggregate.
    private static func reportSkipped(_ file: URL, reason: String) {
        FileHandle.standardError.write(
            Data("vitrine: skipped \(file.lastPathComponent): \(reason)\n".utf8))
    }

    /// Reads the input file through the injected loader, translating its
    /// `FileInputLoader.LoadError` into the matching `CLIError`.
    private static func loadInput(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile
    ) throws -> FileInputLoader.LoadedFile {
        // `--stdin`: read the piped source (the shell integration feeds captured
        // terminal output here) and infer the language from the content — no filename,
        // so ANSI escapes route it to the terminal renderer.
        if options.readStdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            do {
                return try FileInputLoader.decode(data: data, filename: "")
            } catch FileInputLoader.LoadError.binaryFile {
                throw CLIError.inputNotText(path: "<stdin>")
            } catch {
                throw CLIError.inputUnreadable(path: "<stdin>")
            }
        }
        let inputURL = URL(fileURLWithPath: options.inputPath)
        do {
            return try fileLoader(inputURL)
        } catch FileInputLoader.LoadError.binaryFile {
            throw CLIError.inputNotText(path: options.inputPath)
        } catch {
            // `.unreadable`, `.tooLarge`, and any unexpected error all surface as an
            // unreadable input; the CLI never leaks a raw error string.
            throw CLIError.inputUnreadable(path: options.inputPath)
        }
    }

    /// Renders `config` and writes it to `url` as PNG or PDF, returning the pixel
    /// dimensions of the written image (for PDF, the logical point size).
    ///
    /// Encoding goes through the shared `ExportManager.encodedPayload` ladder — the
    /// same ImageIO/PDF path the GUI uses, honoring the chosen scale, fixed size, and
    /// color profile — so the CLI never re-implements the format switch. The PNG branch
    /// keeps its `CGImage` only to report exact pixel dimensions; the format-specific
    /// dimension reporting below is the one genuinely CLI-only part. A render or encode
    /// failure maps to `CLIError.renderFailed`; a write failure to
    /// `CLIError.writeFailed` — neither ever crashes the process.
    private static func renderAndWrite(
        _ config: SnapshotConfig, options: CLIOptions, to url: URL
    ) throws -> (width: Int, height: Int) {
        var pngImage: CGImage?
        let payload = ExportManager.encodedPayload(
            options.format,
            png: {
                let image = ExportManager.renderCGImage(
                    config, scale: options.effectiveScale, fixedSize: options.fixedSize,
                    profile: options.profile)
                pngImage = image
                return image
            },
            pdf: { ExportManager.pdfData(config, fixedSize: options.fixedSize) })
        guard let payload else { throw CLIError.renderFailed }
        try write(payload.data, to: url, options: options)
        if options.textSidecar { try writeTextSidecar(for: config, options: options, beside: url) }
        if options.markdownSidecar {
            try writeMarkdownSidecar(for: config, options: options, beside: url)
        }
        if options.htmlSidecar { try writeHTMLSidecar(for: config, options: options, beside: url) }

        switch options.format {
        case .png, .heic:
            // Both raster formats encode the CGImage rendered above, so `pngImage`
            // is non-nil whenever a payload was produced.
            return (pngImage?.width ?? 0, pngImage?.height ?? 0)
        case .pdf:
            // A PDF is a vector document; report the logical point size it was laid
            // out at (the fixed preset size when one is pinned, else the hugged size
            // read back from the page).
            let size = options.fixedSize ?? pdfPointSize(of: payload.data) ?? .zero
            return (Int(size.width.rounded()), Int(size.height.rounded()))
        }
    }

    /// The "` + card.txt`" tail appended to a success line when sidecars were
    /// written, naming each sidecar file; empty when none was requested.
    private static func sidecarNote(_ options: CLIOptions, beside imageURL: URL) -> String {
        let base = imageURL.deletingPathExtension()
        var names: [String] = []
        if options.textSidecar {
            names.append(base.appendingPathExtension("txt").lastPathComponent)
        }
        if options.markdownSidecar {
            names.append(base.appendingPathExtension("md").lastPathComponent)
        }
        if options.htmlSidecar {
            names.append(base.appendingPathExtension("html").lastPathComponent)
        }
        return names.map { " + \($0)" }.joined()
    }

    /// Writes the plain-text sidecar next to the rendered image at `imageURL`,
    /// replacing its extension with `.txt` (`card.png` → `card.txt`). Terminal output
    /// is reduced to its visible text (escape codes stripped, line redraws resolved) so
    /// the sidecar matches the image; other languages are written verbatim. A write
    /// failure surfaces as `CLIError.writeFailed`, the same as the image write.
    private static func writeTextSidecar(
        for config: SnapshotConfig, options: CLIOptions, beside imageURL: URL
    ) throws {
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("txt")
        do {
            try Data(config.sidecarText.utf8).write(to: sidecarURL)
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "CLI text-sidecar write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            throw CLIError.writeFailed(path: sidecarURL.path)
        }
    }

    /// Writes the Markdown sidecar next to the rendered image at `imageURL`
    /// (`card.png` → `card.md`): the image reference followed by the source in a
    /// language-tagged fenced code block, ready to paste into a README or post so
    /// viewers can copy the code the image shows. Terminal output is reduced to its
    /// visible text first, exactly like the plain-text sidecar.
    private static func writeMarkdownSidecar(
        for config: SnapshotConfig, options: CLIOptions, beside imageURL: URL
    ) throws {
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("md")
        let contents = markdownSidecarContents(
            for: config, imageName: imageURL.lastPathComponent)
        do {
            try Data(contents.utf8).write(to: sidecarURL)
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "CLI markdown-sidecar write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            throw CLIError.writeFailed(path: sidecarURL.path)
        }
    }

    /// Writes the HTML sidecar next to the rendered image at `imageURL`
    /// (`card.png` → `card.html`): the image embed followed by the source in an
    /// escaped, language-tagged `<pre><code>` block. Terminal output is reduced to its
    /// visible text first, exactly like the plain-text and Markdown sidecars.
    private static func writeHTMLSidecar(
        for config: SnapshotConfig, options: CLIOptions, beside imageURL: URL
    ) throws {
        let sidecarURL = imageURL.deletingPathExtension().appendingPathExtension("html")
        let contents = htmlSidecarContents(for: config, imageName: imageURL.lastPathComponent)
        do {
            try Data(contents.utf8).write(to: sidecarURL)
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "CLI html-sidecar write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            throw CLIError.writeFailed(path: sidecarURL.path)
        }
    }

    /// Builds the Markdown sidecar body: `![alt](image)` + a fenced code block.
    /// The fence is one backtick longer than the longest backtick run in the body,
    /// so code containing ``` can never break out of the block; the info string is
    /// the language id (`text` for terminal output, whose escapes are stripped).
    /// The image label/destination are escaped because both the input filename and
    /// output image name are user-controlled strings.
    /// Internal (not private) so the exact format is unit-testable.
    static func markdownSidecarContents(for config: SnapshotConfig, imageName: String) -> String {
        let body = config.sidecarText
        let fenceLanguage = config.language == .terminal ? "text" : config.language.rawValue
        var longestBacktickRun = 0
        var currentRun = 0
        for character in body {
            currentRun = character == "`" ? currentRun + 1 : 0
            longestBacktickRun = max(longestBacktickRun, currentRun)
        }
        let fence = String(repeating: "`", count: max(3, longestBacktickRun + 1))
        let alt = markdownAltText(config.metadata.filename ?? "Code rendered with Vitrine")
        let destination = markdownImageDestination(imageName)
        let trailingNewline = body.hasSuffix("\n") ? "" : "\n"
        return """
            ![\(alt)](\(destination))

            \(fence)\(fenceLanguage)
            \(body)\(trailingNewline)\(fence)
            """ + "\n"
    }

    /// Builds a small, self-contained HTML sidecar with every user-controlled string
    /// escaped for its context. This makes the sidecar safe to paste into docs even
    /// when the source filename, output name, or code contains HTML markup.
    /// Internal (not private) so the exact escaping contract is unit-testable.
    static func htmlSidecarContents(for config: SnapshotConfig, imageName: String) -> String {
        let body = htmlText(config.sidecarText)
        let title = htmlText(config.metadata.title ?? config.metadata.filename ?? "Vitrine render")
        let alt = htmlAttribute(config.metadata.filename ?? "Code rendered with Vitrine")
        let imageSource = htmlAttribute(imageName)
        let language = config.language == .terminal ? "text" : config.language.rawValue
        let codeClass = htmlAttribute("language-\(language)")
        return """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <title>\(title)</title>
            </head>
            <body>
              <figure>
                <img src="\(imageSource)" alt="\(alt)">
                <pre><code class="\(codeClass)">\(body)</code></pre>
              </figure>
            </body>
            </html>
            """ + "\n"
    }

    /// Escapes Markdown image alt text so a source filename containing `]`, `[`,
    /// backslashes, or newlines cannot break the generated image syntax.
    private static func markdownAltText(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\\":
                escaped += "\\\\"
            case "[", "]":
                escaped += "\\\(character)"
            case "\n", "\r":
                escaped += " "
            default:
                escaped.append(character)
            }
        }
        return escaped
    }

    /// Keeps plain filenames readable, but switches to an angle-bracket link
    /// destination when the output name carries Markdown-significant characters
    /// such as spaces, parentheses, or `>`.
    private static func markdownImageDestination(_ imageName: String) -> String {
        let plainSafeCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~/"))
        if imageName.unicodeScalars.allSatisfy({ plainSafeCharacters.contains($0) }) {
            return imageName
        }
        let escaped = imageName.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: ">", with: "\\>")
            .replacingOccurrences(of: "\n", with: "%0A")
            .replacingOccurrences(of: "\r", with: "%0D")
        return "<\(escaped)>"
    }

    /// Escapes text-node content for HTML sidecars.
    private static func htmlText(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&":
                escaped += "&amp;"
            case "<":
                escaped += "&lt;"
            case ">":
                escaped += "&gt;"
            default:
                escaped.append(character)
            }
        }
        return escaped
    }

    /// Escapes attribute values for HTML sidecars, also flattening line breaks so a
    /// user-controlled filename cannot create surprising multi-line attributes.
    private static func htmlAttribute(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&":
                escaped += "&amp;"
            case "\"":
                escaped += "&quot;"
            case "'":
                escaped += "&#39;"
            case "<":
                escaped += "&lt;"
            case ">":
                escaped += "&gt;"
            case "\n", "\r":
                escaped += " "
            default:
                escaped.append(character)
            }
        }
        return escaped
    }

    /// Writes `data` to `url`, mapping any I/O failure to `CLIError.writeFailed`.
    private static func write(_ data: Data, to url: URL, options: CLIOptions) throws {
        do {
            try data.write(to: url)
        } catch {
            // Log only the format, never the (user-chosen) path (CS-048 privacy rule).
            let nsError = error as NSError
            Log.export.error(
                "CLI write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            throw CLIError.writeFailed(path: options.outputPath)
        }
    }

    /// Reads back the first page's media-box size from rendered PDF `data`, so the
    /// success line can report a content-hugged PDF's logical dimensions.
    private static func pdfPointSize(of data: Data) -> CGSize? {
        guard let provider = CGDataProvider(data: data as CFData),
            let document = CGPDFDocument(provider),
            let page = document.page(at: 1)
        else { return nil }
        return page.getBoxRect(.mediaBox).size
    }
}

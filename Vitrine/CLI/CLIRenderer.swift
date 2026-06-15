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

        let outputURL = URL(fileURLWithPath: options.outputPath)
        let dimensions = try renderAndWrite(config, options: options, to: outputURL)

        Log.export.notice(
            "CLI rendered an image (\(options.format.rawValue, privacy: .public))")
        return "Rendered \(outputURL.path) (\(dimensions.width)×\(dimensions.height))"
    }

    /// Runs a folder `batch`: renders every readable text file in the input directory
    /// to the output directory, one image per file (CS-094).
    ///
    /// Non-text/unreadable files are skipped (not fatal), so a mixed folder still
    /// produces images for the code in it; the summary reports how many were skipped.
    /// Each file goes through the same render-and-write path as `vitrine render`, so a
    /// batched image is pixel-identical to rendering that file alone with the same
    /// options. `directoryLister` is injected so the file-discovery half is
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

        let entries: [URL]
        do {
            entries = try directoryLister(inputDirectory)
        } catch {
            throw CLIError.inputUnreadable(path: options.inputPath)
        }
        // Sort for a deterministic batch regardless of filesystem enumeration order,
        // and drop subdirectories so only files are rendered.
        let files =
            entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let ext = options.format == .pdf ? "pdf" : "png"
        var rendered = 0
        var skipped = 0
        for file in files {
            let loaded: FileInputLoader.LoadedFile
            do {
                loaded = try fileLoader(file)
            } catch {
                // A binary/unreadable file is skipped, never a fatal batch error.
                skipped += 1
                continue
            }
            let language = options.language ?? loaded.language
            let config = options.makeConfig(code: loaded.text, language: language)
            let outputURL =
                outputDirectory
                .appendingPathComponent(file.deletingPathExtension().lastPathComponent)
                .appendingPathExtension(ext)
            do {
                _ = try renderAndWrite(config, options: options, to: outputURL)
                rendered += 1
            } catch {
                skipped += 1
            }
        }

        Log.export.notice(
            "CLI batch rendered \(rendered, privacy: .public), skipped \(skipped, privacy: .public)"
        )
        let summary =
            "Rendered \(rendered) image\(rendered == 1 ? "" : "s") to \(outputDirectory.path)"
        return skipped > 0 ? summary + " (skipped \(skipped))" : summary
    }

    /// Reads the input file through the injected loader, translating its
    /// `FileInputLoader.LoadError` into the matching `CLIError`.
    private static func loadInput(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile
    ) throws -> FileInputLoader.LoadedFile {
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

        switch options.format {
        case .png:
            // `pngImage` is non-nil whenever a PNG payload was produced above.
            return (pngImage?.width ?? 0, pngImage?.height ?? 0)
        case .pdf:
            // A PDF is a vector document; report the logical point size it was laid
            // out at (the fixed preset size when one is pinned, else the hugged size
            // read back from the page).
            let size = options.fixedSize ?? pdfPointSize(of: payload.data) ?? .zero
            return (Int(size.width.rounded()), Int(size.height.rounded()))
        }
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

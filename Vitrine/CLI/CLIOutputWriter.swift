import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// Owns artifact preflight, shared encoding, sidecar generation, and file output.
enum CLIOutputWriter {
    /// A written image: its reported dimensions and, for raster formats, the exact
    /// pixels encoded, so `--copy` can reuse them instead of rendering twice.
    struct WrittenArtifact {
        var width: Int
        var height: Int
        var raster: CGImage?
    }

    static func encodedJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Returns every file a render would write beside its primary image output.
    private static func outputTargets(beside imageURL: URL, options: CLIOptions) -> [URL] {
        [imageURL] + sidecarURLs(options, beside: imageURL)
    }

    /// Returns sidecar files a render would write next to its primary image.
    static func sidecarURLs(_ options: CLIOptions, beside imageURL: URL) -> [URL] {
        let base = imageURL.deletingPathExtension()
        var targets: [URL] = []
        if options.textSidecar {
            targets.append(base.appendingPathExtension("txt"))
        }
        if options.markdownSidecar {
            targets.append(base.appendingPathExtension("md"))
        }
        if options.htmlSidecar {
            targets.append(base.appendingPathExtension("html"))
        }
        return targets
    }

    /// Rejects a run whose image or sidecars would replace an input or another output,
    /// including a local background image, watermark logo, or recipe.
    ///
    /// Sidecar names derive from `--out` (`base.txt`/`.md`/`.html`), and an unknown `--out`
    /// extension falls back to PNG, so `render notes.md --out notes.md` or a folder batch
    /// rendered into itself could silently replace a source and still exit 0. Destroying an
    /// input is never the intent, so this fails regardless of `--no-overwrite`.
    static func guardOutputsDoNotOverwriteInputs(
        beside imageURL: URL,
        options: CLIOptions,
        inputs: [URL]
    ) throws {
        try guardOutputsDoNotOverwriteInputs(beside: [imageURL], options: options, inputs: inputs)
    }

    /// Canonicalize inputs once for a whole batch rather than resolving every
    /// source again for each image in the output plan.
    static func guardOutputsDoNotOverwriteInputs(
        beside imageURLs: [URL],
        options: CLIOptions,
        inputs: [URL]
    ) throws {
        let resources = options.protectedResourceURLs
        let claimed = try Set((inputs + resources).map(claimKey))
        let planned = try imageURLs.map { imageURL in
            try outputTargets(beside: imageURL, options: options).map { ($0, try claimKey($0)) }
        }
        // Replacing an input is the more serious cause, so report it before output collisions.
        for targets in planned {
            guard let (imageURL, imageKey) = targets.first else { continue }
            if claimed.contains(imageKey) {
                throw CLIError.outputConflict(
                    "The output would overwrite the input file at \"\(imageURL.path)\". "
                        + "Choose an --out path that differs from the source.")
            }
            for (sidecar, key) in targets.dropFirst() where claimed.contains(key) {
                throw CLIError.outputConflict(
                    "The \(sidecar.pathExtension) sidecar would overwrite the input file at "
                        + "\"\(sidecar.path)\". Choose an --out path whose name differs from the "
                        + "source, or drop the sidecar flag.")
            }
        }
        var claimedOutputs: Set<String> = []
        for (target, key) in planned.joined() where !claimedOutputs.insert(key).inserted {
            throw CLIError.outputConflict(
                "The output at \"\(target.path)\" conflicts with another image or sidecar. "
                    + "Choose distinct paths for image and sidecar outputs.")
        }
    }

    /// The canonical path folded like the default case-insensitive Mac volume, so
    /// `notes.MD` and a `notes.md` sidecar are one claimed file. Folding only decides
    /// whether a name is taken; on a case-sensitive volume it can refuse a distinct
    /// file that differs only by case, which fails closed instead of risking a source.
    static func claimKey(_ url: URL) throws -> String {
        try canonicalPath(url).precomposedStringWithCanonicalMapping.lowercased()
    }

    /// A comparable filesystem identity: symlinks resolved and `.`/`..` removed, so two
    /// spellings of the same file compare equal. Resolve links even when their targets
    /// are missing: a batch can create that target before writing another output. Walk
    /// each link's raw target before `..`, which refers to its resolved physical parent.
    /// A bounded expansion budget refuses cycles instead of returning an uncertain key.
    private static func canonicalPath(_ url: URL) throws -> String {
        var pending = url.pathComponents
        var resolved: [String] = []
        var next = 0
        var links = 0
        while next < pending.count {
            let component = pending[next]
            next += 1
            switch component {
            case "/":
                resolved.removeAll(keepingCapacity: true)
                continue
            case ".":
                continue
            case "..":
                if !resolved.isEmpty { resolved.removeLast() }
                continue
            default:
                break
            }
            let candidate = "/" + (resolved + [component]).joined(separator: "/")
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate)
            else {
                resolved.append(component)
                continue
            }
            links += 1
            guard links <= 40 else {
                throw CLIError.outputConflict(
                    "The path at \"\(url.path)\" has too many symbolic links. "
                        + "Choose a path without a symbolic-link cycle.")
            }
            // `pathComponents` reports a trailing slash as a final "/", which is not the root.
            let parts = (target as NSString).pathComponents.enumerated()
                .filter { $0.offset == 0 || $0.element != "/" }.map(\.element)
            pending.insert(contentsOf: parts, at: next)
        }
        // Foundation also unifies macOS volume aliases (firmlinks). Normalize an existing
        // ancestor after walking raw links, then retain the missing suffix for planned outputs.
        var ancestor = URL(fileURLWithPath: "/" + resolved.joined(separator: "/"))
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        return missing.reversed().reduce(ancestor.standardizedFileURL.resolvingSymlinksInPath()) {
            $0.appendingPathComponent($1)
        }.path
    }

    /// Finds the first existing output target when `--no-overwrite` is active.
    static func existingNoOverwriteTarget(beside imageURL: URL, options: CLIOptions) -> URL? {
        guard options.noOverwrite else { return nil }
        return outputTargets(beside: imageURL, options: options).first(where: entryExists(at:))
    }

    /// Whether any directory entry occupies `url`, without following a final symlink.
    /// Publication refuses a dangling symlink too, so preflight must report it before
    /// rendering rather than letting the run fail late with a generic write error.
    static func entryExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Enforces `--no-overwrite` before rendering/copying so a run fails without
    /// partially replacing images, sidecars, or the clipboard.
    static func guardNoOverwriteTargetsAvailable(
        beside imageURL: URL,
        options: CLIOptions
    ) throws {
        if let existing = existingNoOverwriteTarget(beside: imageURL, options: options) {
            throw CLIError.outputExists(path: existing.path)
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
    /// failure maps to an actionable render error; an unavailable system writer to
    /// `CLIError.unsupportedOutputFormat`; a write failure to
    /// `CLIError.writeFailed` — neither ever crashes the process.
    static func renderAndWrite(
        _ config: SnapshotConfig, options: CLIOptions,
        backgroundStore: BackgroundImageStore = .container,
        foregroundStore: BackgroundImageStore = .foregroundContainer, to url: URL
    ) throws -> (width: Int, height: Int) {
        let artifact = try renderAndWriteArtifact(
            config, options: options, backgroundStore: backgroundStore,
            foregroundStore: foregroundStore, to: url)
        return (artifact.width, artifact.height)
    }

    static func renderAndWriteArtifact(
        _ config: SnapshotConfig, options: CLIOptions,
        backgroundStore: BackgroundImageStore = .container,
        foregroundStore: BackgroundImageStore = .foregroundContainer, to url: URL
    ) throws -> WrittenArtifact {
        guard options.format.isEncodingAvailable else {
            throw CLIError.unsupportedOutputFormat(options.format.displayName)
        }
        var rasterImage: CGImage?
        let payload: (data: Data, type: UTType, ext: String)
        do {
            payload = try ExportManager.encodedPayloadChecked(
                options.format,
                raster: { () throws(RenderBudgetError) -> CGImage in
                    let image = try ExportManager.renderCGImageChecked(
                        config, scale: options.effectiveScale, fixedSize: options.fixedSize,
                        profile: options.profile, backgroundImageStore: backgroundStore,
                        foregroundImageStore: foregroundStore)
                    rasterImage = image
                    return image
                },
                pdf: {
                    ExportManager.pdfData(
                        config, fixedSize: options.fixedSize,
                        backgroundImageStore: backgroundStore,
                        foregroundImageStore: foregroundStore)
                })
        } catch let error {
            throw CLIError.renderFailure(error)
        }
        try write(payload.data, to: url, noOverwrite: options.noOverwrite)
        if options.textSidecar { try writeTextSidecar(for: config, options: options, beside: url) }
        if options.markdownSidecar {
            try writeMarkdownSidecar(for: config, options: options, beside: url)
        }
        if options.htmlSidecar { try writeHTMLSidecar(for: config, options: options, beside: url) }

        switch options.format {
        case .png, .heic, .avif:
            // Every raster format encodes the CGImage rendered above, so `rasterImage`
            // is non-nil whenever a payload was produced.
            return WrittenArtifact(
                width: rasterImage?.width ?? 0, height: rasterImage?.height ?? 0,
                raster: rasterImage)
        case .pdf:
            // A PDF is a vector document; report the logical point size it was laid
            // out at (the fixed preset size when one is pinned, else the hugged size
            // read back from the page).
            let size = options.fixedSize ?? pdfPointSize(of: payload.data) ?? .zero
            return WrittenArtifact(
                width: Int(size.width.rounded()), height: Int(size.height.rounded()), raster: nil)
        }
    }

    /// The "` + card.txt`" tail appended to a success line when sidecars were
    /// written, naming each sidecar file; empty when none was requested.
    static func sidecarNote(_ options: CLIOptions, beside imageURL: URL) -> String {
        sidecarURLs(options, beside: imageURL).map { " + \($0.lastPathComponent)" }.joined()
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
        // `write` already logs the underlying error and maps it to `writeFailed`.
        try write(
            Data(config.sidecarText.utf8), to: sidecarURL, noOverwrite: options.noOverwrite)
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
        // `write` already logs the underlying error and maps it to `writeFailed`.
        try write(Data(contents.utf8), to: sidecarURL, noOverwrite: options.noOverwrite)
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
        // `write` already logs the underlying error and maps it to `writeFailed`.
        try write(Data(contents.utf8), to: sidecarURL, noOverwrite: options.noOverwrite)
    }

    /// Builds the Markdown sidecar body: `![alt](image)` + a fenced code block.
    /// The fence is one backtick longer than the longest backtick run in the body,
    /// so code containing ``` can never break out of the block; the info string is
    /// the language id (`text` for terminal output, whose escapes are stripped).
    /// The image label/destination are escaped because both the input filename and
    /// output image name are user-controlled strings.
    /// Internal (not private) so the exact format is unit-testable.
    static func markdownSidecarContents(for config: SnapshotConfig, imageName: String) -> String {
        MarkdownExport.document(for: config, imageSource: imageName)
    }

    /// Builds a small, self-contained HTML sidecar with every user-controlled string
    /// escaped for its context. This makes the sidecar safe to paste into docs even
    /// when the source filename, output name, or code contains HTML markup.
    /// Internal (not private) so the exact escaping contract is unit-testable.
    static func htmlSidecarContents(for config: SnapshotConfig, imageName: String) -> String {
        HTMLExport.document(for: config, imageSource: imageName)
    }

    /// Writes `data` to `url`, mapping any I/O failure to `CLIError.writeFailed`.
    ///
    /// No-clobber is enforced at publication, including a destination created after
    /// preflight. Each file commits independently; a later sidecar failure preserves
    /// earlier completed outputs and reports failure. The shared fallback on volumes
    /// without exclusive rename can leave a partial file on I/O failure.
    static func write(_ data: Data, to url: URL, noOverwrite: Bool) throws {
        do {
            if noOverwrite {
                try NonReplacingFilePublisher.publish(data, to: url)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Log only the format, never the (user-chosen) path (privacy policy).
            let nsError = error as NSError
            Log.export.error(
                "CLI write failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            throw CLIError.writeFailed(path: url.path)
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

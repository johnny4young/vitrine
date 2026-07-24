import AppKit
import Foundation
import OSLog

/// Owns artifact preflight, shared encoding, sidecar generation, and file output.
enum CLIOutputWriter {
    static func requireOutputURL(_ outputURL: URL?) throws -> URL {
        guard let outputURL else { throw CLIError.missingRequired("--out output path") }
        return outputURL
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

    /// Finds the first existing output target when `--no-overwrite` is active.
    static func existingNoOverwriteTarget(beside imageURL: URL, options: CLIOptions) -> URL? {
        guard options.noOverwrite else { return nil }
        return outputTargets(beside: imageURL, options: options).first {
            FileManager.default.fileExists(atPath: $0.path)
        }
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
    /// failure maps to `CLIError.renderFailed`; a write failure to
    /// `CLIError.writeFailed` — neither ever crashes the process.
    static func renderAndWrite(
        _ config: SnapshotConfig, options: CLIOptions,
        backgroundStore: BackgroundImageStore = .container,
        foregroundStore: BackgroundImageStore = .foregroundContainer, to url: URL
    ) throws -> (width: Int, height: Int) {
        var pngImage: CGImage?
        let payload = ExportManager.encodedPayload(
            options.format,
            png: {
                let image = ExportManager.renderCGImage(
                    config, scale: options.effectiveScale, fixedSize: options.fixedSize,
                    profile: options.profile, backgroundImageStore: backgroundStore,
                    foregroundImageStore: foregroundStore)
                pngImage = image
                return image
            },
            pdf: {
                ExportManager.pdfData(
                    config, fixedSize: options.fixedSize,
                    backgroundImageStore: backgroundStore,
                    foregroundImageStore: foregroundStore)
            })
        guard let payload else { throw CLIError.renderFailed }
        try write(payload.data, to: url)
        if options.textSidecar { try writeTextSidecar(for: config, options: options, beside: url) }
        if options.markdownSidecar {
            try writeMarkdownSidecar(for: config, options: options, beside: url)
        }
        if options.htmlSidecar { try writeHTMLSidecar(for: config, options: options, beside: url) }

        switch options.format {
        case .png, .heic, .avif:
            // Every raster format encodes the CGImage rendered above, so `pngImage`
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
        MarkdownExport.document(for: config, imageSource: imageName)
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
    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url)
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

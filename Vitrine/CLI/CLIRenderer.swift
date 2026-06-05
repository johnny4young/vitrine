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
    /// PNG goes through `renderCGImage` + `pngData` (the same ImageIO path the GUI
    /// uses, honoring the chosen scale, fixed size, and color profile). PDF uses
    /// `pdfData`. A render or encode failure maps to `CLIError.renderFailed`; a write
    /// failure to `CLIError.writeFailed` — neither ever crashes the process.
    private static func renderAndWrite(
        _ config: SnapshotConfig, options: CLIOptions, to url: URL
    ) throws -> (width: Int, height: Int) {
        switch options.format {
        case .png:
            guard
                let cgImage = ExportManager.renderCGImage(
                    config, scale: options.effectiveScale, fixedSize: options.fixedSize,
                    profile: options.profile),
                let data = ExportManager.pngData(from: cgImage)
            else {
                throw CLIError.renderFailed
            }
            try write(data, to: url, options: options)
            return (cgImage.width, cgImage.height)
        case .pdf:
            guard let data = ExportManager.pdfData(config, fixedSize: options.fixedSize) else {
                throw CLIError.renderFailed
            }
            try write(data, to: url, options: options)
            // A PDF is a vector document; report the logical point size it was laid
            // out at (the fixed preset size when one is pinned, else the hugged size
            // read back from the page).
            let size = options.fixedSize ?? pdfPointSize(of: data) ?? .zero
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

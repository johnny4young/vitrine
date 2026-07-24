import AppKit
import Foundation
import OSLog

/// Drives a single `vitrine render` invocation: read the source file, build the
/// snapshot, render it through the **unchanged** app render path, and write the
/// image.
///
/// The render path is `ExportManager` over a `SnapshotCanvas` — byte-for-byte the
/// same pipeline the editor and quick capture use — so a CLI render is pixel-identical
/// to the app for the same options. This type reuses `SnapshotCanvas` and
/// `ExportManager` unchanged, adding only file I/O around that pipeline;
/// it never re-implements rendering.
///
/// It is `@MainActor` because `ImageRenderer` and Highlightr require AppKit on the
/// main actor. The executable hosts a minimal `NSApplication` (accessory policy, no
/// Dock/menu) so this code can run; nothing here needs the network, screen recording,
/// or Accessibility — code rendering is fully local.
@MainActor
enum CLIRenderer {
    /// Machine-readable success summary for a `render` invocation.
    private struct RenderSummary: Encodable, Equatable {
        var command = "render"
        var status: String
        var output: String?
        var format: String?
        var width: Int?
        var height: Int?
        var copied: Bool
        var sidecars: [String]
    }

    /// One artifact in the machine-readable `multi-size` result.
    private struct MultiSizeOutputSummary: Encodable, Equatable {
        var preset: String
        var output: String
        var width: Int
        var height: Int
        var sidecars: [String]
    }

    /// Machine-readable success summary for one-source destination-preset fanout.
    private struct MultiSizeSummary: Encodable, Equatable {
        var command = "multi-size"
        var status = "rendered"
        var outputDirectory: String
        var format: String
        var rendered: Int
        var outputs: [MultiSizeOutputSummary]
    }
    /// Runs the full pipeline for `options` and returns a human-readable success
    /// line (the path written and the pixel dimensions), or throws a `CLIError`.
    ///
    /// `fileLoader` is injected so tests can exercise the render-and-write half
    /// without touching the security-scoped file reader; it defaults to the real
    /// `FileInputLoader.load(from:)` used by the editor's drag-and-drop, so
    /// the CLI reuses the same text-only, language-inferring loader as the app.
    @discardableResult
    static func run(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile = {
            try FileInputLoader.load(from: $0)
        }
    ) throws -> String {
        let background = try CLIRenderResources.prepareBackground(options)
        defer { background.removeTemporaryFiles() }
        let watermarkLogo = try CLIRenderResources.prepareWatermarkLogo(options)

        switch options.inputKind {
        case .code:
            let loaded = try loadInput(options, fileLoader: fileLoader)
            // An explicit `--language` overrides the inferred one; otherwise the loader's
            // extension/content inference wins, exactly as the editor does.
            let language = options.language ?? loaded.language
            var config = options.makeConfig(
                code: loaded.text, language: language,
                backgroundImageReference: background.reference,
                watermarkLogoData: watermarkLogo?.data)
            config.watermark?.logoImage = watermarkLogo?.image
            return try render(
                config, options: options, backgroundStore: background.store,
                foregroundStore: .foregroundContainer)
        case .image:
            return try renderImageInput(
                options, background: background, watermarkLogo: watermarkLogo)
        }
    }

    /// Renders one code/stdin source through each selected destination preset and
    /// writes the resulting files into one output directory. This is the CLI form of
    /// the app's multi-size export: the source is loaded once, every preset
    /// uses the shared `CLIOptions.makeConfig` precedence and `renderAndWrite` encoder,
    /// and filenames match the app's stable `vitrine-<preset id>.<ext>` convention.
    @discardableResult
    static func runMultiSize(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile = {
            try FileInputLoader.load(from: $0)
        }
    ) throws -> String {
        let background = try CLIRenderResources.prepareBackground(options)
        defer { background.removeTemporaryFiles() }
        let watermarkLogo = try CLIRenderResources.prepareWatermarkLogo(options)
        let loaded = try loadInput(options, fileLoader: fileLoader)
        let language = options.language ?? loaded.language

        let requestedIDs =
            options.multiSizePresetIDs.isEmpty
            ? ExportPreset.all.map(\.id) : options.multiSizePresetIDs
        let presets = requestedIDs.compactMap { ExportPreset.preset(withID: $0) }
        guard presets.count == requestedIDs.count else {
            let invalid = requestedIDs.first { ExportPreset.preset(withID: $0) == nil } ?? ""
            throw CLIError.invalidValue(flag: "--presets", value: invalid)
        }

        let outputDirectory = URL(fileURLWithPath: options.outputPath, isDirectory: true)
        let outputURLs = presets.map {
            outputDirectory.appendingPathComponent(
                "vitrine-\($0.id).\(options.format.fileExtension)", isDirectory: false)
        }

        // Preflight every target before creating the directory or rendering anything,
        // so --no-overwrite cannot leave a partially updated preset set.
        for outputURL in outputURLs {
            try CLIOutputWriter.guardNoOverwriteTargetsAvailable(
                beside: outputURL, options: options)
        }
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            throw CLIError.writeFailed(path: options.outputPath)
        }

        var outputs: [MultiSizeOutputSummary] = []
        for (preset, outputURL) in zip(presets, outputURLs) {
            var presetOptions = options
            presetOptions.presetID = preset.id
            presetOptions.multiSizePresetIDs = []
            // The parser rejects these overrides. Clear them defensively as well so a
            // hand-built CLIOptions value cannot defeat destination-preset geometry.
            presetOptions.canvasSize = nil
            presetOptions.scale = nil

            var config = presetOptions.makeConfig(
                code: loaded.text, language: language,
                backgroundImageReference: background.reference,
                watermarkLogoData: watermarkLogo?.data)
            config.watermark?.logoImage = watermarkLogo?.image
            let dimensions = try CLIOutputWriter.renderAndWrite(
                config, options: presetOptions, backgroundStore: background.store,
                to: outputURL)
            outputs.append(
                MultiSizeOutputSummary(
                    preset: preset.id, output: outputURL.path,
                    width: dimensions.width, height: dimensions.height,
                    sidecars: CLIOutputWriter.sidecarURLs(presetOptions, beside: outputURL).map(
                        \.path)))
        }

        Log.export.notice(
            "CLI multi-size rendered \(outputs.count, privacy: .public) preset images")
        if options.jsonOutput {
            return CLIOutputWriter.encodedJSON(
                MultiSizeSummary(
                    outputDirectory: outputDirectory.path,
                    format: options.format.rawValue,
                    rendered: outputs.count,
                    outputs: outputs))
        }
        return
            "Rendered \(outputs.count) preset image\(outputs.count == 1 ? "" : "s") to \(outputDirectory.path)"
    }
    /// Imports one local image into an invocation-scoped store, renders it through the
    /// shared canvas, then removes the temporary copy. This keeps `--image` local and
    /// side-effect free: unlike the editor, the CLI never adds automation inputs to the
    /// user's persistent foreground-image library.
    private static func renderImageInput(
        _ options: CLIOptions, background: CLIRenderResources.PreparedBackground,
        watermarkLogo: CLIRenderResources.PreparedWatermarkLogo?
    ) throws -> String {
        let sourceURL = URL(fileURLWithPath: options.inputPath)
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw CLIError.inputUnreadable(path: options.inputPath)
        }
        let directory = CLIRenderResources.temporaryImageDirectory()
        let store = BackgroundImageStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let reference: ImageReference
        do {
            reference = try store.importImage(
                data: data, preferredExtension: sourceURL.pathExtension)
        } catch BackgroundImageStore.ImportError.notAnImage {
            throw CLIError.inputNotImage(path: options.inputPath)
        } catch {
            throw CLIError.renderFailed
        }

        var config = options.makeConfig(
            code: "", language: .swift, backgroundImageReference: background.reference,
            watermarkLogoData: watermarkLogo?.data)
        config.watermark?.logoImage = watermarkLogo?.image
        config.foregroundImage = reference
        return try render(
            config, options: options, backgroundStore: background.store, foregroundStore: store)
    }

    /// Performs the common copy/write/report path once code or image input has produced
    /// a render-ready config and the store that resolves any foreground image.
    private static func render(
        _ config: SnapshotConfig, options: CLIOptions,
        backgroundStore: BackgroundImageStore,
        foregroundStore: BackgroundImageStore
    ) throws -> String {

        let optionalOutputURL =
            options.outputPath.isEmpty ? nil : URL(fileURLWithPath: options.outputPath)
        if let optionalOutputURL {
            try CLIOutputWriter.guardNoOverwriteTargetsAvailable(
                beside: optionalOutputURL, options: options)
        }

        // `--copy`: put the rendered image on the clipboard (the share-now flow). A
        // `--out` given alongside still writes the file too.
        if options.copyToClipboard {
            let copied = ExportManager.copyToPasteboard(
                config, scale: options.effectiveScale, fixedSize: options.fixedSize,
                profile: options.profile, backgroundImageStore: backgroundStore,
                foregroundImageStore: foregroundStore)
            guard copied else { throw CLIError.renderFailed }
            Log.export.notice("CLI copied an image to the clipboard")
            if let outputURL = optionalOutputURL {
                let dimensions = try CLIOutputWriter.renderAndWrite(
                    config, options: options, backgroundStore: backgroundStore,
                    foregroundStore: foregroundStore, to: outputURL)
                if options.jsonOutput {
                    return CLIOutputWriter.encodedJSON(
                        RenderSummary(
                            status: "copied_and_rendered",
                            output: outputURL.path,
                            format: options.format.rawValue,
                            width: dimensions.width,
                            height: dimensions.height,
                            copied: true,
                            sidecars: CLIOutputWriter.sidecarURLs(options, beside: outputURL).map(
                                \.path)))
                }
                return
                    "Copied the image to the clipboard and wrote \(outputURL.path) "
                    + "(\(dimensions.width)×\(dimensions.height))\(CLIOutputWriter.sidecarNote(options, beside: outputURL))"
            }
            if options.jsonOutput {
                return CLIOutputWriter.encodedJSON(
                    RenderSummary(
                        status: "copied",
                        output: nil,
                        format: options.format.rawValue,
                        width: nil,
                        height: nil,
                        copied: true,
                        sidecars: []))
            }
            return "Copied the image to the clipboard"
        }

        let outputURL = try CLIOutputWriter.requireOutputURL(optionalOutputURL)
        let dimensions = try CLIOutputWriter.renderAndWrite(
            config, options: options, backgroundStore: backgroundStore,
            foregroundStore: foregroundStore, to: outputURL)

        Log.export.notice(
            "CLI rendered an image (\(options.format.rawValue, privacy: .public))")
        if options.jsonOutput {
            return CLIOutputWriter.encodedJSON(
                RenderSummary(
                    status: "rendered",
                    output: outputURL.path,
                    format: options.format.rawValue,
                    width: dimensions.width,
                    height: dimensions.height,
                    copied: false,
                    sidecars: CLIOutputWriter.sidecarURLs(options, beside: outputURL).map(\.path)))
        }
        return
            "Rendered \(outputURL.path) "
            + "(\(dimensions.width)×\(dimensions.height))\(CLIOutputWriter.sidecarNote(options, beside: outputURL))"
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
        if options.jsonOutput {
            return CLIOutputWriter.encodedJSON(
                RenderSummary(
                    status: "opened_editor",
                    output: nil,
                    format: nil,
                    width: nil,
                    height: nil,
                    copied: false,
                    sidecars: []))
        }
        return "Opened the captured output in Vitrine's editor."
    }

    /// Runs a folder `batch`: renders every readable text file in the input directory
    /// to the output directory, one image per file.
    ///
    /// Non-text/unreadable files are skipped (not fatal), so a mixed folder still
    /// produces images for the code in it; the summary reports how many were skipped.
    /// `--recursive` walks nested folders and preserves their relative paths under the
    /// output directory. `--include-ext` / `--exclude-ext` filter regular files by
    /// extension before loading, which keeps known non-code assets out of skipped counts.
    /// `--dry-run` still scans and decodes inputs but skips image/sidecar writes, so a
    /// docs job can preflight a batch cheaply.
    /// `--manifest` writes the successful/planned output list as a JSON artifact with
    /// relative input/output paths and rendered dimensions when available.
    /// `--fail-on-empty` turns an empty discovery/preflight into a failing CLI exit.
    /// `--fail-on-skipped` preserves successful renders but converts any skipped file
    /// into a failing CLI exit for strict CI/docs pipelines.
    /// `--skipped-report` writes a local JSON report before any strict failure is
    /// thrown. Each file goes through the same render-and-write path as `vitrine
    /// render`, so a batched image is pixel-identical to rendering that file alone
    /// with the same options. `directoryLister` is injected so top-level discovery is
    /// unit-testable without a real directory tree. The implementation delegates to
    /// the batch operation while preserving the stable renderer facade used by the
    /// executable and tests.
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
        try CLIBatchRenderer.run(
            options, fileLoader: fileLoader, directoryLister: directoryLister)
    }
    /// Loads a generated Git diff, stdin, or an input file and translates every
    /// low-level failure into the matching stable `CLIError`.
    private static func loadInput(
        _ options: CLIOptions,
        fileLoader: (URL) throws -> FileInputLoader.LoadedFile
    ) throws -> FileInputLoader.LoadedFile {
        if let source = options.gitDiffSource {
            do {
                return try GitDiffInputLoader.load(
                    source: source, paths: options.gitDiffPaths,
                    contextLines: options.gitDiffContextLines)
            } catch GitDiffInputLoader.LoadError.emptyDiff {
                throw CLIError.gitDiffEmpty
            } catch GitDiffInputLoader.LoadError.tooLarge {
                throw CLIError.gitDiffTooLarge
            } catch {
                throw CLIError.gitDiffFailed
            }
        }
        // `--stdin`: read the piped source (the shell integration feeds captured
        // terminal output here). A user-supplied stdin name is only a hint: it is
        // never read from disk, but it lets extension-based inference match file input.
        if options.readStdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            do {
                return try FileInputLoader.decode(data: data, filename: options.stdinFilename ?? "")
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

}

import Foundation
import OSLog

/// Owns folder discovery, output planning, reporting, and batch render orchestration.
enum CLIBatchRenderer {
    /// One skipped input in the optional batch JSON report.
    private struct SkippedReportEntry: Encodable, Equatable {
        /// Slash-separated input path relative to the batch input folder.
        var path: String
        /// Stable user-facing reason matching the stderr line.
        var reason: String
    }

    /// One successfully loaded batch input, kept between discovery and render/write
    /// so output collision planning considers only files that can produce artifacts.
    private struct BatchLoadedInput {
        var file: URL
        var loaded: FileInputLoader.LoadedFile
    }

    /// One successful (or dry-run planned) batch output in the optional manifest.
    private struct BatchManifestEntry: Encodable, Equatable {
        /// Slash-separated input path relative to the batch input folder.
        var input: String
        /// Slash-separated output path relative to the batch output folder.
        var output: String
        /// Slash-separated sidecar paths relative to the batch output folder.
        var sidecars: [String]
        /// The language id actually used for this input.
        var language: String
        /// The requested output format (`png`, `pdf`, `heic`, or `avif`).
        var format: String
        /// `rendered` for real output, `planned` for `--dry-run`.
        var status: String
        /// Rendered width in pixels/points. Omitted for dry-run entries.
        var width: Int?
        /// Rendered height in pixels/points. Omitted for dry-run entries.
        var height: Int?
    }
    /// Machine-readable success summary for a `batch` invocation.
    private struct BatchSummary: Encodable, Equatable {
        var command = "batch"
        var status: String
        var outputDirectory: String
        var rendered: Int
        var skipped: Int
        var dryRun: Bool
        var manifest: String?
        var skippedReport: String?
    }

    static func run(
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
        let background = try CLIRenderResources.prepareBackground(options)
        defer { background.removeTemporaryFiles() }
        let watermarkLogo = try CLIRenderResources.prepareWatermarkLogo(options)

        let inputDirectory = URL(fileURLWithPath: options.inputPath)
        let outputDirectory = URL(fileURLWithPath: options.outputPath)
        if !options.dryRunBatch {
            do {
                try FileManager.default.createDirectory(
                    at: outputDirectory, withIntermediateDirectories: true)
            } catch {
                throw CLIError.writeFailed(path: options.outputPath)
            }
        }

        let files = try batchInputFiles(
            in: inputDirectory,
            recursive: options.recursiveBatch,
            includeExtensions: options.batchIncludeExtensions,
            excludeExtensions: options.batchExcludeExtensions,
            directoryLister: directoryLister)

        var loadedInputs: [BatchLoadedInput] = []
        var skipped = 0
        var skippedReport: [SkippedReportEntry] = []
        for file in files {
            do {
                loadedInputs.append(BatchLoadedInput(file: file, loaded: try fileLoader(file)))
            } catch {
                // A binary/unreadable file is skipped, never a fatal batch error —
                // but the automation user gets the filename and reason on stderr, so
                // "skipped 3" in the summary is diagnosable without re-running.
                skipped += 1
                let reason = "not readable text"
                skippedReport.append(
                    skippedReportEntry(for: file, under: inputDirectory, reason: reason))
                reportSkipped(file, reason: reason)
            }
        }

        let ext = options.format.rawValue
        let outputURLs = batchOutputURLs(
            for: loadedInputs.map(\.file), inputDirectory: inputDirectory,
            outputDirectory: outputDirectory, recursive: options.recursiveBatch, fileExtension: ext)
        var rendered = 0
        var manifest: [BatchManifestEntry] = []
        for input in loadedInputs {
            let file = input.file
            let loaded = input.loaded
            let language = options.language ?? loaded.language
            let outputURL =
                outputURLs[batchOutputKey(for: file)]
                ?? batchOutputURL(
                    for: file, inputDirectory: inputDirectory, outputDirectory: outputDirectory,
                    recursive: options.recursiveBatch, fileExtension: ext)
            if CLIOutputWriter.existingNoOverwriteTarget(beside: outputURL, options: options) != nil
            {
                skipped += 1
                let reason = "output already exists"
                skippedReport.append(
                    skippedReportEntry(for: file, under: inputDirectory, reason: reason))
                reportSkipped(file, reason: reason)
                continue
            }
            if options.dryRunBatch {
                rendered += 1
                manifest.append(
                    batchManifestEntry(
                        for: file, outputURL: outputURL, inputDirectory: inputDirectory,
                        outputDirectory: outputDirectory, language: language, format: ext,
                        status: "planned", dimensions: nil, options: options))
                continue
            }

            var config = options.makeConfig(
                code: loaded.text, language: language,
                backgroundImageReference: background.reference,
                watermarkLogoData: watermarkLogo?.data)
            config.watermark?.logoImage = watermarkLogo?.image
            do {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let dimensions = try CLIOutputWriter.renderAndWrite(
                    config, options: options, backgroundStore: background.store, to: outputURL)
                manifest.append(
                    batchManifestEntry(
                        for: file, outputURL: outputURL, inputDirectory: inputDirectory,
                        outputDirectory: outputDirectory, language: language, format: ext,
                        status: "rendered", dimensions: dimensions, options: options))
                rendered += 1
            } catch {
                skipped += 1
                let reason = "render or write failed"
                skippedReport.append(
                    skippedReportEntry(for: file, under: inputDirectory, reason: reason))
                reportSkipped(file, reason: reason)
            }
        }

        let action = options.dryRunBatch ? "Dry run: would render" : "Rendered"
        let logAction = options.dryRunBatch ? "dry-run would render" : "rendered"
        Log.export.notice(
            "CLI batch \(logAction, privacy: .public) \(rendered, privacy: .public), skipped \(skipped, privacy: .public)"
        )
        let summary =
            "\(action) \(rendered) image\(rendered == 1 ? "" : "s") to \(outputDirectory.path)"
        try writeSkippedReport(skippedReport, path: options.skippedReportPath)
        try writeBatchManifest(manifest, path: options.batchManifestPath)
        if rendered == 0, options.failOnEmpty {
            throw CLIError.batchEmpty(skipped: skipped)
        }
        if skipped > 0, options.failOnSkipped {
            throw CLIError.batchSkipped(rendered: rendered, skipped: skipped)
        }
        if options.jsonOutput {
            return CLIOutputWriter.encodedJSON(
                BatchSummary(
                    status: options.dryRunBatch ? "planned" : "rendered",
                    outputDirectory: outputDirectory.path,
                    rendered: rendered,
                    skipped: skipped,
                    dryRun: options.dryRunBatch,
                    manifest: nonEmptyPath(options.batchManifestPath),
                    skippedReport: nonEmptyPath(options.skippedReportPath)))
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

    /// Builds the output image URLs for a batch. The historical mapping drops the
    /// input extension (`Widget.swift` → `Widget.png`), but that collides when a
    /// folder contains several files with the same stem. Keep legacy names for
    /// non-colliding files and preserve the input extension only for colliding groups.
    private static func batchOutputURLs(
        for files: [URL],
        inputDirectory: URL,
        outputDirectory: URL,
        recursive: Bool,
        fileExtension ext: String
    ) -> [String: URL] {
        let baseRelativePaths = files.map { file in
            (
                file: file,
                relativePath: batchOutputRelativePath(
                    for: file, inputDirectory: inputDirectory, recursive: recursive,
                    preservingInputExtension: false, fileExtension: ext)
            )
        }
        let collisions = Dictionary(grouping: baseRelativePaths) { $0.relativePath }

        var outputs: [String: URL] = [:]
        for entry in baseRelativePaths {
            let shouldPreserveInputExtension = (collisions[entry.relativePath]?.count ?? 0) > 1
            let relativePath = batchOutputRelativePath(
                for: entry.file, inputDirectory: inputDirectory, recursive: recursive,
                preservingInputExtension: shouldPreserveInputExtension, fileExtension: ext)
            outputs[batchOutputKey(for: entry.file)] = outputDirectory.appendingPathComponent(
                relativePath)
        }
        return outputs
    }

    /// Builds the output image URL for one batched input using the legacy mapping.
    /// Callers that know the full file set should prefer `batchOutputURLs(...)` so
    /// same-stem inputs do not overwrite each other.
    private static func batchOutputURL(
        for file: URL,
        inputDirectory: URL,
        outputDirectory: URL,
        recursive: Bool,
        fileExtension ext: String
    ) -> URL {
        outputDirectory.appendingPathComponent(
            batchOutputRelativePath(
                for: file, inputDirectory: inputDirectory, recursive: recursive,
                preservingInputExtension: false, fileExtension: ext))
    }

    /// Builds the slash-separated relative output path for one batch input. Recursive
    /// batches preserve relative folders; top-level batches keep flat output names.
    private static func batchOutputRelativePath(
        for file: URL,
        inputDirectory: URL,
        recursive: Bool,
        preservingInputExtension: Bool,
        fileExtension ext: String
    ) -> String {
        let sourcePath =
            recursive
            ? batchRelativePath(for: file, under: inputDirectory)
            : file.lastPathComponent
        let outputStem =
            preservingInputExtension
            ? sourcePath
            : (sourcePath as NSString).deletingPathExtension
        return (outputStem as NSString).appendingPathExtension(ext) ?? outputStem + "." + ext
    }

    private static func batchOutputKey(for file: URL) -> String {
        file.standardizedFileURL.path
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

    /// Builds the manifest entry for one successfully loaded batch file using stable,
    /// slash-separated paths so CI artifacts are independent of the build machine.
    private static func batchManifestEntry(
        for file: URL,
        outputURL: URL,
        inputDirectory: URL,
        outputDirectory: URL,
        language: Language,
        format: String,
        status: String,
        dimensions: (width: Int, height: Int)?,
        options: CLIOptions
    ) -> BatchManifestEntry {
        BatchManifestEntry(
            input: batchRelativePath(for: file, under: inputDirectory),
            output: batchRelativePath(for: outputURL, under: outputDirectory),
            sidecars: CLIOutputWriter.sidecarURLs(options, beside: outputURL).map {
                batchRelativePath(for: $0, under: outputDirectory)
            },
            language: language.rawValue,
            format: format,
            status: status,
            width: dimensions?.width,
            height: dimensions?.height)
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

    /// Writes the optional positive batch manifest. A requested empty manifest is useful
    /// for CI because it proves discovery completed even when no inputs matched.
    private static func writeBatchManifest(
        _ manifest: [BatchManifestEntry],
        path: String?
    ) throws {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data: Data
            if manifest.isEmpty {
                data = Data("[]\n".utf8)
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                var encoded = try encoder.encode(manifest)
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

    private static func nonEmptyPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return path
    }
}

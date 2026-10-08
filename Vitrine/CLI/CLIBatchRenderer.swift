import Foundation
import OSLog
import VitrineDomain
import VitrineRendering

/// Owns folder discovery, output planning, reporting, and batch render orchestration.
enum CLIBatchRenderer {
    /// One skipped input in the optional batch JSON report.
    private struct SkippedReportEntry: Codable, Equatable {
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
    private struct BatchManifestEntry: Codable, Equatable {
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
        // Discover before creating the output folder, so a missing input leaves nothing
        // behind, and never treat earlier artifacts as new inputs on a re-run.
        let files = try batchInputFiles(
            in: inputDirectory,
            recursive: options.recursiveBatch,
            includeExtensions: options.batchIncludeExtensions,
            excludeExtensions: options.batchExcludeExtensions,
            excluding: excludedArtifacts(options, inputDirectory: inputDirectory),
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

        // Preflight the whole plan before writing anything: rendering a folder into itself
        // with a sidecar flag derives sidecar names from the output image, so file A's
        // `.md`/`.txt`/`.html` sidecar can land exactly on file B. Checked against every
        // discovered input, not just the current one, and before the render loop so a
        // rejected run leaves the folder untouched.
        // Ordered by source key so the first reported conflict is the same on every run.
        let plannedOutputs = outputURLs.keys.sorted().compactMap { outputURLs[$0] }
        try CLIOutputWriter.guardOutputsDoNotOverwriteInputs(
            beside: plannedOutputs, options: options, inputs: files)
        try guardReportTargets(
            options, outputURLs: plannedOutputs, inputs: files, inputDirectory: inputDirectory,
            outputDirectory: outputDirectory)
        if !options.dryRunBatch {
            do {
                try FileManager.default.createDirectory(
                    at: outputDirectory, withIntermediateDirectories: true)
            } catch {
                throw CLIError.writeFailed(path: options.outputPath)
            }
        }

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
                let reason = (error as? CLIError)?.message ?? "render or write failed"
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

    /// Paths a batch writes inside its own input tree: the output folder (unless it is the
    /// input folder itself) and the manifest and skipped-report files.
    private static func excludedArtifacts(
        _ options: CLIOptions, inputDirectory: URL
    ) -> (directory: String?, files: Set<String>) {
        let input = canonicalPath(inputDirectory)
        let output = canonicalPath(URL(fileURLWithPath: options.outputPath))
        let files = [options.batchManifestPath, options.skippedReportPath]
            .compactMap { $0 }.filter { !$0.isEmpty }
            .map { canonicalPath(URL(fileURLWithPath: $0)) }
        return (output == input ? nil : output, Set(files))
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Reports are outputs too: writing one over an image, sidecar, or the other
    /// report silently destroyed an artifact after the render loop claimed success.
    /// Check the complete plan before any output is created, including dry runs,
    /// which still write reports. Fold names like the image planner does so aliases
    /// on the default case-insensitive Mac filesystem cannot bypass the guard.
    private static func guardReportTargets(
        _ options: CLIOptions, outputURLs: [URL], inputs: [URL], inputDirectory: URL,
        outputDirectory: URL
    ) throws {
        let requested: [(path: String?, isManifest: Bool)] = [
            (options.batchManifestPath, true), (options.skippedReportPath, false),
        ]
        let reports: [(url: URL, isManifest: Bool)] = requested.compactMap { request in
            guard let path = request.path, !path.isEmpty else { return nil }
            return (URL(fileURLWithPath: path), request.isManifest)
        }
        guard !reports.isEmpty else { return }
        let resources = [options.backgroundImagePath, options.watermarkLogoPath]
            .compactMap { $0 }.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
        let artifactKeys = outputURLs.flatMap {
            ([$0] + CLIOutputWriter.sidecarURLs(options, beside: $0)).map(CLIOutputWriter.claimKey)
        }
        let outputDirectoryKey = CLIOutputWriter.claimKey(outputDirectory)
        // Discovered inputs, skipped ones included, are claimed too: a report spelled with
        // different case than the source escapes the exact-path discovery exclusion.
        var claimed = Set(artifactKeys + (inputs + resources).map(CLIOutputWriter.claimKey))
        for (report, isManifest) in reports {
            let key = CLIOutputWriter.claimKey(report)
            // A report cannot sit where the run creates a folder, or below a file it writes.
            let nested =
                key == outputDirectoryKey
                || artifactKeys.contains { $0.hasPrefix(key + "/") || key.hasPrefix($0 + "/") }
            guard !nested, claimed.insert(key).inserted else {
                throw CLIError.outputConflict(
                    "The batch report at \"\(report.path)\" conflicts with an input resource "
                        + "or another output. Choose distinct paths for resources and outputs.")
            }
            if options.noOverwrite, FileManager.default.fileExists(atPath: report.path) {
                throw CLIError.outputExists(path: report.path)
            }
            try guardExistingInputReport(
                report, isManifest: isManifest, inputDirectory: inputDirectory)
        }
    }

    /// A named report is excluded from discovery for repeat runs. That must not
    /// silently turn an existing source into an output. Recognize only the bounded,
    /// matching legacy report structure inside the input tree; this is structural
    /// recognition, not proof that Vitrine created the file.
    static let maximumExistingReportBytes = FileInputLoader.maximumByteCount

    private static func guardExistingInputReport(
        _ report: URL, isManifest: Bool, inputDirectory: URL
    ) throws {
        func contains(_ path: String, under root: String) -> Bool {
            path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
        let insideInput =
            contains(
                CLIOutputWriter.claimKey(report), under: CLIOutputWriter.claimKey(inputDirectory))
            || contains(
                report.standardizedFileURL.path, under: inputDirectory.standardizedFileURL.path)
        guard insideInput, FileManager.default.fileExists(atPath: report.path) else { return }
        guard
            let data = try? BoundedFileReader.read(from: report, limit: maximumExistingReportBytes),
            matchesReportStructure(data, isManifest: isManifest)
        else {
            throw CLIError.outputConflict(
                "The batch report at \"\(report.path)\" would replace an unrecognized input file. "
                    + "Choose a new report path or move the report outside the input folder.")
        }
    }

    private static func matchesReportStructure(_ data: Data, isManifest: Bool) -> Bool {
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        let required: Set<String> =
            isManifest
            ? ["input", "output", "sidecars", "language", "format", "status"]
            : ["path", "reason"]
        let allowed = isManifest ? required.union(["width", "height"]) : required
        let recognizedKeys = objects.allSatisfy {
            let keys = Set($0.keys)
            return required.isSubset(of: keys) && keys.isSubset(of: allowed)
        }
        guard recognizedKeys else { return false }
        let decoder = JSONDecoder()
        if isManifest {
            guard let entries = try? decoder.decode([BatchManifestEntry].self, from: data) else {
                return false
            }
            return entries.allSatisfy {
                !$0.input.isEmpty && !$0.output.isEmpty
                    && Language(rawValue: $0.language) != nil
                    && $0.sidecars.allSatisfy { !$0.isEmpty }
                    && ExportFormat(rawValue: $0.format) != nil
                    && (($0.status == "planned" && $0.width == nil && $0.height == nil)
                        || ($0.status == "rendered" && ($0.width ?? 0) > 0 && ($0.height ?? 0) > 0))
            }
        }
        guard let entries = try? decoder.decode([SkippedReportEntry].self, from: data) else {
            return false
        }
        return entries.allSatisfy { !$0.path.isEmpty && !$0.reason.isEmpty }
    }

    /// Lists regular files for batch rendering. Non-recursive mode keeps the legacy
    /// top-level behavior; recursive mode uses FileManager's enumerator so nested
    /// folders can be mirrored under the output directory.
    private static func batchInputFiles(
        in inputDirectory: URL,
        recursive: Bool,
        includeExtensions: Set<String>,
        excludeExtensions: Set<String>,
        excluding excluded: (directory: String?, files: Set<String>),
        directoryLister: (URL) throws -> [URL]
    ) throws -> [URL] {
        let entries: [URL]
        do {
            if recursive {
                var isDirectory: ObjCBool = false
                guard
                    FileManager.default.fileExists(
                        atPath: inputDirectory.path, isDirectory: &isDirectory),
                    isDirectory.boolValue,
                    let enumerator = FileManager.default.enumerator(
                        at: inputDirectory,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles])
                else { throw CLIError.inputUnreadable(path: inputDirectory.path) }
                var found: [URL] = []
                while let entry = enumerator.nextObject() as? URL {
                    if let directory = excluded.directory, canonicalPath(entry) == directory {
                        enumerator.skipDescendants()
                        continue
                    }
                    found.append(entry)
                }
                entries = found
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
            .filter { !excluded.files.contains(canonicalPath($0)) }
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

        // The per-group rename above is not enough on its own: a *recomputed* name can
        // land on a name another group never changed. `a.swift` + `a.py` collide on
        // `a.png` and become `a.swift.png`/`a.py.png` — but a third input literally named
        // `a.swift.txt` already owns `a.swift.png` via the legacy mapping, and whichever
        // rendered last silently replaced the other while the batch reported every file
        // as rendered. So the assignment claims names as it goes: any candidate that is
        // already taken gets a numeric discriminator before the image extension.
        // Iteration is sorted by input path, so which file keeps the plain name (and
        // which gets `-2`) never depends on directory-listing order.
        var outputs: [String: URL] = [:]
        var claimed: Set<String> = []
        for entry in baseRelativePaths.sorted(by: { $0.file.path < $1.file.path }) {
            let shouldPreserveInputExtension = (collisions[entry.relativePath]?.count ?? 0) > 1
            var relativePath = batchOutputRelativePath(
                for: entry.file, inputDirectory: inputDirectory, recursive: recursive,
                preservingInputExtension: shouldPreserveInputExtension, fileExtension: ext)
            if claimed.contains(filesystemKey(relativePath)) {
                let stem = (relativePath as NSString).deletingPathExtension
                var discriminator = 2
                while claimed.contains(filesystemKey("\(stem)-\(discriminator).\(ext)")) {
                    discriminator += 1
                }
                relativePath = "\(stem)-\(discriminator).\(ext)"
            }
            claimed.insert(filesystemKey(relativePath))
            outputs[batchOutputKey(for: entry.file)] = outputDirectory.appendingPathComponent(
                relativePath)
        }
        return outputs
    }

    /// The identity two output names share when the destination volume cannot tell them
    /// apart, used to claim names during batch planning.
    ///
    /// Swift string equality is exact, but the default macOS volume (APFS, and HFS+
    /// before it) is **case-insensitive** and compares normalized Unicode. So
    /// `a.swift.png` and `A.swift.png` are one file on disk: claiming them as distinct
    /// let one render silently overwrite the other while the summary reported both and
    /// the manifest listed two outputs. Reproduced on APFS — three inputs,
    /// `Rendered 3 images`, two files on disk.
    ///
    /// Folding here is deliberately one-directional: it decides *whether* a name is
    /// taken, never what gets written. The path itself keeps the author's casing, so a
    /// case-sensitive volume still receives exactly the names it always did.
    private static func filesystemKey(_ relativePath: String) -> String {
        relativePath.precomposedStringWithCanonicalMapping.lowercased()
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

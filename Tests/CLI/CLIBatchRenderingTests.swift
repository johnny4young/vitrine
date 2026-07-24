import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

/// Filesystem-level batch rendering, filtering, reporting, sidecar, and collision contracts.
@Suite("CLI batch rendering")
struct CLIBatchRenderingTests: CLITestSupport {
    @Test func batchRendersEveryTextFileInTheFolder() throws {
        let input = try makeTempDirectory()
        let output = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try "let a = 1".write(
            to: input.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "x = 1\n".write(
            to: input.appendingPathComponent("b.py"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse(["batch", input.path, "--out", output.path])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 2 image"))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("A.png").path))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("b.png").path))
    }

    @Test func batchReusesOneLocalImageBackgroundForEveryOutput() throws {
        let root = try makeTempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let background = root.appendingPathComponent("background.png")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let a = 1\n".write(
            to: input.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "let b = 2\n".write(
            to: input.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
        try writeFixtureImage(to: background, size: CGSize(width: 64, height: 40))
        let backgroundData = try Data(contentsOf: background)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--background-image", background.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 2 image"))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("A.png").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("B.png").path))
        #expect(try Data(contentsOf: background) == backgroundData)
    }

    @Test func batchFormattingKeepsRenderedAndCopyableSourceAligned() throws {
        let input = try makeTempDirectory()
        let output = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        let source = "struct Card {\nlet title = \"Vitrine\"\n}"
        try source.write(
            to: input.appendingPathComponent("Card.swift"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--format-code", "--text-sidecar",
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 1 image"))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Card.png").path))
        #expect(
            try String(
                contentsOf: output.appendingPathComponent("Card.txt"), encoding: .utf8)
                == "struct Card {\n  let title = \"Vitrine\"\n}")
    }

    @Test func batchCanRenderNestedFoldersRecursively() throws {
        let input = try makeTempDirectory()
        let output = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        let docs = input.appendingPathComponent("docs", isDirectory: true)
        let scripts = input.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "let title = \"Docs\"".write(
            to: docs.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
        try "print('script')\n".write(
            to: scripts.appendingPathComponent("Sample.py"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--recursive", "--sidecars", "text",
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 2 image"))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Sample.png").path))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Sample.txt").path))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("scripts/Sample.png").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: output.appendingPathComponent("Sample.png").path))
    }

    @Test func batchDryRunDoesNotWriteImagesOrSidecars() throws {
        let root = try makeTempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path,
            "--dry-run",
            "--sidecars", "text",
            "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Dry run: would render 1 image"))
        #expect(summary.contains("skipped 1"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: String]])
        #expect(decoded == [["path": "Blob.bin", "reason": "not readable text"]])
    }

    @Test func batchManifestListsRenderedOutputsWithRelativePathsAndDimensions() throws {
        let input = try makeTempDirectory()
        let output = try makeTempDirectory()
        let manifest = try makeTempDirectory().appendingPathComponent("manifest.json")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent())
        }
        let docs = input.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "let ok = true\n".write(
            to: docs.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--recursive", "--manifest", manifest.path,
            "--sidecars", "text,html",
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 1 image"))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Ok.txt").path))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Ok.html").path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]])
        let entry = try #require(decoded.first)
        #expect(entry["input"] as? String == "docs/Ok.swift")
        #expect(entry["output"] as? String == "docs/Ok.png")
        #expect(entry["sidecars"] as? [String] == ["docs/Ok.txt", "docs/Ok.html"])
        #expect(entry["language"] as? String == "swift")
        #expect(entry["format"] as? String == "png")
        #expect(entry["status"] as? String == "rendered")
        #expect((entry["width"] as? Int ?? 0) > 0)
        #expect((entry["height"] as? Int ?? 0) > 0)
    }

    @Test func batchJsonSummaryReportsRenderedAndSkippedCounts() throws {
        let root = try makeTempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--json", "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(summary.utf8)) as? [String: Any])
        #expect(decoded["command"] as? String == "batch")
        #expect(decoded["status"] as? String == "rendered")
        #expect(decoded["outputDirectory"] as? String == output.path)
        #expect(decoded["rendered"] as? Int == 1)
        #expect(decoded["skipped"] as? Int == 1)
        #expect(decoded["dryRun"] as? Bool == false)
        #expect(decoded["skippedReport"] as? String == report.path)
        #expect(decoded["manifest"] == nil)
    }

    @Test func batchDryRunManifestListsPlannedOutputsWithoutWritingImages() throws {
        let root = try makeTempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let manifest = root.appendingPathComponent("manifest.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "print('planned')\n".write(
            to: input.appendingPathComponent("Planned.py"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run", "--manifest", manifest.path,
            "--text-sidecar",
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Dry run: would render 1 image"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]])
        let entry = try #require(decoded.first)
        #expect(entry["input"] as? String == "Planned.py")
        #expect(entry["output"] as? String == "Planned.png")
        #expect(entry["sidecars"] as? [String] == ["Planned.txt"])
        #expect(entry["language"] as? String == "python")
        #expect(entry["status"] as? String == "planned")
        #expect(entry["width"] == nil)
        #expect(entry["height"] == nil)
    }

    @Test func batchManifestDisambiguatesSameStemOutputs() throws {
        let root = try makeTempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let manifest = root.appendingPathComponent("manifest.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let value = 1\n".write(
            to: input.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        try "export const value = 1\n".write(
            to: input.appendingPathComponent("Widget.ts"), atomically: true, encoding: .utf8)
        try "print('solo')\n".write(
            to: input.appendingPathComponent("Solo.py"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Solo.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run", "--manifest", manifest.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Dry run: would render 3 images"))
        #expect(summary.contains("skipped 1"))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]])
        let outputs = decoded.reduce(into: [String: String]()) { result, entry in
            if let input = entry["input"] as? String, let output = entry["output"] as? String {
                result[input] = output
            }
        }
        #expect(outputs["Solo.py"] == "Solo.png")
        #expect(outputs["Widget.swift"] == "Widget.swift.png")
        #expect(outputs["Widget.ts"] == "Widget.ts.png")
    }

    @Test func batchNoOverwriteSkipsExistingTargetsAndReportsThem() throws {
        let root = try makeTempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try "let old = true\n".write(
            to: input.appendingPathComponent("Old.swift"), atomically: true, encoding: .utf8)
        try "print('fresh')\n".write(
            to: input.appendingPathComponent("Fresh.py"), atomically: true, encoding: .utf8)
        let existing = output.appendingPathComponent("Old.png")
        try Data("existing image".utf8).write(to: existing)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--no-overwrite",
            "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 1 image"))
        #expect(summary.contains("skipped 1"))
        #expect(try Data(contentsOf: existing) == Data("existing image".utf8))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Fresh.png").path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: String]])
        #expect(decoded == [["path": "Old.swift", "reason": "output already exists"]])
    }

    @Test func batchFailOnEmptyFailsAfterWritingRequestedArtifacts() throws {
        let root = try makeTempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let manifest = root.appendingPathComponent("manifest.json")
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let ignored = true\n".write(
            to: input.appendingPathComponent("Ignored.swift"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run", "--include-ext", "go",
            "--fail-on-empty", "--manifest", manifest.path, "--skipped-report", report.path,
        ])

        #expect(throws: CLIError.batchEmpty(skipped: 0)) {
            try CLIRenderer.runBatch(options)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try String(contentsOf: manifest, encoding: .utf8) == "[]\n")
        #expect(try String(contentsOf: report, encoding: .utf8) == "[]\n")
    }

    @Test func batchExtensionFiltersAreAppliedBeforeLoading() throws {
        let input = try makeTempDirectory()
        let output = try makeTempDirectory()
        let report = try makeTempDirectory().appendingPathComponent("skipped.json")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: report.deletingLastPathComponent())
        }
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try "# Notes\n".write(
            to: input.appendingPathComponent("Guide.md"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))
        try "plain text".write(
            to: input.appendingPathComponent("README"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path,
            "--include-ext", ".swift,md",
            "--exclude-ext", "md",
            "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 1 image"))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Ok.png").path))
        #expect(
            !FileManager.default.fileExists(atPath: output.appendingPathComponent("Guide.png").path)
        )
        #expect(
            !FileManager.default.fileExists(atPath: output.appendingPathComponent("Blob.png").path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: String]])
        #expect(decoded.isEmpty)
    }

    @Test func batchCanFailWhenAnyFileIsSkippedAndStillWritesASkippedReport() throws {
        let input = try makeTempDirectory()
        let output = try makeTempDirectory()
        let report = try makeTempDirectory().appendingPathComponent("skipped.json")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: report.deletingLastPathComponent())
        }
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--fail-on-skipped",
            "--skipped-report", report.path,
        ])

        #expect(throws: CLIError.batchSkipped(rendered: 1, skipped: 1)) {
            try CLIRenderer.runBatch(options)
        }
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Ok.png").path))
        let data = try Data(contentsOf: report)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(decoded == [["path": "Blob.bin", "reason": "not readable text"]])
    }
}

import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

/// A batch never re-reads its own artifacts and keeps typed render failures readable.
@Suite("CLI batch artifacts")
struct CLIBatchArtifactTests: CLITestSupport {
    @Test(arguments: ["--manifest", "--skipped-report"])
    func anExistingSourceCannotBecomeAReport(flag: String) throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let nested = input.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)
        let target = nested.appendingPathComponent("source.swift")
        let malformed = [
            "let original = true\n", "{broken", "{\"input\":\"A.swift\"}", "[42]",
            "[{\"path\":\"A.swift\",\"reason\":false}]",
            "[{\"path\":\"A.swift\",\"reason\":\"skip\",\"source\":\"private\"}]",
        ]
        for contents in malformed {
            let original = Data(contents.utf8)
            try original.write(to: target)
            let options = try CLIArguments.parse([
                "batch", input.path, "--out", output.path, "--recursive", flag, target.path,
            ])
            #expect(throws: CLIError.self) { try CLIRenderer.runBatch(options) }
            #expect(try Data(contentsOf: target) == original)
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func oversizedExistingInputReportsAreRejectedBeforeOutput(flag: String) throws {
        let input = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: input) }
        let target = input.appendingPathComponent("report.json")
        let output = input.appendingPathComponent("cards", isDirectory: true)
        try Data("[]".utf8).write(to: target)
        let size = UInt64(CLIBatchRenderer.maximumExistingReportBytes + 1)
        let file = try FileHandle(forWritingTo: target)
        try file.truncate(atOffset: size)
        try file.close()
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, flag, target.path,
        ])

        #expect(throws: CLIError.self) { try CLIRenderer.runBatch(options) }
        #expect(try target.resourceValues(forKeys: [.fileSizeKey]).fileSize == Int(size))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func emptyPriorReportsCanBeReusedInsideNestedInputs(flag: String) throws {
        let input = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: input) }
        let nested = input.appendingPathComponent("nested", isDirectory: true)
        let output = input.appendingPathComponent("cards", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let target = nested.appendingPathComponent("report.json")
        try Data("[]\n".utf8).write(to: target)
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--recursive", "--dry-run",
            flag, target.path,
        ])

        for _ in 0..<2 {
            #expect(try CLIRenderer.runBatch(options).contains("would render 1 image"))
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func existingReportsMustMatchTheRequestedKind(flag: String) throws {
        let input = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: input) }
        let output = input.appendingPathComponent("cards", isDirectory: true)
        let target = input.appendingPathComponent("report.json")
        let manifest = """
            [{"input":"A.swift","output":"A.png","sidecars":[],
              "language":"swift","format":"png","status":"planned"}]
            """
        let skipped = #"[{"path":"A.swift","reason":"not readable text"}]"#
        let original = Data((flag == "--manifest" ? skipped : manifest).utf8)
        try original.write(to: target)
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, flag, target.path,
        ])

        #expect(throws: CLIError.self) { try CLIRenderer.runBatch(options) }
        #expect(try Data(contentsOf: target) == original)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func matchingNonemptyReportsCanBeReused(flag: String) throws {
        let input = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: input) }
        let output = input.appendingPathComponent("cards", isDirectory: true)
        let target = input.appendingPathComponent("report.json")
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)
        let manifest = """
            [{"input":"A.swift","output":"A.png","sidecars":[],"language":"swift",
              "format":"png","status":"rendered","width":32,"height":20}]
            """
        let skipped = #"[{"path":"A.swift","reason":"not readable text"}]"#
        try Data((flag == "--manifest" ? manifest : skipped).utf8).write(to: target)
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run", flag, target.path,
        ])

        #expect(try CLIRenderer.runBatch(options).contains("would render 1 image"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func reportsCannotReplaceBackgroundOrWatermarkResources(flag: String) throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let resource = root.appendingPathComponent("resource.png")
        let alias = root.appendingPathComponent("resource-alias.json")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)
        try writeFixtureImage(to: resource, size: CGSize(width: 32, height: 20))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: resource)
        let original = try Data(contentsOf: resource)

        for resourceFlag in ["--background-image", "--watermark-logo"] {
            for report in [resource, alias] {
                let options = try CLIArguments.parse([
                    "batch", input.path, "--out", output.path,
                    resourceFlag, resource.path, flag, report.path,
                ])
                #expect(throws: CLIError.self) { try CLIRenderer.runBatch(options) }
                #expect(try Data(contentsOf: resource) == original)
                #expect(!FileManager.default.fileExists(atPath: output.path))
                #expect(
                    try FileManager.default.destinationOfSymbolicLink(atPath: alias.path)
                        == resource.path)
            }
        }
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func reportsCannotOverwriteImagesOrSidecars(flag: String) throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)

        for name in ["A.png", "A.txt", "A.md", "A.html", "a.PNG"] {
            let options = try CLIArguments.parse([
                "batch", input.path, "--out", output.path, "--sidecars", "all",
                flag, output.appendingPathComponent(name).path,
            ])
            #expect(throws: CLIError.self) { try CLIRenderer.runBatch(options) }
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }

    @Test func anUnrecognizedInputReportIsARuntimeConflict() throws {
        let input = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: input) }
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)
        let target = input.appendingPathComponent("notes.json")
        let original = Data("{\"name\": \"config\"}".utf8)
        try original.write(to: target)
        let output = input.appendingPathComponent("cards", isDirectory: true)
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--manifest", target.path,
        ])

        expectOutputConflict { try CLIRenderer.runBatch(options) }
        #expect(try Data(contentsOf: target) == original)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func reportsCannotReplaceTheOutputFolderOrAPlannedOutputFolder(flag: String) throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        let nested = input.appendingPathComponent("docs", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try writeInput("let a = 1\n", named: "A.swift", in: nested)

        for report in [output, output.appendingPathComponent("docs")] {
            let options = try CLIArguments.parse([
                "batch", input.path, "--out", output.path, "--recursive", flag, report.path,
            ])
            expectOutputConflict { try CLIRenderer.runBatch(options) }
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }

    private func expectOutputConflict(_ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected the batch report conflict to be refused")
        } catch let error as CLIError {
            guard case .outputConflict = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(error.exitCode == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func reportsMustHaveDistinctPathsEvenDuringADryRun() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let report = root.appendingPathComponent("report.json")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run",
            "--manifest", report.path, "--skipped-report", report.path,
        ])
        #expect(throws: CLIError.self) { try CLIRenderer.runBatch(options) }
        #expect(!FileManager.default.fileExists(atPath: report.path))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func noOverwriteProtectsExistingReportsBeforeRendering(flag: String) throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let report = root.appendingPathComponent("report.json")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)
        let original = Data("previous report\n".utf8)
        try original.write(to: report)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--no-overwrite", flag, report.path,
        ])
        #expect(throws: CLIError.outputExists(path: report.path)) {
            try CLIRenderer.runBatch(options)
        }
        #expect(try Data(contentsOf: report) == original)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func skippedInputsAreStillProtectedFromSidecarWrites() throws {
        let input = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: input) }
        _ = try writeInput("let a = 1\n", named: "A.swift", in: input)
        let unreadable = input.appendingPathComponent("A.txt")
        let original = Data([0xFF, 0xFE, 0x00, 0x00])
        try original.write(to: unreadable)
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", input.path, "--text-sidecar",
        ])

        #expect(throws: CLIError.self) {
            try CLIBatchRenderer.run(
                options,
                fileLoader: { url in
                    if url.lastPathComponent == unreadable.lastPathComponent {
                        throw CLIError.inputUnreadable(path: url.path)
                    }
                    return FileInputLoader.LoadedFile(
                        text: "let a = 1\n", language: .swift, filename: url.lastPathComponent)
                })
        }
        #expect(try Data(contentsOf: unreadable) == original)
        #expect(!FileManager.default.fileExists(atPath: input.appendingPathComponent("A.png").path))
    }

    @Test func rerunningIntoANestedOutputFolderDoesNotRenderEarlierArtifacts() throws {
        let input = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: input) }
        try "let a = 1\n".write(
            to: input.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "# Notes\n".write(
            to: input.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let output = input.appendingPathComponent("cards", isDirectory: true)
        let manifest = input.appendingPathComponent("manifest.json")
        let report = input.appendingPathComponent("skipped.json")
        let arguments = [
            "batch", input.path, "--out", output.path, "--recursive", "--sidecars", "all",
            "--manifest", manifest.path, "--skipped-report", report.path,
            "--fail-on-skipped", "--json",
        ]

        for _ in 0..<2 {
            let summary = try CLIRenderer.runBatch(try CLIArguments.parse(arguments))
            #expect(summary.contains(#""rendered" : 2"#))
            #expect(summary.contains(#""skipped" : 0"#))
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: output.appendingPathComponent("cards").path))
    }

    @Test func aMissingInputFolderLeavesNoOutputFolderBehind() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("absent", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)

        for recursive in [false, true] {
            let options = try CLIArguments.parse(
                ["batch", missing.path, "--out", output.path] + (recursive ? ["--recursive"] : []))
            #expect(throws: CLIError.inputUnreadable(path: missing.path)) {
                try CLIRenderer.runBatch(options)
            }
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }

    @Test func anOversizedFileIsReportedWithItsRenderFailure() throws {
        let input = try makeTempDirectory()
        let output = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try String(repeating: "let bounded = true\n", count: 1_000).write(
            to: input.appendingPathComponent("Tall.swift"), atomically: true, encoding: .utf8)
        let report = output.appendingPathComponent("skipped.json")
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--scale", "3",
            "--skipped-report", report.path,
        ])

        _ = try CLIRenderer.runBatch(options)
        let entries = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: report))
                as? [[String: String]])
        #expect(entries.first?["reason"] == CLIError.renderTooLarge.message)
    }
}

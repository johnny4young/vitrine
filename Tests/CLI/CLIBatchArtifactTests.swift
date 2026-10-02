import Foundation
import Testing

@testable import VitrineCLICore

/// A batch never re-reads its own artifacts and keeps typed render failures readable.
@Suite("CLI batch artifacts")
struct CLIBatchArtifactTests: CLITestSupport {
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

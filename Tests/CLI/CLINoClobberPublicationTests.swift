import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

@Suite("CLI no-clobber applies at publication")
struct CLINoClobberPublicationTests: CLITestSupport {
    @Test(arguments: ["png", "txt", "md", "html"])
    func postPreflightWinnersSurviveRealRendering(extensionName: String) throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("card.png")
        let winner = directory.appendingPathComponent("card.\(extensionName)")
        let original = Data("another producer's completed artifact".utf8)
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "--out", output.path,
            "--no-overwrite", "--sidecars", "all",
        ])
        try CLIOutputWriter.guardNoOverwriteTargetsAvailable(beside: output, options: options)
        // The other producer commits after preflight, before our real render/write path.
        try original.write(to: winner)
        var config = SnapshotConfig()
        config.code = "let value = 42"
        config.language = .swift

        #expect(throws: CLIError.writeFailed(path: winner.path)) {
            _ = try CLIOutputWriter.renderAndWriteArtifact(config, options: options, to: output)
        }
        #expect(try Data(contentsOf: winner) == original)
        if extensionName != "png" {
            #expect(try decodePNG(at: output.path).width > 0)
        }
    }

    @Test(arguments: ["--manifest", "--skipped-report"])
    func batchReportsPreserveWinnersCreatedAfterRendering(flag: String) throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let report = root.appendingPathComponent("report.json")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        _ = try writeInput("let value = 42", named: "Card.swift", in: input)
        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--no-overwrite", flag, report.path,
        ])
        let original = Data("another producer's report".utf8)
        var reachedPublication = false

        #expect(throws: CLIError.writeFailed(path: report.path)) {
            try CLIBatchRenderer.run(
                options,
                beforeReports: {
                    reachedPublication = true
                    try original.write(to: report)
                })
        }

        #expect(reachedPublication)
        #expect(try Data(contentsOf: report) == original)
        #expect(try decodePNG(at: output.appendingPathComponent("Card.png").path).width > 0)
    }

    @Test func lateDanglingSymlinkIsPreservedAndNeverFollowed() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("manifest.json")
        let target = directory.appendingPathComponent("other.json")
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: target)

        #expect(throws: CLIError.writeFailed(path: output.path)) {
            try CLIOutputWriter.write(Data("new".utf8), to: output, noOverwrite: true)
        }
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: output.path) == target.path)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func defaultOverwriteModeStillReplacesAnExistingOutput() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("report.json")
        try Data("old".utf8).write(to: output)

        try CLIOutputWriter.write(Data("new".utf8), to: output, noOverwrite: false)

        #expect(try Data(contentsOf: output) == Data("new".utf8))
    }
}

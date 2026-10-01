import AppKit
import Darwin
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

/// Synthetic assembly-cost comparison, not a user study or a claim about human click speed.
@MainActor
@Suite("Documentation assembly benchmark")
struct DocumentationExportBenchmarkTests {
    @Test func tenSyntheticTasksRecordAssemblyTimeAndMemoryWithoutExtraRenders() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples: [(String, String, Language)] = [
            ("swift", "let answer = 42", .swift),
            ("unicode", "let label = \"説明 👩🏽‍💻\"", .swift),
            ("quotes", "print(\"<&>\")", .swift),
            ("fences", "```text\nexample\n```", .plaintext),
            ("terminal", "\u{1B}[32mPASS\u{1B}[0m", .terminal),
            ("cursor", "old\rnew\u{1B}[K", .terminal),
            ("multiline", "let a = 1\nlet b = 2", .swift),
            ("comment", "// Explain this result\nlet result = true", .swift),
            ("redaction", "safe\nPRIVATE_REDACTED_SENTINEL", .swift),
            ("description", "print(42)", .swift),
        ]
        var rows: [[String: Any]] = []
        let clock = ContinuousClock()
        for (label, source, language) in samples {
            var config = SnapshotConfig(code: source, language: language)
            if label == "redaction" { config.redactedLineRanges = [2...2] }
            config.altText = try SnapshotAltText.normalized("Synthetic \(label) documentation")
            let renderStart = clock.now
            let image = try ExportManager.renderCGImageChecked(config, scale: 1)
            let png = try #require(ExportManager.pngData(from: image))
            let renderTime = milliseconds(renderStart.duration(to: clock.now))
            let payload = DocumentationPackage(
                config: config, png: png, representations: [.markdown, .html, .text])
            let baseline = directory.appendingPathComponent("before-\(label)")
            try FileManager.default.createDirectory(
                at: baseline, withIntermediateDirectories: false)
            let before = clock.now
            // Existing separate-file assembly: the same renderer/builders, four writes.
            for (name, data) in payload.files {
                try data.write(to: baseline.appendingPathComponent(name), options: .atomic)
            }
            let beforeTime = milliseconds(before.duration(to: clock.now))
            let after = clock.now
            let result = try await DocumentationPackageWriter.write(
                payload, parent: directory, name: "after-\(label)")
            let afterTime = milliseconds(after.duration(to: clock.now))
            for (name, data) in payload.files {
                #expect(try Data(contentsOf: result.appendingPathComponent(name)) == data)
            }
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            rows.append([
                "task": label, "render_ms": renderTime, "separate_write_ms": beforeTime,
                "transaction_ms": afterTime, "separate_assembly_calls": payload.files.count,
                "transaction_calls": 1, "rasterizations": 1, "max_rss_bytes": usage.ru_maxrss,
            ])
        }
        #expect(rows.count == 10)
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        Attachment.record(data, named: "documentation-assembly-measurements.json")
        print("DOCUMENTATION-ASSEMBLY \(String(decoding: data, as: UTF8.self))")
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds)
            / 1_000_000_000_000_000
    }
}

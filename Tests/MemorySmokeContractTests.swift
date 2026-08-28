import Foundation
import Testing

/// Structural guard for the local dynamic-memory evidence lane.
///
/// The Python self-test covers parsing and baseline arithmetic. This suite protects the
/// repository-level contract around it: the real app journey stays isolated, retains raw
/// evidence, remains part of lint, and never degrades into a misleading zero-leak gate.
@Suite("Dynamic memory evidence contract")
struct MemorySmokeContractTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func text(_ components: String...) throws -> String {
        try String(
            contentsOf: components.reduce(repositoryRoot) { $0.appendingPathComponent($1) },
            encoding: .utf8)
    }

    @Test func runnerIsExecutableAndRetainsRawEvidence() throws {
        let path = Self.repositoryRoot.appendingPathComponent("scripts/run-memory-smoke.py")
        #expect(FileManager.default.isExecutableFile(atPath: path.path))

        let script = try Self.text("scripts", "run-memory-smoke.py")
        for required in [
            "VITRINE_USER_DEFAULTS_SUITE",
            "VITRINE_MEMORY_IMAGE_STORE_ISOLATED",
            "--outputGraph=",
            "--atExit",
            "--fullStacks",
            "--journey",
            "--snapshot-loop",
            "--memory-image-cycle",
            "--memory-window-churn",
            "--memory-web-snapshot-cycle",
            "VITRINE_MEMORY_IMAGE_CYCLE_COMPLETE",
            "VITRINE_MEMORY_WINDOW_CHURN_COMPLETE",
            "VITRINE_MEMORY_WEB_SNAPSHOT_CYCLE_COMPLETE",
            "editor-snapshot",
            "image-import-cycle",
            "window-churn",
            "web-snapshot-cycle",
            "journey_id",
            "comparable_journey",
            "working_tree_clean",
            "f\"{arguments.journey}.memgraph\"",
            "leaks.txt",
            "report.json",
        ] {
            #expect(script.contains(required), "memory smoke must retain \(required)")
        }
    }

    @Test func makeBuildsBeforeCaptureAndRunsParserSelfTestInLint() throws {
        let makefile = try Self.text("Makefile")
        #expect(makefile.contains("memory-smoke: build memory-smoke-check"))
        #expect(makefile.contains("memory-smoke-all: build memory-smoke-check"))
        #expect(makefile.contains("python3 scripts/run-memory-smoke.py --self-test"))
        #expect(makefile.contains(#"--journey "$(MEMORY_JOURNEY)""#))
        #expect(
            makefile.contains(
                "editor-snapshot image-import-cycle window-churn web-snapshot-cycle"))

        let lintLine = try #require(
            makefile.components(separatedBy: .newlines).first { $0.hasPrefix("lint:") })
        #expect(lintLine.contains("memory-smoke-check"))
    }

    @Test func imageJourneyOwnsItsTaskAndRequiresDebugIsolation() throws {
        let handler = try Self.text("Vitrine", "App", "AppLaunchArgumentHandler.swift")
        #expect(handler.contains("private var memoryJourneyTask: Task<Void, Never>?"))
        #expect(handler.contains("memoryJourneyTask?.cancel()"))
        #expect(handler.contains("debugIsolatedContainerRoot()"))
        #expect(handler.contains("session(for: .primary).settings"))
        #expect(handler.contains("unique-snapshots="))

        let store = try Self.text("Vitrine", "Models", "BackgroundImageStore.swift")
        #expect(store.contains("#if DEBUG"))
        #expect(store.contains("VITRINE_MEMORY_IMAGE_STORE_ISOLATED"))
        #expect(store.contains("SHA256.hash"))

        let journey = try Self.text("Vitrine", "App", "MemoryImageCycleJourney.swift")
        #expect(journey.contains("VITRINE_MEMORY_IMAGE_CYCLE_COMPLETE"))
        #expect(journey.contains("defer { settings.config.foregroundImage = nil }"))
        #expect(journey.contains("JourneyError.duplicateSnapshot"))
    }

    @Test func laneRequiresReviewInsteadOfInferringLeakOwnership() throws {
        let script = try Self.text("scripts", "run-memory-smoke.py")
        #expect(script.contains(#""status": "manual_review_required""#))
        #expect(script.contains("allocation path, not ownership"))
        #expect(script.contains("cannot prove the absence"))
        #expect(script.contains("Framework leaks are reported"))

        let documentation = try Self.text("docs", "RELEASING.md")
        #expect(documentation.contains("evidence lane, not a zero-leak CI gate"))
        #expect(documentation.contains("same clean"))
        #expect(documentation.contains("commit, OS, architecture, Xcode, and journey"))
        #expect(documentation.contains("generated evidence local"))
        #expect(documentation.contains("untracked"))
    }

    @Test func generatedEvidenceStaysIgnored() throws {
        let gitignore = try Self.text(".gitignore")
        #expect(
            gitignore.components(separatedBy: .newlines).contains("build/"),
            "raw memgraphs and reports must never become tracked release inputs")
    }
}

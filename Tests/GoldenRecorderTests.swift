import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

/// The golden-fixture **recorder** (CS-025).
///
/// This suite is the "single command" that regenerates the visual baseline:
/// `make record-goldens` runs only this suite with `VITRINE_RECORD_GOLDENS=1`. It
/// renders every `GoldenScenario` through the production export path and writes the
/// PNG fixtures plus the pinned-image `manifest.json` into
/// `Tests/Fixtures/Golden/`. A developer reviews and commits the resulting diff
/// when a deliberate visual change lands.
///
/// It is **opt-in**: every test is `enabled(if:)` the environment flag is set, so a
/// normal `make test` run never rewrites a single fixture. The recorder is
/// deliberately isolated from `GoldenImageTests` so the comparison suite can never
/// accidentally "fix" a regression by overwriting the baseline it is meant to
/// guard.
/// Whether the recorder is armed: the opt-in `VITRINE_RECORD_GOLDENS` flag must be
/// present and truthy. Off by default so a routine test run is read-only.
///
/// Defined as a free helper (not a static on `GoldenRecorderTests`) so the `@Suite`
/// trait below can reference it without the macro hitting a circular reference to
/// the type it is attached to.
enum GoldenRecording {
    /// `nonisolated` so the `@Suite(.enabled(if:))` trait — a `Sendable`,
    /// nonisolated closure — can read it; it only touches `ProcessInfo`, which is
    /// safe from any context.
    nonisolated static var isActive: Bool {
        guard let value = ProcessInfo.processInfo.environment["VITRINE_RECORD_GOLDENS"] else {
            return false
        }
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
    }
}

@MainActor
@Suite(
    "Golden recorder (CS-025)",
    .enabled(
        if: GoldenRecording.isActive,
        "set VITRINE_RECORD_GOLDENS=1 (make record-goldens) to (re)generate fixtures"))
struct GoldenRecorderTests {
    /// Renders every scenario, writes its PNG, and (re)writes the manifest pinned
    /// to this runner image. One test keeps the write atomic-ish: the PNGs and the
    /// manifest are produced together from the same render pass, so the pin always
    /// matches the bytes on disk.
    @Test func recordAllFixtures() throws {
        let directory = GoldenPaths.recordingOutputDirectory
        // Start from a clean staging directory so a stale file from a previous run
        // can never be copied into the committed baseline.
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        // The single machine-readable line `make record-goldens` parses to learn
        // where the (sandbox-remapped) staging files landed.
        print("GOLDEN OUTPUT \(directory.path)")

        var records: [String: GoldenManifest.ScenarioRecord] = [:]
        for scenario in GoldenScenario.allCases {
            let image = try #require(
                scenario.render(), "recording render failed for \(scenario.label)")
            let png = try #require(
                ExportManager.pngData(from: image), "PNG encode failed for \(scenario.label)")
            let url = directory.appendingPathComponent(scenario.fileName)
            try png.write(to: url)
            records[scenario.rawValue] = GoldenManifest.ScenarioRecord(
                width: image.width,
                height: image.height,
                configFingerprint: scenario.configFingerprint)
            print("GOLDEN RECORD \(scenario.label) \(image.width)x\(image.height) \(url.path)")
        }

        let manifest = GoldenManifest(
            schema: GoldenManifest.currentSchema,
            pinnedImage: .current(),
            scenarios: records)
        try manifest.encoded().write(to: GoldenManifest.url(in: directory))
        print(
            "GOLDEN RECORD manifest pinned to "
                + "\(manifest.pinnedImage.osVersion)/\(manifest.pinnedImage.architecture)/"
                + "swift\(manifest.pinnedImage.swiftVersion)")
    }
}

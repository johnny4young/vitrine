import AppKit
import Foundation
import Testing

@testable import Vitrine

/// CS-093 — the PRO multi-size one-pass export: one capture fanned out over
/// `ExportPreset` sizes into a folder. These pin the acceptance — N selected presets
/// write N correctly-named files in one action, and each file is byte-for-byte what a
/// single export with THAT preset selected (at its pinned scale) produces.
@Suite("Multi-size export · CS-093")
@MainActor
struct MultiSizeExportTests {
    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineMultiSize-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func baseConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        return config
    }

    @Test func writesOneFilePerSelectedPreset() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let presets = [ExportPreset.twitter, .linkedIn, .openGraph]

        let result = ExportManager.exportPresetSizes(
            baseConfig(), presets: presets, to: dir, format: .png)

        #expect(result.written == 3)
        #expect(result.failed == 0)
        for preset in presets {
            let url = dir.appendingPathComponent("vitrine-\(preset.id).png")
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func eachFileEqualsASingleExportWithThatPresetSelected() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = baseConfig()
        let preset = ExportPreset.openGraph

        _ = ExportManager.exportPresetSizes(base, presets: [preset], to: dir, format: .png)

        // The reference: exactly what a single export with this preset selected
        // produces — its presentation applied, rendered at its pinned size + scale.
        var single = base
        preset.apply(to: &single)
        let referenceImage = try #require(
            ExportManager.renderCGImage(
                single, scale: CGFloat(preset.scale), fixedSize: preset.sizing.fixedSize))
        let reference = try #require(ExportManager.pngData(from: referenceImage))

        let written = try Data(
            contentsOf: dir.appendingPathComponent("vitrine-\(preset.id).png"))
        #expect(written == reference)
    }

    @Test func textSidecarWritesATxtBesideEachImage() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let presets = [ExportPreset.twitter, .openGraph]

        let result = ExportManager.exportPresetSizes(
            baseConfig(), presets: presets, to: dir, format: .png, textSidecar: true)

        #expect(result.written == 2)
        #expect(result.failed == 0)
        for preset in presets {
            let txt = dir.appendingPathComponent("vitrine-\(preset.id).txt")
            #expect(FileManager.default.fileExists(atPath: txt.path))
            #expect((try? String(contentsOf: txt, encoding: .utf8)) == "let answer = 42")
        }
    }

    @Test func noTextSidecarByDefault() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = ExportManager.exportPresetSizes(
            baseConfig(), presets: [ExportPreset.twitter], to: dir)
        let txt = dir.appendingPathComponent("vitrine-\(ExportPreset.twitter.id).txt")
        #expect(!FileManager.default.fileExists(atPath: txt.path))
    }

    @Test func noPresetsWritesNothing() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = ExportManager.exportPresetSizes(baseConfig(), presets: [], to: dir)
        #expect(result == (written: 0, failed: 0))
        let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(contents?.isEmpty ?? true)
    }
}

import AppKit
import CoreGraphics
import Testing

@testable import Vitrine

/// Features #12/#33 — the reference-and-measurement band: the dimension-callout
/// ruler annotation and the floating pinned-snapshot window.
@Suite("Reference tools (measure + pin)")
@MainActor
struct ReferenceToolsTests {
    // MARK: - Measure (#12)

    @Test func measureChangesTheRenderedPixelsAndTracksItsSpan() throws {
        var plain = SnapshotConfig()
        plain.code = "let a = 1\nlet b = 2"
        var short = plain
        short.annotations = [
            Annotation(kind: .measure, start: CGPoint(x: 0.2, y: 0.5), end: CGPoint(x: 0.4, y: 0.5))
        ]
        var long = plain
        long.annotations = [
            Annotation(kind: .measure, start: CGPoint(x: 0.1, y: 0.5), end: CGPoint(x: 0.9, y: 0.5))
        ]
        #expect(try png(plain) != png(short), "a measure must change the exported image")
        #expect(
            try png(short) != png(long),
            "different spans must render different labels/shafts")
    }

    /// The measure is drag-placed, maps tool→kind, and uses both color and weight.
    @Test func measureToolContract() {
        #expect(!Annotation.Kind.measure.isPointPlaced)
        #expect(AnnotationTool.measure.kind == .measure)
        #expect(AnnotationTool.measure.usesThickness)
        #expect(AnnotationTool.measure.usesColor)
    }

    @Test func measureRoundTripsThroughPersistence() {
        let defaults = UserDefaults(suiteName: "VitrineReferenceTools-\(UUID().uuidString)")!
        var config = SnapshotConfig()
        config.annotations = [
            Annotation(
                kind: .measure, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.7, y: 0.2))
        ]
        SettingsCodec.persistStyle(config, to: defaults)
        let restored = SettingsCodec.readConfig(from: defaults).annotations
        #expect(restored.first?.kind == .measure)
        #expect(restored.first?.end == CGPoint(x: 0.7, y: 0.2))
    }

    // MARK: - Pinned snapshot (#33)

    /// Pinning shows a floating, all-Spaces panel; pinning again reuses the same
    /// panel (one reference at a time); unpinning hides it.
    @Test func pinShowsAFloatingPanelAndUnpinHidesIt() throws {
        let controller = PinnedSnapshotController.shared
        defer { controller.unpin() }

        let image = NSImage(size: NSSize(width: 400, height: 260), flipped: false) { rect in
            NSColor.systemIndigo.setFill()
            rect.fill()
            return true
        }
        controller.pin(image)
        #expect(controller.isPinned)

        let panel = try #require(
            NSApp.windows.compactMap { $0 as? NSPanel }
                .first { $0.accessibilityIdentifier() == "pinned-snapshot-window" })
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.isFloatingPanel)
        #expect(!panel.isReleasedWhenClosed, "closing must hide, not deallocate, the panel")

        // Re-pin replaces content in the same panel instance.
        controller.pin(image)
        let again =
            NSApp.windows.compactMap { $0 as? NSPanel }
            .filter { $0.accessibilityIdentifier() == "pinned-snapshot-window" }
        #expect(again.count == 1, "one pin at a time — the panel is reused")

        controller.unpin()
        #expect(!controller.isPinned)
    }

    /// A pinned image larger than the bound scales down keeping aspect; a small one
    /// is never upscaled.
    @Test func pinnedPanelBoundsItsInitialSize() throws {
        let controller = PinnedSnapshotController.shared
        defer { controller.unpin() }

        let huge = NSImage(size: NSSize(width: 2200, height: 1100), flipped: false) { _ in true }
        controller.pin(huge)
        let panel = try #require(
            NSApp.windows.compactMap { $0 as? NSPanel }
                .first { $0.accessibilityIdentifier() == "pinned-snapshot-window" })
        let content = panel.contentRect(forFrameRect: panel.frame).size
        #expect(content.width <= 440)
        #expect(abs(content.width / content.height - 2) < 0.05, "aspect is preserved")
    }

    // MARK: - Render helper

    private func png(
        _ config: SnapshotConfig, size: CGSize = CGSize(width: 320, height: 200)
    ) throws -> Data {
        let cg = try #require(ExportManager.renderCGImage(config, scale: 1, fixedSize: size))
        return try #require(ExportManager.pngData(from: cg))
    }
}

import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import Testing

@testable import Vitrine

/// Snapshot annotations (CS-083): the model round-trips, persists in the config,
/// and renders into the exported image. Pins that the default (no-annotation) path
/// is unaffected and that each kind actually changes pixels.
@MainActor
@Suite("Annotations (CS-083)")
struct AnnotationTests {
    // MARK: - Model

    @Test func codableRoundTripsEveryKind() throws {
        let original = [
            Annotation(kind: .arrow, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.8, y: 0.6)),
            Annotation(
                kind: .text, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
                text: "Hi", color: RGBAColor(Color(hex: "#00FF88"))),
            Annotation(kind: .blur, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.4, y: 0.4)),
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([Annotation].self, from: data)
        #expect(decoded == original)
    }

    @Test func geometryDenormalizesToCanvasPoints() {
        let annotation = Annotation(
            kind: .blur, start: CGPoint(x: 0.25, y: 0.5), end: CGPoint(x: 0.75, y: 1.0))
        let size = CGSize(width: 400, height: 200)
        #expect(annotation.startPoint(in: size) == CGPoint(x: 100, y: 100))
        #expect(annotation.endPoint(in: size) == CGPoint(x: 300, y: 200))
        #expect(annotation.rect(in: size) == CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    @Test func clampKeepsPointsOnCanvas() {
        #expect(Annotation.clampNormalized(CGPoint(x: -0.3, y: 1.4)) == CGPoint(x: 0, y: 1))
        #expect(Annotation.clampNormalized(CGPoint(x: 0.4, y: 0.9)) == CGPoint(x: 0.4, y: 0.9))
    }

    @Test func fingerprintIgnoresIDButTracksVisualState() {
        let a = Annotation(id: UUID(), kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))
        let b = Annotation(id: UUID(), kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))
        #expect(a.id != b.id)
        #expect(a.fingerprint == b.fingerprint, "the random id must not affect the fingerprint")

        var moved = a
        moved.end = CGPoint(x: 0.5, y: 0.5)
        #expect(
            moved.fingerprint != a.fingerprint, "moving an endpoint must change the fingerprint")
    }

    // MARK: - Content lifecycle

    @Test func clearContentMarksDropsAnnotationsAndHighlightsButKeepsStyle() {
        var config = SnapshotConfig()
        config.annotations = [Annotation(kind: .text, start: .zero, end: CGPoint(x: 1, y: 1))]
        config.highlightedLineRanges = [3...5]
        config.redactedLineRanges = [2...2]
        // Style + header that should survive a new capture (reusable, not content-bound).
        config.fontSize = 18
        config.metadata.title = "PR Review"
        let keptTheme = config.theme

        config.clearContentMarks()

        #expect(config.annotations.isEmpty)
        #expect(config.highlightedLineRanges.isEmpty)
        #expect(config.redactedLineRanges.isEmpty)
        #expect(config.fontSize == 18)
        #expect(config.metadata.title == "PR Review")
        #expect(config.theme == keptTheme)
    }

    // MARK: - Persistence

    @Test func persistsAndReadsBackThroughTheConfig() {
        let defaults = UserDefaults(suiteName: "VitrineAnnotationTests-\(UUID().uuidString)")!
        var config = SnapshotConfig()
        config.annotations = [
            Annotation(kind: .arrow, start: CGPoint(x: 0.3, y: 0.5), end: CGPoint(x: 0.6, y: 0.5)),
            Annotation(
                kind: .text, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
                text: "Note"),
            Annotation(
                kind: .counter, start: CGPoint(x: 0.4, y: 0.4), end: CGPoint(x: 0.4, y: 0.4),
                number: 1),
            Annotation(
                kind: .blur, start: CGPoint(x: 0.34, y: 0.44), end: CGPoint(x: 0.66, y: 0.56)),
        ]
        SettingsCodec.persistStyle(config, to: defaults)
        let restored = SettingsCodec.readConfig(from: defaults)
        #expect(restored.annotations == config.annotations)
    }

    @Test func emptyAnnotationsClearTheStoredKey() {
        let defaults = UserDefaults(suiteName: "VitrineAnnotationTests-\(UUID().uuidString)")!
        var config = SnapshotConfig()
        config.annotations = [
            Annotation(kind: .arrow, start: CGPoint(x: 0.3, y: 0.5), end: CGPoint(x: 0.6, y: 0.5))
        ]
        SettingsCodec.persistStyle(config, to: defaults)
        #expect(defaults.data(forKey: SettingsCodec.Keys.annotations) != nil)

        config.annotations = []
        SettingsCodec.persistStyle(config, to: defaults)
        #expect(defaults.data(forKey: SettingsCodec.Keys.annotations) == nil)
        #expect(SettingsCodec.readConfig(from: defaults).annotations.isEmpty)
    }

    @Test func corruptStoreDegradesToNoAnnotations() {
        let defaults = UserDefaults(suiteName: "VitrineAnnotationTests-\(UUID().uuidString)")!
        defaults.set(Data("not json".utf8), forKey: SettingsCodec.Keys.annotations)
        #expect(SettingsCodec.readConfig(from: defaults).annotations.isEmpty)
    }

    // MARK: - Rendering into the export

    /// Renders a config to PNG bytes through the same `SnapshotCanvas` +
    /// `ImageRenderer` path the exporter uses.
    private func png(
        _ config: SnapshotConfig, size: CGSize = CGSize(width: 320, height: 200)
    )
        throws -> Data
    {
        let renderer = ImageRenderer(content: SnapshotCanvas(config: config, fixedSize: size))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        let cg = try #require(renderer.cgImage)
        let normalized = ExportManager.normalized(cg, to: .sRGB)
        return try #require(ExportManager.pngData(from: normalized))
    }

    @Test func arrowChangesTheRenderedPixels() throws {
        var plain = SnapshotConfig()
        plain.code = "let x = 1"
        var arrowed = plain
        arrowed.annotations = [
            Annotation(kind: .arrow, start: CGPoint(x: 0.15, y: 0.5), end: CGPoint(x: 0.85, y: 0.5))
        ]
        #expect(try png(plain) != png(arrowed), "an arrow must change the exported image")
    }

    @Test func textCalloutChangesTheRenderedPixels() throws {
        var plain = SnapshotConfig()
        plain.code = "let x = 1"
        var texted = plain
        texted.annotations = [
            Annotation(
                kind: .text, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
                text: "SECRET")
        ]
        #expect(try png(plain) != png(texted), "a text callout must change the exported image")
    }

    // MARK: - Spotlight (feature #7)

    @Test func spotlightDimsTheRenderedPixels() throws {
        var plain = SnapshotConfig()
        plain.code = "let a = 1\nlet b = 2\nlet c = 3"
        var spotted = plain
        spotted.annotations = [
            Annotation(
                kind: .spotlight, start: CGPoint(x: 0.1, y: 0.3), end: CGPoint(x: 0.9, y: 0.5))
        ]
        #expect(try png(plain) != png(spotted), "a spotlight must dim the exported image")
    }

    /// The spotlight is drag-placed, maps tool→kind, and exposes neither color (the
    /// scrim is fixed) nor thickness.
    @Test func spotlightToolContract() {
        #expect(!Annotation.Kind.spotlight.isPointPlaced)
        #expect(AnnotationTool.spotlight.kind == .spotlight)
        #expect(!AnnotationTool.spotlight.usesThickness)
        #expect(!AnnotationTool.spotlight.usesColor)
    }

    /// A spotlight survives the persistence round-trip.
    @Test func spotlightRoundTripsThroughPersistence() {
        let defaults = UserDefaults(suiteName: "VitrineAnnotationTests-\(UUID().uuidString)")!
        var config = SnapshotConfig()
        config.annotations = [
            Annotation(
                kind: .spotlight, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.6, y: 0.5))
        ]
        SettingsCodec.persistStyle(config, to: defaults)
        let restored = SettingsCodec.readConfig(from: defaults).annotations
        #expect(restored.first?.kind == .spotlight)
        #expect(restored.first?.end == CGPoint(x: 0.6, y: 0.5))
    }

    // MARK: - Curved arrow (feature #11)

    @Test func curvedArrowChangesTheRenderedPixelsAndDiffersFromStraight() throws {
        var plain = SnapshotConfig()
        plain.code = "let x = 1"
        var straight = plain
        straight.annotations = [
            Annotation(kind: .arrow, start: CGPoint(x: 0.15, y: 0.5), end: CGPoint(x: 0.85, y: 0.5))
        ]
        var curved = plain
        curved.annotations = [
            Annotation(
                kind: .curvedArrow, start: CGPoint(x: 0.15, y: 0.5), end: CGPoint(x: 0.85, y: 0.5))
        ]
        #expect(try png(plain) != png(curved), "a curved arrow must change the exported image")
        #expect(
            try png(straight) != png(curved),
            "a curved arrow must render differently from a straight one over the same span")
    }

    /// The curved arrow is drag-placed (two free points), maps tool→kind, and exposes
    /// both the color swatch and the size slider like the straight arrow.
    @Test func curvedArrowToolContract() {
        #expect(!Annotation.Kind.curvedArrow.isPointPlaced)
        #expect(AnnotationTool.curvedArrow.kind == .curvedArrow)
        #expect(AnnotationTool.curvedArrow.usesThickness)
        #expect(AnnotationTool.curvedArrow.usesColor)
    }

    /// A curved arrow survives the persistence round-trip.
    @Test func curvedArrowRoundTripsThroughPersistence() {
        let defaults = UserDefaults(suiteName: "VitrineAnnotationTests-\(UUID().uuidString)")!
        var config = SnapshotConfig()
        config.annotations = [
            Annotation(
                kind: .curvedArrow, start: CGPoint(x: 0.2, y: 0.3), end: CGPoint(x: 0.8, y: 0.7),
                thickness: 6)
        ]
        SettingsCodec.persistStyle(config, to: defaults)
        let restored = SettingsCodec.readConfig(from: defaults).annotations
        #expect(restored.first?.kind == .curvedArrow)
        #expect(restored.first?.end == CGPoint(x: 0.8, y: 0.7))
    }

    // MARK: - Sticker layer (feature #13)

    @Test func stickerChangesTheRenderedPixels() throws {
        var plain = SnapshotConfig()
        plain.code = "let x = 1"
        var stickered = plain
        stickered.annotations = [
            Annotation(
                kind: .sticker, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
                text: "🔥", thickness: 12)
        ]
        #expect(try png(plain) != png(stickered), "a sticker must change the exported image")
    }

    /// A sticker is click-placed (like text/counter), the tool maps to its kind, it
    /// exposes the size slider but not the color swatch (an emoji has its own colors),
    /// and the glyph rides in `text` through `make`.
    @Test func stickerToolContractAndPlacement() {
        #expect(Annotation.Kind.sticker.isPointPlaced)
        #expect(AnnotationTool.sticker.kind == .sticker)
        #expect(AnnotationTool.sticker.usesThickness)
        #expect(!AnnotationTool.sticker.usesColor)
        #expect(!AnnotationTool.stickerChoices.isEmpty)

        let placed = Annotation.make(
            kind: .sticker, from: CGPoint(x: 0.4, y: 0.6), to: CGPoint(x: 0.4, y: 0.6),
            color: Annotation.defaultColor, thickness: 10, text: "👀")
        #expect(placed.text == "👀")
        #expect(placed.kind == .sticker)
    }

    /// A sticker survives the persistence round-trip (kind + glyph + anchor).
    @Test func stickerRoundTripsThroughPersistence() {
        let defaults = UserDefaults(suiteName: "VitrineAnnotationTests-\(UUID().uuidString)")!
        var config = SnapshotConfig()
        config.annotations = [
            Annotation(
                kind: .sticker, start: CGPoint(x: 0.25, y: 0.75), end: CGPoint(x: 0.25, y: 0.75),
                text: "🚀", thickness: 14)
        ]
        SettingsCodec.persistStyle(config, to: defaults)
        let restored = SettingsCodec.readConfig(from: defaults).annotations
        #expect(restored.count == 1)
        #expect(restored.first?.kind == .sticker)
        #expect(restored.first?.text == "🚀")
        #expect(restored.first?.start == CGPoint(x: 0.25, y: 0.75))
    }

    @Test func redactingALineChangesTheRenderedPixels() throws {
        // Both render row-by-row (line numbers on), so the only difference is the
        // redacted row mask — isolating redaction from the row-layout switch.
        var base = SnapshotConfig()
        base.code = "let key = \"AKIAIOSFODNN7EXAMPLE\"\nlet ok = 1"
        base.showLineNumbers = true
        var redacted = base
        redacted.redactedLineRanges = [1...1]
        #expect(
            try png(base) != png(redacted),
            "redacting a line must mask it and change the exported image")
    }

    @Test func redactedLinesAreRemovedFromCopyableSidecarText() {
        var config = SnapshotConfig()
        config.code = "let visible = 1\nlet hidden = \"runtime-only-secret\"\nlet tail = 2"
        config.redactedLineRanges = [2...2]

        #expect(!config.sidecarText.contains("runtime-only-secret"))
        #expect(
            config.sidecarText
                == "let visible = 1\n\(SnapshotConfig.redactedLinePlaceholder)\nlet tail = 2")
    }

    @Test func blurBoxChangesPixelsAndKeepsAValidImage() throws {
        var plain = SnapshotConfig()
        plain.code = "let secret = \"abc123\""
        var blurred = plain
        blurred.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.2, y: 0.3), end: CGPoint(x: 0.8, y: 0.6))
        ]
        let plainData = try png(plain)
        let blurredData = try png(blurred)
        #expect(plainData != blurredData, "a blur box must change the exported image")

        // The blurred export is still a full, decodable image of the requested size.
        let source = try #require(CGImageSourceCreateWithData(blurredData as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 320 && image.height == 200)
    }

    @Test func everyDrawableKindChangesThePixels() throws {
        var base = SnapshotConfig()
        base.code = "let x = 1\nlet y = 2\nlet z = 3"
        let plainData = try png(base)
        let marks: [Annotation] = [
            Annotation(kind: .line, start: CGPoint(x: 0.1, y: 0.5), end: CGPoint(x: 0.9, y: 0.5)),
            Annotation(
                kind: .rectangle, start: CGPoint(x: 0.2, y: 0.3), end: CGPoint(x: 0.8, y: 0.7)),
            Annotation(
                kind: .highlighter, start: CGPoint(x: 0.1, y: 0.45), end: CGPoint(x: 0.9, y: 0.55)),
            Annotation(
                kind: .counter, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5),
                number: 1),
        ]
        for mark in marks {
            var config = base
            config.annotations = [mark]
            #expect(try png(config) != plainData, "\(mark.kind) must change the exported image")
        }
    }

    // MARK: - Model: new fields & tools

    @Test func decodesLegacyAnnotationWithDefaultedFields() throws {
        // An annotation saved before thickness/number/text/color existed must still
        // decode, defaulting the missing fields rather than failing the whole array.
        let full = Annotation(
            kind: .arrow, start: CGPoint(x: 0.1, y: 0.2), end: CGPoint(x: 0.8, y: 0.6),
            thickness: 12, number: 3)
        let data = try JSONEncoder().encode(full)
        var dict = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        dict.removeValue(forKey: "thickness")
        dict.removeValue(forKey: "number")
        dict.removeValue(forKey: "text")
        dict.removeValue(forKey: "color")
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Annotation.self, from: legacy)
        #expect(decoded.kind == .arrow)
        #expect(decoded.thickness == Annotation.defaultThickness)
        #expect(decoded.number == 0)
        #expect(decoded.text.isEmpty)
    }

    @Test func everyDrawingToolMapsToAKindAndSelectDoesNot() {
        for tool in AnnotationTool.allCases {
            if tool == .select {
                #expect(tool.kind == nil)
            } else {
                #expect(tool.kind != nil, "\(tool) must draw a kind")
            }
        }
    }

    @Test func makeStartsTextCalloutsEmptyForInlineEditing() {
        // The editor opens a focused inline field on a fresh text callout, so it must
        // start empty rather than dropping a literal placeholder the user has to clear.
        let text = Annotation.make(
            kind: .text, from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.5, y: 0.5),
            color: Annotation.defaultColor, thickness: Annotation.defaultThickness)
        #expect(text.text.isEmpty)
    }

    @Test func isBlankTextOnlyFlagsEmptyTextCallouts() {
        func text(_ value: String) -> Annotation {
            Annotation(kind: .text, start: .zero, end: .zero, text: value)
        }
        #expect(text("").isBlankText)
        #expect(text("  \n\t ").isBlankText, "a whitespace-only callout counts as blank")
        #expect(!text("Hi").isBlankText)
        // Other kinds are never "blank text", even though they carry no text.
        #expect(!Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1)).isBlankText)
        #expect(!Annotation(kind: .counter, start: .zero, end: .zero, number: 1).isBlankText)
    }
}

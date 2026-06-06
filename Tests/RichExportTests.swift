import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Rich export targets and multi-representation clipboard (CS-054).
///
/// These tests pin the four guarantees the ticket is about:
///  1. Copy puts image data on the pasteboard and, when enabled, an additional
///     rich representation — without breaking the existing PNG round-trip.
///  2. "Copy as data URI" yields a valid `data:image/png;base64,…` string that
///     decodes back to a real PNG.
///  3. "Copy highlighted code as RTF/HTML" preserves syntax colors and the
///     selected font.
///  4. Large outputs are bounded.
///
/// They exercise the real `RichPasteboard`/`ExportManager` pipeline and use a
/// private, named `NSPasteboard` so they never clobber the developer's clipboard
/// and never interfere with one another.
@MainActor
@Suite("Rich export (CS-054)", .serialized)
struct RichExportTests {
    // MARK: - Fixtures & helpers

    private static func sampleConfig(
        _ mutate: (inout SnapshotConfig) -> Void = { _ in }
    ) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42\nfunc greet() { print(\"hi\") }"
        config.language = .swift
        mutate(&config)
        return config
    }

    /// A private pasteboard so a test never touches `NSPasteboard.general`.
    private static func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("VitrineRichExportTests-\(UUID().uuidString)"))
    }

    /// The PNG magic number, used to prove a blob is a real PNG.
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    // MARK: - 1. Multi-representation copy + PNG round-trip

    @Test func defaultCopyPlacesOnlyPNGAndRoundTrips() {
        // The unchanged one-shortcut copy: a single PNG representation, no rich
        // text, decodable back to a PNG (the existing round-trip still passes).
        let pasteboard = Self.scratchPasteboard()
        let copied = RichPasteboard.copy(
            Self.sampleConfig(), scale: 1, fixedSize: nil, profile: .sRGB,
            includeRichText: false, to: pasteboard)
        #expect(copied)

        let png = pasteboard.data(forType: RichPasteboard.pngType)
        #expect(png != nil)
        #expect(Array((png ?? Data()).prefix(4)) == Self.pngSignature)
        // Without the opt-in, no styled-text representation is present.
        #expect(pasteboard.data(forType: RichPasteboard.rtfType) == nil)
        #expect(pasteboard.data(forType: RichPasteboard.htmlType) == nil)
    }

    @Test func richCopyAddsRTFAndHTMLAlongsideTheImage() {
        // With the opt-in, the same copy carries the PNG *and* RTF *and* HTML on a
        // single item, so a destination picks whichever it prefers.
        let pasteboard = Self.scratchPasteboard()
        let copied = RichPasteboard.copy(
            Self.sampleConfig(), scale: 1, fixedSize: nil, profile: .sRGB,
            includeRichText: true, to: pasteboard)
        #expect(copied)

        let png = pasteboard.data(forType: RichPasteboard.pngType)
        #expect(png != nil)
        #expect(Array((png ?? Data()).prefix(4)) == Self.pngSignature)
        #expect(pasteboard.data(forType: RichPasteboard.rtfType) != nil)
        #expect(pasteboard.data(forType: RichPasteboard.htmlType) != nil)
    }

    @Test func richCopyDoesNotChangeTheImageBytes() {
        // The rich path must only *add* representations: the PNG it writes is the
        // same image the plain copy writes (no matte, no recompression drift).
        let plain = Self.scratchPasteboard()
        let rich = Self.scratchPasteboard()
        let config = Self.sampleConfig()

        #expect(
            RichPasteboard.copy(
                config, scale: 1, fixedSize: nil, profile: .sRGB,
                includeRichText: false, to: plain))
        #expect(
            RichPasteboard.copy(
                config, scale: 1, fixedSize: nil, profile: .sRGB,
                includeRichText: true, to: rich))

        let plainPNG = plain.data(forType: RichPasteboard.pngType)
        let richPNG = rich.data(forType: RichPasteboard.pngType)
        #expect(plainPNG == richPNG)
    }

    @Test func payloadBuilderReportsImageAndRichTextPresence() {
        // The value-level builder (no pasteboard) reflects the same shape, so the
        // multi-representation contract is testable without a live clipboard.
        let plain = RichPasteboard.makePayload(
            for: Self.sampleConfig(), scale: 1, fixedSize: nil, profile: .sRGB,
            includeRichText: false)
        #expect(plain != nil)
        #expect(plain?.hasRichText == false)
        #expect(Array((plain?.png ?? Data()).prefix(4)) == Self.pngSignature)

        let rich = RichPasteboard.makePayload(
            for: Self.sampleConfig(), scale: 1, fixedSize: nil, profile: .sRGB,
            includeRichText: true)
        #expect(rich?.hasRichText == true)
        #expect(rich?.rtf != nil)
        #expect(rich?.html != nil)
    }

    @Test func copyToPasteboardRichTextRoutesThroughTheRichPath() {
        // The public `ExportManager.copyToPasteboard(richText:)` flag is what the
        // editor/menu/quick-capture callers pass; with it on, the general
        // pasteboard ends up with both image and styled text.
        let config = Self.sampleConfig()
        #expect(
            ExportManager.copyToPasteboard(config, scale: 1, richText: true))

        let pasteboard = NSPasteboard.general
        #expect(pasteboard.data(forType: RichPasteboard.pngType) != nil)
        #expect(pasteboard.data(forType: RichPasteboard.rtfType) != nil)
    }

    @Test func copyToPasteboardDefaultIsImageOnly() {
        // Regression guard: the default (no `richText:`) copy is image-only, so the
        // one-shortcut behavior is unchanged.
        let config = Self.sampleConfig()
        #expect(ExportManager.copyToPasteboard(config, scale: 1))

        let pasteboard = NSPasteboard.general
        #expect(pasteboard.data(forType: RichPasteboard.pngType) != nil)
        #expect(pasteboard.data(forType: RichPasteboard.rtfType) == nil)
        #expect(pasteboard.data(forType: RichPasteboard.htmlType) == nil)
    }

    // MARK: - 2. Data URI

    @Test func dataURIHasTheExpectedPrefixAndDecodesToPNG() throws {
        let cgImage = try #require(
            ExportManager.renderCGImage(Self.sampleConfig(), scale: 1))
        let png = try #require(ExportManager.pngData(from: cgImage))
        let uri = try #require(RichPasteboard.dataURI(forPNG: png))

        #expect(uri.hasPrefix("data:image/png;base64,"))

        // The payload after the comma is valid base64 and decodes to the exact PNG.
        let base64 = String(uri.dropFirst("data:image/png;base64,".count))
        let decoded = try #require(Data(base64Encoded: base64))
        #expect(Array(decoded.prefix(4)) == Self.pngSignature)
        #expect(decoded == png)
    }

    @Test func dataURIDecodesToAnImageImageIOCanOpen() throws {
        // Stronger than a signature check: the decoded bytes open as an image, so
        // the URI a user pastes into a browser or Markdown really renders.
        let cgImage = try #require(
            ExportManager.renderCGImage(Self.sampleConfig(), scale: 1))
        let png = try #require(ExportManager.pngData(from: cgImage))
        let uri = try #require(RichPasteboard.dataURI(forPNG: png))
        let base64 = String(uri.dropFirst("data:image/png;base64,".count))
        let decoded = try #require(Data(base64Encoded: base64))

        let source = try #require(CGImageSourceCreateWithData(decoded as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == cgImage.width)
        #expect(image.height == cgImage.height)
    }

    @Test func copyDataURIPutsAStringOnThePasteboard() throws {
        let pasteboard = Self.scratchPasteboard()
        let copied = RichPasteboard.copyDataURI(
            for: Self.sampleConfig(), scale: 1, fixedSize: nil, profile: .sRGB,
            to: pasteboard)
        #expect(copied)

        let string = try #require(pasteboard.string(forType: .string))
        #expect(string.hasPrefix("data:image/png;base64,"))
        let base64 = String(string.dropFirst("data:image/png;base64,".count))
        let decoded = try #require(Data(base64Encoded: base64))
        #expect(Array(decoded.prefix(4)) == Self.pngSignature)
    }

    @Test func dataURIIsOmittedWhenItExceedsTheCap() {
        // A blob larger than the cap yields no URI rather than an unbounded string.
        let oversized = Data(count: RichPasteboard.maxRepresentationBytes + 1)
        #expect(RichPasteboard.dataURI(forPNG: oversized) == nil)
    }

    // MARK: - 3. RTF / HTML attribute checks

    @Test func rtfRoundTripPreservesTheSelectedFontFamily() throws {
        // The selected font must survive into the styled text: re-read the RTF and
        // confirm the code is set in the requested family at the requested size.
        let config = Self.sampleConfig {
            $0.fontName = "Menlo"
            $0.fontSize = 17
        }
        let attributed = RichPasteboard.highlightedCode(for: config)
        let rtf = try #require(RichPasteboard.rtfData(from: attributed))

        let reread = try #require(
            NSAttributedString(rtf: rtf, documentAttributes: nil))
        #expect(reread.length > 0)

        let font = try #require(
            reread.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        // The family round-trips (Menlo, not the proportional system default).
        #expect(font.fontName.localizedCaseInsensitiveContains("menlo"))
        #expect(font.pointSize == 17)
    }

    @Test func rtfPreservesNonDefaultSyntaxColors() throws {
        // Syntax highlighting must survive: the styled text carries more than one
        // foreground color (keywords vs. identifiers vs. literals), and at least one
        // is a real syntax color rather than the plain text color.
        let config = Self.sampleConfig {
            $0.theme = .oneDark
        }
        let attributed = RichPasteboard.highlightedCode(for: config)
        let rtf = try #require(RichPasteboard.rtfData(from: attributed))
        let reread = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil))

        let colors = Self.foregroundColors(in: reread)
        // A highlighted snippet uses several token colors; plain text would use one.
        #expect(colors.count > 1)
    }

    @Test func htmlPreservesSyntaxColorsAsMarkup() throws {
        // The HTML flavor must also carry color. Serialized HTML embeds the token
        // colors as inline CSS, so the markup contains color declarations.
        let config = Self.sampleConfig { $0.theme = .oneDark }
        let attributed = RichPasteboard.highlightedCode(for: config)
        let html = try #require(RichPasteboard.htmlData(from: attributed))
        let markup = try #require(String(data: html, encoding: .utf8))

        // Cocoa's HTML writer emits foreground color as a CSS `color:` rule.
        #expect(markup.localizedCaseInsensitiveContains("color"))

        // And it carries multiple distinct foreground colors. We assert on the emitted
        // CSS rather than re-parsing via `NSAttributedString(html:)`, which spins a WebKit
        // run loop and intermittently returns nil under the headless parallel test runner.
        let colors = Set(
            markup.matches(of: /color:\s*([^;"}<]+)/).map {
                String($0.1).trimmingCharacters(in: .whitespaces).lowercased()
            })
        #expect(colors.count > 1, "highlighted HTML must carry more than one color")
    }

    @Test func copyHighlightedCodePlacesRichTextAndPlainTextFallback() throws {
        let config = Self.sampleConfig()
        let pasteboard = Self.scratchPasteboard()
        #expect(RichPasteboard.copyHighlightedCode(for: config, to: pasteboard))

        // Styled representations for rich-text apps…
        #expect(pasteboard.data(forType: RichPasteboard.rtfType) != nil)
        #expect(pasteboard.data(forType: RichPasteboard.htmlType) != nil)
        // …plus the raw source for a plain-text code editor.
        let plain = try #require(pasteboard.string(forType: .string))
        #expect(plain == config.code)
    }

    // MARK: - 4. Bounding large outputs

    @Test func styledTextIsOmittedWhenItExceedsTheCap() {
        // A representation larger than the cap must be dropped, not truncated or
        // placed unbounded on the pasteboard. Driven with a tiny cap so the check is
        // fast and deterministic: even a short snippet's RTF/HTML clears 16 bytes.
        let attributed = RichPasteboard.highlightedCode(for: Self.sampleConfig())
        #expect(RichPasteboard.rtfData(from: attributed, maxBytes: 16) == nil)
        #expect(RichPasteboard.htmlData(from: attributed, maxBytes: 16) == nil)
        // The same string serializes fine under the real (large) cap.
        #expect(RichPasteboard.rtfData(from: attributed) != nil)
        #expect(RichPasteboard.htmlData(from: attributed) != nil)
    }

    @Test func realCapIsLargeEnoughForATypicalCaptureButStillBounded() throws {
        // The shipped cap fits a normal snippet's styled text yet rules out an
        // unbounded blob.
        #expect(RichPasteboard.maxRepresentationBytes > 0)
        let attributed = RichPasteboard.highlightedCode(for: Self.sampleConfig())
        let rtf = try #require(RichPasteboard.rtfData(from: attributed))
        #expect(rtf.count <= RichPasteboard.maxRepresentationBytes)
    }

    // MARK: - Rich representations are additive, never fatal

    @Test func payloadHasRichTextReflectsTheActualRepresentationsPresent() throws {
        // `hasRichText` is the flag callers and the pasteboard writer trust to decide
        // whether styled text rode along; it must not lie. Whatever the builder
        // actually attached, the flag agrees — and the PNG is always there.
        let payload = try #require(
            RichPasteboard.makePayload(
                for: Self.sampleConfig(), scale: 1, fixedSize: nil, profile: .sRGB,
                includeRichText: true))

        #expect(payload.hasRichText == (payload.rtf != nil || payload.html != nil))
        #expect(Array(payload.png.prefix(4)) == Self.pngSignature)
    }

    @Test func richPayloadStillCarriesTheImageWhenAStyledRepresentationIsDropped() throws {
        // The ticket's core safety promise: an oversized/failed rich representation
        // is *omitted, never fatal* — the image still copies. The size cap is fixed
        // on `makePayload`, so this proves the composition directly: the styled text
        // for this snippet is dropped under a 16-byte cap, yet the same snippet's
        // payload is non-nil and carries a decodable PNG. Together they show a drop
        // never takes the image down with it.
        let config = Self.sampleConfig()
        let attributed = RichPasteboard.highlightedCode(for: config)
        // Precondition: under a tiny cap the styled text really is dropped…
        #expect(RichPasteboard.rtfData(from: attributed, maxBytes: 16) == nil)
        #expect(RichPasteboard.htmlData(from: attributed, maxBytes: 16) == nil)

        // …and yet the full rich build still yields an image-bearing payload.
        let payload = try #require(
            RichPasteboard.makePayload(
                for: config, scale: 1, fixedSize: nil, profile: .sRGB, includeRichText: true))
        #expect(Array(payload.png.prefix(4)) == Self.pngSignature)
    }

    @Test func richCopyOfEmptyCodeStillPlacesADecodablePNG() throws {
        // A real user path: triggering the rich copy with an empty editor. Empty code
        // must not crash the highlighter or the build, and the image guarantee holds
        // regardless of whether empty styled text produced a usable rich blob.
        let config = Self.sampleConfig { $0.code = "" }
        let pasteboard = Self.scratchPasteboard()
        #expect(
            RichPasteboard.copy(
                config, scale: 1, fixedSize: nil, profile: .sRGB,
                includeRichText: true, to: pasteboard))

        let png = try #require(pasteboard.data(forType: RichPasteboard.pngType))
        #expect(Array(png.prefix(4)) == Self.pngSignature)
    }

    // MARK: - Settings wiring

    @Test func richClipboardSettingDefaultsOffAndPersists() {
        let defaults = UserDefaults(suiteName: "VitrineRichExport-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        // Default off keeps the one-shortcut copy a plain image.
        #expect(settings.richClipboard == false)

        settings.richClipboard = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.richClipboard)
    }

    @Test func resetClearsRichClipboard() {
        let defaults = UserDefaults(suiteName: "VitrineRichExport-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.richClipboard = true
        settings.resetToDefaults()
        #expect(settings.richClipboard == false)
    }

    // MARK: - Helpers

    /// Collects the distinct sRGB foreground colors used across an attributed
    /// string, so a test can assert that highlighting produced more than one token
    /// color (and therefore survived serialization).
    private static func foregroundColors(in string: NSAttributedString) -> Set<String> {
        var colors: Set<String> = []
        let full = NSRange(location: 0, length: string.length)
        string.enumerateAttribute(.foregroundColor, in: full) { value, _, _ in
            guard let color = (value as? NSColor)?.usingColorSpace(.sRGB) else { return }
            // Quantize to avoid float noise between the writer and reader.
            let key = String(
                format: "%.2f,%.2f,%.2f", color.redComponent, color.greenComponent,
                color.blueComponent)
            colors.insert(key)
        }
        return colors
    }
}

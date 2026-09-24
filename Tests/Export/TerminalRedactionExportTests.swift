import AppKit
import Foundation
import PDFKit
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Terminal redaction export", .serialized)
struct TerminalRedactionExportTests {
    @Test func cursorAddressedSecretIsRemovedFromEveryTextRepresentation() throws {
        let secret = "SYNTHETIC_SECRET_123456789"
        var config = SnapshotConfig()
        config.language = .terminal
        config.terminalColumns = 80
        config.code = "\u{1B}[32msafe\u{1B}[0m\u{1B}[2;1HAPI_KEY=\(secret)"
        let lines = SecretScanner.secretLines(in: config.sidecarText)
        try #require(lines == [2])
        config.redactedLineRanges = lines.map { $0...$0 }

        #expect(config.richClipboardText == config.sidecarText)
        #expect(config.richClipboardText.contains(secret) == false)
        let styled = RichPasteboard.highlightedCode(for: config)
        #expect(styled.string == config.sidecarText)
        let rtf = try #require(RichPasteboard.rtfData(from: styled))
        let decodedRTF = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil))
        #expect(decodedRTF.string.contains(secret) == false)
        #expect(decodedRTF.string.contains(SnapshotConfig.redactedLinePlaceholder))
        let html = try #require(RichPasteboard.htmlData(from: styled))
        #expect(String(decoding: html, as: UTF8.self).contains(secret) == false)

        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        var restored = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.code.contains(secret) == false)
        #expect(restored.sidecarText == config.sidecarText)
    }

    private static let marker = "SECR3T"
    private nonisolated static let streams: [String] = [
        "\u{1B}[32msafe\u{1B}[0m\u{1B}[2;1HSECR3T",
        "\u{1B}[1;1HabcdefghijklmnopSECR3T",
        "\u{1B}[1;1H界界界界界界界界SECR3T",
        "discarded\rSECR3T\nsafe",
        "shell$ \u{1B}[?1049h\u{1B}[2J\u{1B}[1;1Hsafe\u{1B}[2;1HSECR3T\u{1B}[?1049l",
        "\u{1B}[1;1Hsafe\u{1B}[2;4r\u{1B}[2;1Hgone\nSECR3T\nsafe\nend",
    ]

    @Test(arguments: streams)
    func resolvedRowsStaySanitizedAcrossExports(_ stream: String) throws {
        var config = SnapshotConfig(code: stream, language: .terminal)
        config.terminalColumns = 16
        let rows = config.sidecarText.components(separatedBy: "\n")
        let hidden = rows.indices.filter { rows[$0].contains(Self.marker) }
        try #require(hidden.count == 1)
        config.redactedLineRanges = hidden.map { ($0 + 1)...($0 + 1) }
        let expected = rows.enumerated().map { index, line in
            hidden.contains(index) ? SnapshotConfig.redactedLinePlaceholder : line
        }.joined(separator: "\n")
        #expect(config.sidecarText == expected)
        #expect(config.richClipboardText == expected)

        let image = try #require(ExportManager.renderCGImage(config, scale: 1))
        let payload = try #require(
            RichPasteboard.makePayload(
                cgImage: image, for: config, includeRichText: true, includePlainText: true))
        #expect(payload.plainText == expected)
        let rtf = try #require(payload.rtf)
        let decoded = try #require(NSAttributedString(rtf: rtf, documentAttributes: nil))
        #expect(decoded.string == expected)
        #expect(
            String(decoding: try #require(payload.html), as: UTF8.self).contains(Self.marker)
                == false)
        let markdown = try #require(
            RichPasteboard.markdownDocument(forPNG: payload.png, config: config))
        #expect(markdown.contains(Self.marker) == false)
        #expect(markdown.contains(expected))

        let pasteboard = NSPasteboard(name: .init("TerminalRedaction-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(RichPasteboard.copyHighlightedCode(for: config, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == expected)
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        var restored = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.sidecarText == expected)

        // An equally long substitute must produce the identical masked image: none of
        // the hidden glyphs may affect the exported pixels, not merely the text rider.
        var substitute = config
        substitute.code = stream.replacingOccurrences(of: Self.marker, with: "XXXXXX")
        let substituteImage = try #require(ExportManager.renderCGImage(substitute, scale: 1))
        #expect(ExportManager.pngData(from: substituteImage) == payload.png)
        var unredacted = config
        unredacted.redactedLineRanges = []
        let exposedImage = try #require(ExportManager.renderCGImage(unredacted, scale: 1))
        #expect(ExportManager.pngData(from: exposedImage) != payload.png)
        let pdf = try #require(ExportManager.pdfData(config))
        let document = try #require(PDFDocument(data: pdf))
        #expect(document.pageCount == 1)
        #expect(document.string?.contains(Self.marker) != true)
        let substitutePDF = try #require(ExportManager.pdfData(substitute))
        let exposedPDF = try #require(ExportManager.pdfData(unredacted))
        // PDF text extraction alone cannot prove that rasterized glyphs are hidden.
        // Compare the actual page raster against safe and deliberately exposed controls.
        let pixels = try pdfPixels(pdf)
        #expect(try pdfPixels(substitutePDF) == pixels)
        #expect(try pdfPixels(exposedPDF) != pixels)
    }

    private func pdfPixels(_ data: Data) throws -> Data {
        let document = try #require(PDFDocument(data: data))
        // PDFPage does not retain its document; drawing an orphan page yields no content.
        return try withExtendedLifetime(document) {
            let page = try #require(document.page(at: 0))
            let size = page.bounds(for: .mediaBox).size
            return try #require(page.thumbnail(of: size, for: .mediaBox).tiffRepresentation)
        }
    }

    @Test func redactingStyledFragmentsKeepsVisibleColorsAndNeutralizesHiddenAttributes() throws {
        let stream = "\u{1B}[32mvisible\n\u{1B}[31mSEC\u{1B}[1mR3T\n\u{1B}[34mtail"
        var config = SnapshotConfig(code: stream, language: .terminal)
        config.redactedLineRanges = [2...2]
        let styled = RichPasteboard.highlightedCode(for: config)
        #expect(styled.string == "visible\n[redacted]\ntail")
        let palette = ANSIPalette.forTheme(config.theme)
        #expect(
            styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == palette.base[2])
        #expect(
            styled.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor
                == palette.defaultForeground)
        #expect(
            styled.attribute(.foregroundColor, at: styled.length - 1, effectiveRange: nil)
                as? NSColor == palette.base[4])
        let font = try #require(styled.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold) == false)
    }

    @Test func redactionsPreserveEmptyRowsAndIgnoreOutOfBoundsRanges() {
        var config = SnapshotConfig(
            code: "safe\n\n\u{1B}[31msecret\u{1B}[0m\n", language: .terminal)
        config.redactedLineRanges = [2...3, 3...4, Int.max...Int.max]
        #expect(config.sidecarText == "safe\n[redacted]\n[redacted]\n[redacted]")
        #expect(RichPasteboard.highlightedCode(for: config).string == config.sidecarText)
    }

    @Test func highlightedCopyPlainTextMatchesTheResolvedScreen() {
        let config = SnapshotConfig(
            code: "hidden\r\u{1B}[2K\u{1B}[32mshown\u{1B}[0m", language: .terminal)
        let pasteboard = NSPasteboard(name: .init("TerminalRedaction-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(RichPasteboard.copyHighlightedCode(for: config, to: pasteboard))
        #expect(pasteboard.string(forType: .string) == config.sidecarText)
        #expect(pasteboard.string(forType: .string) == "shown")
    }

    @Test func narrowRedactedLinksKeepThePlaceholderOnOneRow() throws {
        var config = SnapshotConfig(
            code: "\u{1B}[1;1Hab\u{1B}[2;1HSECR\u{1B}[3;1Hcd", language: .terminal)
        config.terminalColumns = 4
        config.redactedLineRanges = [2...2]
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        var restored = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.sidecarText == config.sidecarText)
        #expect(restored.sidecarText.components(separatedBy: "\n")[1] == "[redacted]")
    }

    @Test func unredactedLinksRetainTheOriginalTerminalTranscript() throws {
        let code = "\u{1B}[32mvisible\u{1B}[0m\u{1B}[2;1Htail"
        let config = SnapshotConfig(code: code, language: .terminal)
        var restored = SnapshotConfig()
        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config))
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.code == code)
        #expect(restored.sidecarText == config.sidecarText)
    }

}

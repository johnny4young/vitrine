import AppKit
import Testing

@testable import Vitrine

/// Features #34/#39 — the input-intelligence band: on-device OCR of a beautified
/// image back into copyable text, and the inferred header title.
@Suite("Smart input (OCR + suggested title)")
@MainActor
struct SmartInputTests {
    // MARK: - Suggested title (#39)

    @Test func filenameChipWinsAndKeepsItsExtension() {
        var config = SnapshotConfig()
        config.code = "func ignored() {}"
        config.metadata = SnapshotMetadata(filename: "src/ContentView.swift")
        #expect(SuggestedFilename.suggestedTitle(for: config) == "ContentView.swift")
    }

    @Test func declaredIdentifierIsSuggestedWithoutAPrefix() {
        var config = SnapshotConfig()
        config.code = "struct PaymentsClient {\n    let retries = 3\n}"
        #expect(SuggestedFilename.suggestedTitle(for: config) == "PaymentsClient")
    }

    @Test func terminalAndUndeclaredCodeSuggestNothing() {
        var terminal = SnapshotConfig()
        terminal.language = .terminal
        terminal.code = "def hidden(): pass"
        #expect(SuggestedFilename.suggestedTitle(for: terminal) == nil)

        var plain = SnapshotConfig()
        plain.code = "x = 1\ny = 2"
        #expect(SuggestedFilename.suggestedTitle(for: plain) == nil)
    }

    // MARK: - OCR (#34)

    /// The full loop: render a snapshot of known code through the real export
    /// pipeline, then recognize it back. Asserts on distinctive tokens (not exact
    /// equality) so antialiasing/hinting variance never flakes the suite.
    @Test func recognizesRenderedCodeText() async throws {
        var config = SnapshotConfig()
        config.code = "func launchRocket() {\n    countdown(seconds: 10)\n}"
        config.fontSize = 18
        config.showLineNumbers = false
        let cgImage = try #require(ExportManager.renderCGImage(config, scale: 2))

        let text = try await ImageTextExtractor.recognizeText(in: cgImage)

        #expect(text.contains("launchRocket"))
        #expect(text.contains("countdown"))
        // Reading order: the declaration line comes before the body line.
        let declaration = try #require(text.range(of: "launchRocket"))
        let body = try #require(text.range(of: "countdown"))
        #expect(declaration.lowerBound < body.lowerBound)
    }

    @Test func blankImageYieldsEmptyText() async throws {
        let context = try #require(
            CGContext(
                data: nil, width: 220, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 220, height: 120))
        let blank = try #require(context.makeImage())

        let text = try await ImageTextExtractor.recognizeText(in: blank)
        #expect(text.isEmpty)
    }
}

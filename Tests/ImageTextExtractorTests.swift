import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import Vitrine

@Suite("On-device image text recognition", .timeLimit(.minutes(1)))
struct ImageTextExtractorTests {
    @Test func realRecognitionPreservesReadingOrderAndNormalizedBoxes() async throws {
        let image = try fixture(lines: ["Hello Vitrine", "Private on device"])
        let lines = try await ImageTextExtractor.recognizeLines(in: image)
        #expect(lines.map(\.text) == ["Hello Vitrine", "Private on device"])
        #expect(lines.count == 2)
        for line in lines {
            #expect(line.boundingBox.minX >= 0 && line.boundingBox.maxX <= 1)
            #expect(line.boundingBox.minY >= 0 && line.boundingBox.maxY <= 1)
            #expect(line.boundingBox.width > 0 && line.boundingBox.height > 0)
        }
        if lines.count == 2 {
            #expect(lines[0].boundingBox.minY > lines[1].boundingBox.minY)
        }
        #expect(
            try await ImageTextExtractor.recognizeText(in: image)
                == "Hello Vitrine\nPrivate on device")
    }

    @Test func blankImageReturnsNoText() async throws {
        #expect(try await ImageTextExtractor.recognizeText(in: fixture(lines: [])) == "")
    }

    @Test func alreadyCancelledRecognitionDoesNotStartVision() async throws {
        let image = try fixture(lines: ["Do not recognize"])
        let task = Task { try await ImageTextExtractor.recognizeText(in: image) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Synthetic text only. Core Text makes the source independent of screenshots,
    /// display scale, UI timing, and user clipboard contents.
    private func fixture(lines: [String]) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 800, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 240))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                "Menlo" as CFString, 36, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                gray: 0, alpha: 1),
        ]
        for (index, text) in lines.enumerated() {
            context.textPosition = CGPoint(x: 30, y: 175 - index * 70)
            CTLineDraw(
                CTLineCreateWithAttributedString(
                    NSAttributedString(string: text, attributes: attributes)), context)
        }
        return try #require(context.makeImage())
    }
}

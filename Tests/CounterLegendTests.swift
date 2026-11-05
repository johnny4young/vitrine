import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Counter legend")
struct CounterLegendTests {
    private func counter(_ number: Int, _ label: String = "", at y: Double = 0.3) -> Annotation {
        Annotation(
            kind: .counter, start: CGPoint(x: 0.2, y: y), end: CGPoint(x: 0.2, y: y),
            text: label, number: number)
    }

    private func config(_ annotations: [Annotation]) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "struct Counter {\n    var value = 0\n}\nlet port = 8080"
        config.language = .swift
        config.annotations = annotations
        return config
    }

    private func pixels(_ image: CGImage, height: Int? = nil) throws -> [UInt8] {
        let rows = height ?? image.height
        var bytes = [UInt8](repeating: 0, count: image.width * rows * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(
                CGContext(
                    data: buffer.baseAddress, width: image.width, height: rows,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // Core Graphics' origin is bottom-left: this keeps the image's top `rows`.
            context.draw(
                image,
                in: CGRect(
                    x: 0, y: rows - image.height, width: image.width, height: image.height))
        }
        return bytes
    }

    // MARK: - Entries

    @Test func entriesListLabeledCountersInBadgeOrder() {
        let text = Annotation(kind: .text, start: .zero, end: .zero, text: "not a legend")
        let entries = CounterLegend.entries(
            from: [counter(3, " third "), text, counter(2), counter(1, "first\nline")])
        #expect(entries.map(\.number) == [1, 3])
        #expect(entries.map(\.label) == ["first line", "third"])
    }

    @Test func aCaptureWithoutLabelsHasNoLegend() {
        #expect(config([]).counterLegend.isEmpty)
        #expect(config([counter(1), counter(2, "   ")]).counterLegend.isEmpty)
    }

    // MARK: - Redaction

    @Test func aSecretShapedLabelIsMaskedWhole() {
        let secret = "sk_live_" + String(repeating: "a1", count: 12)
        let legend = config([counter(1, "the key \(secret)")]).counterLegend
        #expect(legend.map(\.label) == [CounterLegend.mask])
    }

    @Test func aLabelMatchingARedactedLineIsMaskedWhole() {
        var capture = config([counter(1, "the hunter2long"), counter(2, "Counter value")])
        capture.code = "struct Counter {\n    let value = hunter2long\n    var value = 0\n}"
        capture.redactedLineRanges = [2...2]
        #expect(
            capture.counterLegend.map(\.label) == [CounterLegend.mask, "Counter value"],
            "words visible elsewhere in the code stay")
    }

    @Test(arguments: [
        "hunter 2long", "hunter-2long", "hunter2", "xhunter2long", "hunter\u{200D}2long",
        "HUNTER2LONG", "see hunter2",
    ])
    func aDisguisedCopyOfARedactedValueIsMasked(label: String) {
        var capture = config([counter(1, label)])
        capture.code = "let a = hunter2long\nlet b = 1"
        capture.redactedLineRanges = [1...1]
        #expect(capture.counterLegend.map(\.label) == [CounterLegend.mask])
        #expect(capture.isLegendLabelMasked(capture.annotations[0]))
    }

    @Test func aRedactedValueWrappedAcrossTerminalRowsIsMasked() {
        var capture = config([counter(1, "r2longv")])
        capture.language = .terminal
        capture.terminalColumns = 10
        capture.code = "\u{1B}[Hhunter2longvalue\u{1B}[3;1Hshown row"
        capture.redactedLineRanges = [1...2]
        #expect(capture.counterLegend.map(\.label) == [CounterLegend.mask])
    }

    @Test func aBlurredValueWrappedAcrossRowsIsCollected() {
        let hidden = CounterLegend.hiddenText(
            rows: ["token=hunter", "2longvalue", "short"], redactions: [], blurred: true,
            rowsMayWrap: true)
        #expect(CounterLegend.isMasked("hunter2longvalue", hiding: hidden))
    }

    @Test func redactedTerminalRowsAreCheckedOnTheFinalScreen() {
        var capture = config([counter(1, "token topsecretvalue")])
        capture.language = .terminal
        capture.code = "\u{1B}[31mfirst row\u{1B}[0m\ntopsecretvalue here\nlast row"
        capture.redactedLineRanges = [2...2]
        #expect(capture.counterLegend.map(\.label) == [CounterLegend.mask])
    }

    @Test func aBlurBoxHidesValuesButNotOrdinaryWords() {
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.5, y: 0.5))
        var capture = config([
            counter(1, "the struct"), counter(2, "swordfish"), counter(3, "on 8080"),
            counter(4, "tunafish"), blur,
        ])
        capture.code = """
            struct Counter {}
            let port = 8080
            let name = "swordfish"
            DB_PASSWORD=tunafish
            """
        #expect(
            capture.counterLegend.map(\.label) == [
                "the struct", CounterLegend.mask, CounterLegend.mask, CounterLegend.mask,
            ])
        capture.annotations.removeLast()
        #expect(
            capture.counterLegend.map(\.label) == [
                "the struct", "swordfish", "on 8080", "tunafish",
            ])
    }

    @Test func hiddenTextFollowsTheDocument() {
        var capture = config([counter(1, "hunter2long")])
        capture.code = "let a = hunter2long\nlet b = 1"
        capture.redactedLineRanges = [1...1]
        #expect(capture.counterLegend.map(\.label) == [CounterLegend.mask])
        capture.code = "let a = other2value\nlet b = 1"
        #expect(capture.counterLegend.map(\.label) == ["hunter2long"])
        capture.code = "let b = 1\nlet a = hunter2long"
        #expect(capture.counterLegend.map(\.label) == ["hunter2long"], "line 2 is visible")
        capture.redactedLineRanges = [2...2]
        #expect(capture.counterLegend.map(\.label) == [CounterLegend.mask])
    }

    @Test func theWholeLabelIsCheckedBeforeItIsCut() {
        let padding = String(repeating: "a ", count: 56)
        let secret = "sk_live_" + String(repeating: "a1", count: 12)
        #expect(
            config([counter(1, padding + secret)]).counterLegend.map(\.label)
                == [CounterLegend.mask])

        var capture = config([counter(1, padding + "hunter2longvalue")])
        capture.code = "let a = hunter2longvalue\nlet b = 1"
        capture.redactedLineRanges = [1...1]
        #expect(capture.counterLegend.map(\.label) == [CounterLegend.mask])

        let long = String(repeating: "word ", count: 40)
        let cut = config([counter(1, long)]).counterLegend.first?.label
        #expect(cut?.count == CounterLegend.maxLabelLength)
    }

    @Test func aSecretSplitByAZeroWidthJoinerIsStillASecret() {
        let secret =
            "sk_live_" + String(repeating: "a1", count: 6) + "\u{200D}"
            + String(repeating: "a1", count: 6)
        #expect(config([counter(1, secret)]).counterLegend.map(\.label) == [CounterLegend.mask])
    }

    // MARK: - Duplicating

    @Test func aDuplicatedCounterStartsWithoutALabelAndAStickerKeepsItsGlyph() {
        let canvas = CGSize(width: 400, height: 200)
        let copy = counter(1, "the struct").duplicated(in: canvas, counterNumber: 2)
        #expect(copy.number == 2)
        #expect(copy.text.isEmpty)
        let sticker = Annotation(kind: .sticker, start: .zero, end: .zero, text: "🔥")
        #expect(sticker.duplicated(in: canvas, counterNumber: 2).text == "🔥")
    }

    @Test func imageCapturesOnlyApplyTheSecretCheck() {
        var capture = config([counter(1, "hunter2long")])
        capture.code = "hunter2long"
        capture.redactedLineRanges = [1...1]
        capture.foregroundImage = ImageReference(fileName: "image.png")
        #expect(capture.counterLegend.map(\.label) == ["hunter2long"])
    }

    @Test func aShareLinkCarriesOnlyTheMaskedLabel() throws {
        var capture = config([counter(1, "see hunter2long")])
        capture.code = "let a = hunter2long\nlet b = 1"
        capture.redactedLineRanges = [1...1]

        let snapshot = SharedSnapshot(capturing: capture)
        let json = try #require(
            String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        #expect(!json.contains("hunter2long"))

        var reopened = SnapshotConfig()
        snapshot.apply(to: &reopened)
        #expect(reopened.annotations.first?.text == CounterLegend.mask)
        #expect(reopened.counterLegend.map(\.label) == [CounterLegend.mask])
    }

    @Test func legendTextStaysOutOfTextExports() {
        let plain = config([counter(1)])
        let labeled = config([counter(1, "secret plan")])
        #expect(labeled.sidecarText == plain.sidecarText)
        #expect(labeled.richClipboardText == plain.richClipboardText)
        #expect(labeled.altText == nil)
    }

    // MARK: - Render

    @Test func aLabelOnlyExtendsTheNaturalCanvasDownward() throws {
        let plain = try #require(ExportManager.renderCGImage(config([counter(1)]), scale: 1))
        let labeled = try #require(
            ExportManager.renderCGImage(config([counter(1, "the struct")]), scale: 1))

        #expect(labeled.width == plain.width)
        #expect(labeled.height > plain.height)
        // Same coordinate space: the capture and its badge land on the same pixels.
        // Gradient dithering follows the bitmap's height, so allow that much noise.
        let capture = try pixels(labeled, height: plain.height)
        let baseline = try pixels(plain)
        #expect(zip(capture, baseline).allSatisfy { abs(Int($0) - Int($1)) <= 4 })
    }

    @Test func aBlankLabelRendersLikeNoLabel() throws {
        let plain = try #require(ExportManager.renderCGImage(config([counter(1)]), scale: 1))
        let blank = try #require(ExportManager.renderCGImage(config([counter(1, "  ")]), scale: 1))
        #expect(blank.height == plain.height)
        #expect(try pixels(blank) == pixels(plain))
    }

    @Test func aLongLabelWrapsInsteadOfWideningTheCanvas() throws {
        let long = Array(repeating: "wrapping", count: 12).joined(separator: " ")
        let plain = try #require(ExportManager.renderCGImage(config([counter(1)]), scale: 1))
        let short = try #require(
            ExportManager.renderCGImage(config([counter(1, "short")]), scale: 1))
        let wrapped = try #require(
            ExportManager.renderCGImage(config([counter(1, long)]), scale: 1))

        #expect(wrapped.width == plain.width)
        #expect(wrapped.height > short.height)
    }

    @Test func aFixedFrameDrawsNoLegendAndReportsIt() throws {
        let frame = CGSize(width: 800, height: 600)
        let capture = config([counter(1, "the struct"), counter(2), counter(3, "the secret")])
        let fit = capture.counterLegendFit(in: frame)
        #expect(fit.entries.isEmpty)
        #expect(fit.dropped == 2)
        #expect(capture.counterLegendFit(in: nil).entries.count == 2)

        let plain = config([counter(1), counter(2), counter(3)])
        let unlabeled = try #require(
            ExportManager.renderCGImage(plain, scale: 1, fixedSize: frame))
        let image = try #require(
            ExportManager.renderCGImage(capture, scale: 1, fixedSize: frame))
        #expect(try pixels(image) == pixels(unlabeled))
    }

    @Test func aMaskedLabelRendersDifferentlyFromItsRawText() throws {
        var raw = config([counter(1, "see hunter2long")])
        raw.code = "let a = hunter2long\nlet b = 1"
        var redacted = raw
        redacted.redactedLineRanges = [1...1]
        var masked = redacted
        masked.annotations = [counter(1, CounterLegend.mask)]

        let hidden = try #require(ExportManager.renderCGImage(redacted, scale: 1))
        let expected = try #require(ExportManager.renderCGImage(masked, scale: 1))
        #expect(try pixels(hidden) == pixels(expected))
    }

    @Test func pdfExportCarriesTheBand() throws {
        let plain = try #require(ExportManager.pdfData(config([counter(1)])))
        let labeled = try #require(ExportManager.pdfData(config([counter(1, "the struct")])))
        func pageHeight(_ data: Data) throws -> CGFloat {
            let provider = try #require(CGDataProvider(data: data as CFData))
            let page = try #require(CGPDFDocument(provider)?.page(at: 1))
            return page.getBoxRect(.mediaBox).height
        }
        #expect(try pageHeight(labeled) > pageHeight(plain))
    }

    @Test(arguments: [2.0, 3.0])
    func theBandFillsTheBottomRow(scale: Double) throws {
        for lineCount in 1...4 {
            for fontSize in [13.0, 14.0, 15.0, 17.0] {
                var capture = config([counter(1, "the struct")])
                capture.code = (0..<lineCount).map { "let a\($0) = 1" }.joined(separator: "\n")
                capture.fontSize = fontSize
                let image = try #require(ExportManager.renderCGImage(capture, scale: scale))
                let bytes = try pixels(image)
                let lastRow = (image.height - 1) * image.width * 4
                let opaque = stride(from: lastRow + 3, to: bytes.count, by: 4)
                    .allSatisfy { bytes[$0] == 255 }
                #expect(opaque, "\(lineCount) lines at \(fontSize) pt")
            }
        }
    }

    // MARK: - Editing geometry

    @Test func editingActionsMeasureTheCanvasWithoutTheBand() {
        let geometry = PreviewCardGeometry()
        geometry.size = CGSize(width: 400, height: 240)
        geometry.legendHeight = 40
        #expect(geometry.canvasSize == CGSize(width: 400, height: 200))

        var mark = counter(1, at: 0.5)
        mark.nudge(by: CGSize(width: 0, height: 10), in: geometry.canvasSize)
        #expect(abs(mark.start.y - 0.55) < 0.0001, "10 pt of the 200 pt canvas")
    }
}

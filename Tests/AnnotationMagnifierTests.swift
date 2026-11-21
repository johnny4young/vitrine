import AppKit
import CoreGraphics
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

/// The magnifier: it enlarges only what the export already shows, blur boxes hide whatever
/// ends up under them, and no source can draw more than the capped number of lenses.
@MainActor
@Suite("Annotation magnifier")
struct AnnotationMagnifierTests {
    private let size = CGSize(width: 480, height: 300)

    private func image(_ config: SnapshotConfig) throws -> CGImage {
        let renderer = ImageRenderer(content: SnapshotCanvas(config: config, fixedSize: size))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        return ExportManager.normalized(try #require(renderer.cgImage), to: .sRGB)
    }

    private func png(_ config: SnapshotConfig) throws -> Data {
        try #require(ExportManager.pngData(from: image(config)))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    /// Mean luminance over `region`, in top-left canvas coordinates.
    private func luminance(_ image: CGImage, in region: CGRect) throws -> Double {
        let data = try pixels(image)
        var total = 0.0
        var count = 0.0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let index = (y * image.width + x) * 4
                total += 0.2126 * Double(data[index]) + 0.7152 * Double(data[index + 1])
                total += 0.0722 * Double(data[index + 2])
                count += 1
            }
        }
        return total / count
    }

    /// Summed luminance steps between neighbours: high for sharp text, low once blurred.
    private func edgeEnergy(_ image: CGImage, in region: CGRect) throws -> Double {
        let data = try pixels(image)
        func luma(_ x: Int, _ y: Int) -> Double {
            let index = (y * image.width + x) * 4
            return 0.2126 * Double(data[index]) + 0.7152 * Double(data[index + 1]) + 0.0722
                * Double(data[index + 2])
        }
        var total = 0.0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                total += abs(luma(x + 1, y) - luma(x, y)) + abs(luma(x, y + 1) - luma(x, y))
            }
        }
        return total
    }

    private var code: String {
        (1...10).map { "let secret\($0) = \"AKIA\($0)Q7XW2MZK9PLR4TV8\"" }.joined(separator: "\n")
    }

    private func lens(
        _ start: CGPoint = CGPoint(x: 0.3, y: 0.3), _ end: CGPoint = CGPoint(x: 0.7, y: 0.7)
    ) -> Annotation {
        var lens = Annotation(kind: .rectangle, start: start, end: end)
        lens.variant = .magnifier
        return lens
    }

    private func config(_ annotations: [Annotation]) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = code
        config.language = .plaintext
        config.annotations = annotations
        return config
    }

    /// The largest channel difference between two renders inside `region`.
    private func maxDifference(_ a: CGImage, _ b: CGImage, in region: CGRect) throws -> Int {
        let first = try pixels(a)
        let second = try pixels(b)
        var largest = 0
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let index = (y * a.width + x) * 4
                for channel in 0..<3 {
                    largest = max(
                        largest, abs(Int(first[index + channel]) - Int(second[index + channel])))
                }
            }
        }
        return largest
    }

    private func region(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
        CGRect(
            x: x0 * size.width, y: y0 * size.height, width: (x1 - x0) * size.width,
            height: (y1 - y0) * size.height)
    }

    /// The same capture with a different secret on the lines around the canvas centre.
    private func withOtherSecrets(_ config: SnapshotConfig) -> SnapshotConfig {
        var other = config
        other.code = code.split(separator: "\n").enumerated().map { index, line in
            (2...7).contains(index)
                ? line.replacingOccurrences(of: "Q7XW2MZK9PLR4TV8", with: "ZB3HN8YC0RJSU5EG")
                : String(line)
        }.joined(separator: "\n")
        return other
    }

    // MARK: - Redaction

    @Test func aMagnifierNeverSharpensABlurBox() throws {
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.02, y: 0.02), end: CGPoint(x: 0.98, y: 0.98))
        let centre = CGRect(x: size.width / 2 - 30, y: size.height / 2 - 20, width: 60, height: 40)
        let sharp = try edgeEnergy(image(config([lens()])), in: centre)
        let blurOnly = try edgeEnergy(image(config([blur])), in: centre)
        let both = try edgeEnergy(image(config([blur, lens()])), in: centre)
        #expect(sharp > both * 3, "the lens must show the text when unblurred")
        #expect(both <= blurOnly * 1.05, "the lens must not sharpen the blur")
    }

    /// A blur box over the edge of a lens hides the enlarged text there, even though that
    /// text comes from a spot of the content the box does not cover.
    @Test func aBlurBoxOverPartOfALensBlursTheEnlargedContent() throws {
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.56, y: 0.35), end: CGPoint(x: 0.7, y: 0.65))
        let region = CGRect(x: 0.58 * size.width, y: 0.4 * size.height, width: 40, height: 60)
        let sharp = try edgeEnergy(image(config([lens()])), in: region)
        let covered = try edgeEnergy(image(config([lens(), blur])), in: region)
        #expect(sharp > covered * 3, "the enlarged text under the box must be blurred")
    }

    /// A small blur box at the lens centre: the lens shows its enlarged copy around the box,
    /// where the box itself does not reach. Two different secrets must look the same there.
    @Test func theEnlargedCopyOfABlurBoxHidesItsContent() throws {
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.45, y: 0.45), end: CGPoint(x: 0.55, y: 0.55))
        // Inside the lens and outside the box: the enlarged copy of the box's own content.
        let copy = region(0.56, 0.47, 0.6, 0.53)
        let sharp = try maxDifference(
            image(config([lens()])), image(withOtherSecrets(config([lens()]))), in: copy)
        let covered = try maxDifference(
            image(config([lens(), blur])), image(withOtherSecrets(config([lens(), blur]))),
            in: copy)
        #expect(sharp > 100, "the region must show the secret without the box")
        // The blur filter rounds to within one level; no glyph detail survives.
        #expect(covered <= 2, "the enlarged blur must not differ with the secret")
    }

    /// Two overlapping lenses with a blur box over their overlap: whichever lens wins the
    /// overlap, the box blurs what ends up there.
    @Test func aBlurBoxOverOverlappingLensesBlursTheOverlap() throws {
        let left = lens(CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.55, y: 0.7))
        let right = lens(CGPoint(x: 0.45, y: 0.3), CGPoint(x: 0.8, y: 0.7))
        let blur = Annotation(
            kind: .blur, start: CGPoint(x: 0.45, y: 0.3), end: CGPoint(x: 0.55, y: 0.7))
        let overlap = region(0.47, 0.42, 0.53, 0.58)
        let sharp = try edgeEnergy(image(config([left, right])), in: overlap)
        let covered = try edgeEnergy(image(config([left, right, blur])), in: overlap)
        #expect(sharp > covered * 5, "the overlap must be blurred")
        #expect(
            try png(config([left, right])) != png(config([right])), "both lenses must draw")
    }

    @Test func aMagnifierShowsRedactedLinesAsRedacted() throws {
        var base = config([lens()])
        var other = base
        other.code = code.replacingOccurrences(
            of: "AKIA5Q7XW2MZK9PLR4TV8", with: "AKIA5ZZZZZZZZZZZZZZZZ")
        #expect(try png(base) == png(base), "renders of one input match")
        #expect(try png(base) != png(other), "the lens must cover the changed line")

        base.redactedLineRanges = [5...5]
        other.redactedLineRanges = [5...5]
        let inside = region(0.37, 0.37, 0.63, 0.63)
        // The first render after adding a redaction can differ from the next ones by one level.
        _ = try image(base)
        #expect(try maxDifference(image(base), image(other), in: inside) == 0)
        #expect(try png(base) == png(other), "a magnified redacted line must not reveal its text")
    }

    /// A mark inside a lens is enlarged with the content, so a mark covering a secret keeps
    /// covering its enlarged copy.
    @Test func marksInsideALensAreEnlargedToo() throws {
        let badge = Annotation(
            kind: .counter, start: CGPoint(x: 0.42, y: 0.5), end: CGPoint(x: 0.42, y: 0.5),
            number: 1)
        // The badge sits 0.08 left of the lens centre, so its enlarged copy is at 0.34.
        let copy = CGRect(x: 0.34 * size.width - 4, y: 0.5 * size.height - 4, width: 8, height: 8)
        let without = try luminance(image(config([lens()])), in: copy)
        let with = try luminance(image(config([lens(), badge])), in: copy)
        #expect(abs(with - without) > 20)
    }

    @Test func aLensInTheDimmedPartOfASpotlightIsDimmedToo() throws {
        let spotlight = Annotation(
            kind: .spotlight, start: CGPoint(x: 0.75, y: 0.05), end: CGPoint(x: 0.95, y: 0.25))
        let centre = CGRect(x: size.width / 2 - 20, y: size.height / 2 - 10, width: 40, height: 20)
        let lit = try luminance(image(config([lens()])), in: centre)
        let dimmed = try luminance(image(config([lens(), spotlight])), in: centre)
        #expect(dimmed < lit * 0.7)
    }

    // MARK: - Cap

    private func lenses(_ count: Int) -> [Annotation] { (0..<count).map { _ in lens() } }

    @Test func magnifiersPastTheCapBecomePlainBoxes() {
        let marks = [Annotation(kind: .arrow, start: .zero, end: .zero)] + lenses(6)
        let capped = marks.cappingMagnifiers()
        #expect(capped.count(where: \.isMagnifier) == Annotation.maxMagnifiers)
        #expect(capped.map(\.id) == marks.map(\.id))
        #expect(capped.suffix(2).allSatisfy { $0.kind == .rectangle && $0.variant == .standard })
    }

    @Test func aShareLinkCarriesAtMostTheCappedMagnifiers() throws {
        var snapshot = SharedSnapshot(capturing: SnapshotConfig())
        snapshot.annotations = lenses(9)
        let decoded = try SnapshotShareLink.snapshot(from: SnapshotShareLink.url(for: snapshot))
        #expect(decoded.annotations.count == 9)
        #expect(decoded.annotations.count(where: \.isMagnifier) == Annotation.maxMagnifiers)
        let captured = SharedSnapshot(capturing: config(lenses(9)))
        #expect(captured.annotations.count(where: \.isMagnifier) == Annotation.maxMagnifiers)
    }

    @Test func aRestoredWindowAndStyleAreCapped() throws {
        let archived = try JSONEncoder().encode(EditorWindowState(config: config(lenses(7))))
        let window = try #require(EditorWindowState.decoded(from: archived))
        #expect(window.annotations.count(where: \.isMagnifier) == Annotation.maxMagnifiers)

        let defaults = testDefaults()
        SettingsCodec.persistStyle(config(lenses(7)), to: defaults)
        let style = SettingsCodec.readConfig(from: defaults).annotations
        #expect(style.count == 7)
        #expect(style.count(where: \.isMagnifier) == Annotation.maxMagnifiers)
    }

    /// Lenses past the cap draw exactly like plain boxes: no lens and no ring.
    @Test func theCanvasDrawsLensesPastTheCapAsBoxes() throws {
        // One extra lens sits inside the first, so it is also drawn enlarged as a box.
        var inner = lens(CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.5, y: 0.5))
        inner.color = RGBAColor(red: 0, green: 0.8, blue: 0.2, opacity: 1)
        let extra = lenses(3).map {
            var lens = $0
            lens.start = CGPoint(x: 0.6, y: 0.6)
            lens.end = CGPoint(x: 0.95, y: 0.95)
            return lens
        }
        let uncapped = config(lenses(Annotation.maxMagnifiers) + extra + [inner])
        var boxes = uncapped
        for index in Annotation.maxMagnifiers..<boxes.annotations.count {
            boxes.annotations[index].variant = .standard
        }
        #expect(try png(uncapped) == png(boxes))
    }

    private func pinnedComment(at point: CGPoint) -> Annotation {
        Annotation(
            kind: .text, start: point, end: point, text: "Pinned",
            lineAnchor: DiffLineAnchor(row: 1, side: .new))
    }

    @Test func lensesPastTheCapStayBoxesBesideAPinnedComment() throws {
        let comment = pinnedComment(at: CGPoint(x: 0.1, y: 0.1))
        let uncapped = config([comment] + lenses(Annotation.maxMagnifiers + 2))
        var boxes = uncapped
        for index in (Annotation.maxMagnifiers + 1)..<boxes.annotations.count {
            boxes.annotations[index].variant = .standard
        }
        #expect(try png(uncapped) == png(boxes))
    }

    /// A pinned comment's own point is stale, so a lens must not enlarge it there.
    @Test func aLensLeavesPinnedCommentsToTheirLine() throws {
        let comment = pinnedComment(at: CGPoint(x: 0.42, y: 0.5))
        #expect(try png(config([lens(), comment])) == png(config([lens()])))
    }
}

import AppKit
import Foundation
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@Suite("Optical margins", .serialized)
@MainActor
struct OpticalMarginsTests {
    private func config(_ mode: PaddingMode, shadow: Bool = true) -> SnapshotConfig {
        var config = SnapshotConfig(code: "let answer = 42", language: .swift)
        config.paddingMode = mode
        config.showShadow = shadow
        return config
    }

    // MARK: Geometry

    @Test func theDefaultShadowIsCountedAndTheCardSitsAboveCenter() {
        let insets = OpticalMargins.insets(margin: 32, shadow: config(.balanced).cardShadow)
        #expect(insets == EdgeInsets(top: 31, leading: 42, bottom: 53, trailing: 42))
    }

    @Test func withoutAShadowOnlyTheLiftRemains() {
        let insets = OpticalMargins.insets(margin: 32, shadow: .none)
        #expect(insets == EdgeInsets(top: 29, leading: 32, bottom: 35, trailing: 32))
    }

    @Test func aSidewaysShadowWidensItsOwnSide() {
        let shadow = Brand.ShadowStyle(color: .black, radius: 20, x: 6, y: 0)
        let insets = OpticalMargins.insets(margin: 20, shadow: shadow)
        #expect(insets.leading == 24)
        #expect(insets.trailing == 36)
    }

    @Test func manualKeepsTheSamePaddingOnEveryEdgeAndCentersTheCard() {
        var manual = config(.manual)
        manual.padding = 40
        #expect(manual.canvasInsets == EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40))
        #expect(manual.canvasAlignment == .center)
        #expect(config(.balanced).canvasAlignment.vertical == .opticalCenter)
    }

    @Test func theCardShadowFollowsTheToggleAndDepth() {
        #expect(config(.manual, shadow: false).cardShadow == .none)
        var deep = config(.manual)
        deep.shadowRadius = 36
        #expect(deep.cardShadow.radius == 36)
        #expect(deep.cardShadow.y == Brand.Shadow.elevated.y)
    }

    @Test func theSwitchBindingMapsToTheMode() {
        var style = config(.manual)
        style.balancesPadding = true
        #expect(style.paddingMode == .balanced)
        style.balancesPadding = false
        #expect(style.paddingMode == .manual)
    }

    // MARK: Rendering

    @Test func aHuggingCanvasGrowsByTheBalancedInsets() throws {
        let manual = try #require(ExportManager.renderCGImage(config(.manual), scale: 1))
        let balanced = try #require(ExportManager.renderCGImage(config(.balanced), scale: 1))
        #expect(balanced.width - manual.width == 42 * 2 - 32 * 2)
        #expect(balanced.height - manual.height == 31 + 53 - 32 * 2)
    }

    @Test func theOpticalCenterPutsLessOfTheFreeSpaceAbove() throws {
        let image = try #require(
            ImageRenderer(
                content: Color.red.frame(width: 10, height: 100)
                    .frame(
                        width: 10, height: 300,
                        alignment: Alignment(horizontal: .center, vertical: .opticalCenter))
            ).cgImage)
        let bitmap = try rgba(image)
        let rows = (0..<bitmap.height).filter { bitmap.bytes[($0 * bitmap.width) * 4 + 3] > 128 }
        #expect(rows.first == 92)
        #expect(rows.last == 191)
    }

    private let frame = CGSize(width: 600, height: 600)

    /// Rows holding the opaque card on a transparent canvas; the shadow stays under the cut.
    private func cardRows(_ mode: PaddingMode, shadow: Bool) throws -> ClosedRange<Int> {
        var style = config(mode, shadow: shadow)
        style.background = .transparent
        let image = try #require(ExportManager.renderCGImage(style, scale: 1, fixedSize: frame))
        let bitmap = try rgba(image)
        let rows = (0..<bitmap.height).filter { row in
            (0..<bitmap.width).contains { bitmap.bytes[(row * bitmap.width + $0) * 4 + 3] > 128 }
        }
        return try #require(rows.first)...#require(rows.last)
    }

    @Test func aFixedFrameLiftsTheBalancedCard() throws {
        let manual = try cardRows(.manual, shadow: false)
        let balanced = try cardRows(.balanced, shadow: false)
        #expect(manual.count == balanced.count)
        #expect(abs(manual.lowerBound - (599 - manual.upperBound)) <= 1)
        let above = Double(balanced.lowerBound)
        let below = Double(599 - balanced.upperBound)
        #expect(abs(above / (above + below) - Double(OpticalMargins.topShare)) < 0.01)
    }

    /// The shadow falls below the card, so its padded block reaches lower and the card rises.
    @Test func aFixedFrameCountsTheShadowBelowTheCard() throws {
        let card = try cardRows(.balanced, shadow: true)
        let insets = config(.balanced).canvasInsets
        let block = CGFloat(card.count) + insets.top + insets.bottom
        let top =
            (frame.height * OpticalMargins.topShare).rounded()
            - (block * OpticalMargins.topShare).rounded() + insets.top
        #expect(abs(card.lowerBound - Int(top)) <= 1)
        #expect(card.lowerBound < (try cardRows(.balanced, shadow: false)).lowerBound)
    }

    // MARK: Blur boxes

    private func blurred(_ mode: PaddingMode) -> SnapshotConfig {
        var style = config(mode)
        style.code = (1...8).map { "let value\($0) = \"item-\($0 * 7919)\"" }
            .joined(separator: "\n")
        style.annotations = [
            Annotation(kind: .blur, start: CGPoint(x: 0.2, y: 0.3), end: CGPoint(x: 0.7, y: 0.6))
        ]
        return style
    }

    /// The blurred pixels, measured from the card's top-leading corner.
    private func blurredRegion(_ style: SnapshotConfig) throws -> CGRect {
        var sharp = style
        sharp.annotations = []
        let a = try rgba(try #require(ExportManager.renderCGImage(style, scale: 1)))
        let b = try rgba(try #require(ExportManager.renderCGImage(sharp, scale: 1)))
        try #require(a.width == b.width && a.height == b.height)
        var region = CGRect.null
        for index in stride(from: 0, to: a.bytes.count, by: 4) {
            let delta = (0..<3).map { abs(Int(a.bytes[index + $0]) - Int(b.bytes[index + $0])) }
            guard delta.contains(where: { $0 > 8 }) else { continue }
            let pixel = index / 4
            region = region.union(
                CGRect(x: pixel % a.width, y: pixel / a.width, width: 1, height: 1))
        }
        let insets = style.canvasInsets
        return region.offsetBy(dx: -insets.leading, dy: -insets.top)
    }

    @Test func blurBoxesKeepTheModeSoTheyCoverTheSameCode() throws {
        let manual = blurred(.manual)
        var document = manual
        document.balancesPadding = true
        StyleSnapshot(capturing: blurred(.balanced)).apply(to: &document)
        #expect(document.locksPaddingMode)
        #expect(document.paddingMode == .manual)
        let covered = try blurredRegion(manual)
        #expect(!covered.isNull)
        #expect(try blurredRegion(document) == covered)

        // Without the lock the same normalized box lands on different code.
        #expect(try blurredRegion(blurred(.balanced)) != covered)
    }

    @Test func aBalancedDocumentKeepsItsModeUnderNewBlurBoxes() {
        var document = blurred(.balanced)
        StyleSnapshot(capturing: config(.manual)).apply(to: &document)
        document.balancesPadding = false
        #expect(document.paddingMode == .balanced)
    }

    private func rgba(_ image: CGImage) throws -> (bytes: [UInt8], width: Int, height: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return (bytes, image.width, image.height)
    }

    // MARK: Persistence

    @Test func manualLeavesEncodedStylesUnchanged() throws {
        let json = try String(
            decoding: JSONEncoder().encode(StyleSnapshot(capturing: config(.manual))),
            as: UTF8.self)
        #expect(json.contains("paddingMode") == false)
    }

    @Test func presetsRecipesAndShareLinksCarryBalance() throws {
        let style = StyleSnapshot(capturing: config(.balanced))
        #expect(style.paddingMode == .balanced)
        var applied = config(.manual)
        style.apply(to: &applied)
        #expect(applied.paddingMode == .balanced)

        let recipe = WorkspaceRecipe(name: "Balanced", style: style)
        let data = try WorkspaceRecipeDocument(recipe: recipe).jsonData()
        #expect(try WorkspaceRecipeDocument.recipe(from: data).style.paddingMode == .balanced)

        let url = try SnapshotShareLink.url(for: SharedSnapshot(capturing: config(.balanced)))
        var restored = SnapshotConfig()
        try SnapshotShareLink.snapshot(from: url).apply(to: &restored)
        #expect(restored.paddingMode == .balanced)
    }

    @Test func anUnknownValueFallsBackInAPresetButFailsARecipe() throws {
        let json = #"{"themeID":"dracula","paddingMode":"golden"}"#
        let style = try JSONDecoder().decode(StyleSnapshot.self, from: Data(json.utf8))
        #expect(style.paddingMode == nil)
        let decoder = JSONDecoder()
        decoder.userInfo[StyleSnapshot.strictDecodingKey] = true
        #expect(throws: DecodingError.self) {
            try decoder.decode(StyleSnapshot.self, from: Data(json.utf8))
        }
    }

    @Test func savedSettingsAndOlderWindowsDegradeToManual() throws {
        let defaults = testDefaults()
        defaults.set("golden", forKey: SettingsCodec.Keys.paddingMode)
        #expect(SettingsCodec.readConfig(from: defaults).paddingMode == .manual)

        let themes = CustomThemeStore(defaults: testDefaults())
        let older = try #require(EditorWindowState.decoded(from: Data("{}".utf8)))
        #expect(older.config(themes: themes).paddingMode == .manual)
        #expect(EditorWindowState(config: config(.manual)).paddingMode == nil)
    }
}

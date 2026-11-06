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
        let rows = try opaqueRows(image)
        #expect(rows == 92...191)
    }

    @Test func aFixedFrameLiftsTheBalancedCard() throws {
        func cardRows(_ mode: PaddingMode) throws -> ClosedRange<Int> {
            var style = config(mode, shadow: false)
            style.background = .transparent
            let size = CGSize(width: 600, height: 600)
            let image = try #require(ExportManager.renderCGImage(style, scale: 1, fixedSize: size))
            return try opaqueRows(image)
        }
        let manual = try cardRows(.manual)
        let balanced = try cardRows(.balanced)
        #expect(manual.count == balanced.count)
        #expect(abs(manual.lowerBound - (599 - manual.upperBound)) <= 1)
        let above = Double(balanced.lowerBound)
        let below = Double(599 - balanced.upperBound)
        #expect(abs(above / (above + below) - Double(OpticalMargins.topShare)) < 0.01)
    }

    private func opaqueRows(_ image: CGImage) throws -> ClosedRange<Int> {
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
        let rows = (0..<image.height).filter { row in
            (0..<image.width).contains { bytes[(row * image.width + $0) * 4 + 3] > 128 }
        }
        return try #require(rows.first)...#require(rows.last)
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

import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import VitrineDomain

@testable import VitrineRendering

@MainActor
@Suite("Magic background")
struct MagicBackgroundTests {
    private static let code = """
        import SwiftUI

        // A small counter.
        struct CounterView: View {
            @State private var count = 0
            var body: some View {
                Button("Tapped \\(count) times") { count += 1 }
            }
        }
        """

    private func theme(background: String, foreground: String) throws -> Theme {
        Theme(
            id: "custom.magic.\(background).\(foreground)", displayName: "Magic",
            palette: ThemePalette(
                background: try #require(HexColor(background)),
                foreground: try #require(HexColor(foreground))))
    }

    private func config(_ code: String = code, theme: Theme = .oneDark) -> SnapshotConfig {
        var config = SnapshotConfig(code: code, language: .swift)
        config.theme = theme
        return config
    }

    private func hue(_ color: RGBAColor) -> Double { MagicBackground.HSL(color).hue }

    @Test func theSameCaptureAlwaysDerivesTheSameGradients() throws {
        let first = MagicBackground.gradients(for: config())
        #expect(first.count >= 2)
        #expect(MagicBackground.gradients(for: config()) == first)
        let data = try JSONEncoder().encode(
            BackgroundStyle.customGradient(try #require(first.first)))
        #expect(
            try JSONDecoder().decode(BackgroundStyle.self, from: data)
                == .customGradient(try #require(first.first)))
    }

    @Test func gradientsFollowTheInkTheTextIsDrawnIn() throws {
        let theme = try theme(background: "#101010", foreground: "#E0402A")
        let gradient = try #require(MagicBackground.gradients(for: config(theme: theme)).first)
        let ink = try #require(RGBAColor(hex: "#E0402A"))
        #expect(MagicBackground.hueDistance(hue(gradient.stops[0].color), hue(ink)) < 0.02)
    }

    @Test(arguments: [Theme.oneDark, Theme.github])
    func everyStopLeavesTheCardStandingOff(_ theme: Theme) throws {
        let card = try #require(
            ThemeLegibility.cardColor(theme: theme, language: .swift, palette: .theme))
        let cardColor = RGBAColor(
            red: card.redComponent, green: card.greenComponent, blue: card.blueComponent,
            opacity: 1)
        let gradients = MagicBackground.gradients(for: config(theme: theme))
        #expect(!gradients.isEmpty)
        for stop in gradients.flatMap(\.stops) {
            #expect(MagicBackground.contrast(stop.color, cardColor) >= Brand.Contrast.aaLarge)
        }
    }

    @Test func anEmptyCaptureStillOffersANeutralPair() throws {
        let gradients = MagicBackground.gradients(for: config(""))
        let first = try #require(gradients.first)
        #expect(first.stops.allSatisfy { MagicBackground.HSL($0.color).saturation <= 0.13 })
    }

    @Test func aTranslucentCardKeepsTheTextReadableOnEveryStop() throws {
        let theme = try theme(background: "#00000080", foreground: "#FFFFFF")
        var probe = config(theme: theme)
        let gradients = MagicBackground.gradients(for: probe)
        #expect(!gradients.isEmpty)
        probe.showShadow = false
        for stop in gradients.flatMap(\.stops) {
            probe.background = .solid(stop.color)
            let report = try #require(ThemeLegibility.measure(ThemeLegibility.Input(probe)))
            #expect(!report.isWeak)
        }
    }

    @Test func paletteRanksByWeightAndKeepsHuesApart() throws {
        let red = try #require(RGBAColor(hex: "#D03030"))
        let nearRed = try #require(RGBAColor(hex: "#D04030"))
        let blue = try #require(RGBAColor(hex: "#3050D0"))
        let gray = try #require(RGBAColor(hex: "#808080"))
        let palette = MagicBackground.palette(
            from: [
                .init(color: gray, weight: 0.5), .init(color: blue, weight: 0.2),
                .init(color: nearRed, weight: 0.1), .init(color: red, weight: 0.3),
                .init(color: blue, weight: 0),
            ],
            card: nil)
        #expect(palette.count == 2)
        #expect(MagicBackground.hueDistance(hue(palette[0]), hue(red)) < 0.02)
        #expect(MagicBackground.hueDistance(hue(palette[1]), hue(blue)) < 0.02)
    }

    @Test func oneHueGetsAnAnalogousPartnerAndVariantsNeverRepeat() throws {
        let red = try #require(RGBAColor(hex: "#D03030"))
        let palette = MagicBackground.palette(from: [.init(color: red, weight: 1)], card: nil)
        #expect(palette.count == 2)
        let gradients = MagicBackground.variants(of: palette, card: nil)
        #expect(Set(gradients).count == gradients.count)
        #expect(gradients.map(\.angle) == [135, 45, 120, 90])
        #expect(MagicBackground.variants(of: [], card: nil).isEmpty)
    }

    @Test func hslRoundTripsThroughEverySector() throws {
        for hex in ["#D03030", "#D0D030", "#30D030", "#30D0D0", "#3030D0", "#D030D0", "#808080"] {
            let color = try #require(RGBAColor(hex: hex))
            let back = MagicBackground.HSL(color).color
            #expect(abs(back.red - color.red) < 0.001, "\(hex)")
            #expect(abs(back.green - color.green) < 0.001, "\(hex)")
            #expect(abs(back.blue - color.blue) < 0.001, "\(hex)")
        }
    }

    @Test func anImageGivesItsDominantColors() async throws {
        let url = try Self.writeImage(halves: (Self.red, Self.blue))
        defer { try? FileManager.default.removeItem(at: url) }
        let gradients = await MagicBackground.gradients(forImageAt: url)
        #expect(await MagicBackground.gradients(forImageAt: url) == gradients)
        let hues = try #require(gradients.first).stops.map { hue($0.color) }
        let red = hue(RGBAColor(red: 0.9, green: 0.2, blue: 0.15, opacity: 1))
        let blue = hue(RGBAColor(red: 0.15, green: 0.3, blue: 0.9, opacity: 1))
        #expect(hues.contains { MagicBackground.hueDistance($0, red) < 0.05 })
        #expect(hues.contains { MagicBackground.hueDistance($0, blue) < 0.05 })
    }

    @Test func somethingThatIsNotAnImageGivesNothing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magic-\(UUID().uuidString).txt")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(MagicBackground.swatches(ofImageAt: url).isEmpty)
    }

    private static let red = NSColor(srgbRed: 0.9, green: 0.2, blue: 0.15, alpha: 1)
    private static let blue = NSColor(srgbRed: 0.15, green: 0.3, blue: 0.9, alpha: 1)

    private static func writeImage(halves: (NSColor, NSColor)) throws -> URL {
        let side = 64
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(halves.0.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
        context.setFillColor(halves.1.cgColor)
        context.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("magic-\(UUID().uuidString).png")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}

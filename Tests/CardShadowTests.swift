import AppKit
import Testing
import VitrineDomain

@testable import VitrineRendering

@Suite("Card shadow")
struct CardShadowTests {
    @Test func aTranslucentCardIsPaintedOnce() throws {
        var config = SnapshotConfig(code: "x", language: .swift)
        config.theme = Theme(
            id: "custom.translucent", displayName: "Translucent",
            palette: ThemePalette(
                background: try #require(HexColor("#00000080")),
                foreground: try #require(HexColor("#00000000"))))
        config.background = .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1))
        config.showChrome = false

        let image = try #require(
            ExportManager.renderCGImage(
                config, scale: 1, fixedSize: CGSize(width: 400, height: 300)))
        let pixels = NSBitmapImageRep(cgImage: image)
        let center = try #require(
            pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2)?
                .usingColorSpace(.sRGB))
        // Half-opaque black over white: about 0.5, not the 0.25 of a doubled fill.
        #expect(abs(center.redComponent - 0.5) < 0.06)
    }
}

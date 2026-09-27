import AppKit
import SwiftUI
import Testing

@testable import Vitrine

@Suite("Reduced motion control geometry")
struct DecorativeScaleEffectTests {
    @Test(arguments: [false, true], [CGFloat(0.98), 1.08])
    func reducedMotionKeepsPressAndHoverGeometryStable(active: Bool, scale: CGFloat) throws {
        let normal = try pixelWidth(active: active, scale: scale, reduceMotion: false)
        let reduced = try pixelWidth(active: active, scale: scale, reduceMotion: true)
        #expect(reduced == 100)
        #expect(normal == (active ? Int((100 * scale).rounded()) : 100))
    }

    /// Render the actual modifier with the system-policy input and measure opaque
    /// pixels, not a duplicate scale formula. Controls read the read-only system environment.
    private func pixelWidth(active: Bool, scale: CGFloat, reduceMotion: Bool) throws -> Int {
        let renderer = ImageRenderer(
            content: Rectangle().fill(.white).frame(width: 100, height: 100)
                .modifier(
                    DecorativeScaleEffect(
                        isActive: active, scale: scale, reduceMotion: reduceMotion)
                )
                .frame(width: 120, height: 120))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixels = NSBitmapImageRep(cgImage: image)
        var width = 0
        for x in 0..<pixels.pixelsWide {
            let color = try #require(pixels.colorAt(x: x, y: pixels.pixelsHigh / 2))
            if color.alphaComponent > 0.99 { width += 1 }
        }
        return width
    }
}

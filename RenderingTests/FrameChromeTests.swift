import AppKit
import Testing

@testable import VitrineRendering

@MainActor
@Suite("Automatic frame chrome")
struct FrameChromeTests {
    private func makePNG(_ color: NSColor, _ size: CGSize) throws -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func autoChromeSamplesTheImageTopEdge() throws {
        let image = try #require(
            NSImage(data: try makePNG(.systemBlue, CGSize(width: 40, height: 40))))
        let sampled = try #require(FrameChrome.topEdgeColor(of: image))
        let ns = try #require(NSColor(sampled).usingColorSpace(.sRGB))
        // A solid blue image samples to a blue-dominant chrome bar.
        #expect(ns.blueComponent > ns.redComponent)
        #expect(ns.blueComponent > ns.greenComponent)
    }

}

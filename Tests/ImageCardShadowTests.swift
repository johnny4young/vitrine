import AppKit
import Testing
import VitrineDomain

@testable import VitrineRendering

@Suite("Image card shadow")
struct ImageCardShadowTests {
    private static func image(transparentCenter: Bool) throws -> NSImage {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<120 {
            for x in 0..<200 {
                let hole = transparentCenter && (40..<160).contains(x) && (30..<90).contains(y)
                rep.setColor(
                    hole ? .clear : NSColor(deviceRed: 0.2, green: 0.4, blue: 0.9, alpha: 1),
                    atX: x, y: y)
            }
        }
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private static func render(
        _ image: NSImage, frame: ImageFrame, shadowRadius: Double? = nil
    ) throws -> NSBitmapImageRep {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ImageCardShadowTests-\(UUID().uuidString)")
        let store = BackgroundImageStore(directory: directory)
        let url = directory.appendingPathExtension("png")
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(
            NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
        var config = SnapshotConfig()
        config.foregroundImage = try store.importImage(from: url)
        config.imageFrame = frame
        config.background = .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1))
        if let shadowRadius { config.shadowRadius = shadowRadius }
        let rendered = try #require(
            ExportManager.renderCGImage(
                config, scale: 1, fixedSize: CGSize(width: 400, height: 300),
                foregroundImageStore: store))
        return NSBitmapImageRep(cgImage: rendered)
    }

    @Test func opacityChecksEveryPixel() throws {
        #expect(FramedImageView.hasNoTransparentPixels(try Self.image(transparentCenter: false)))
        #expect(!FramedImageView.hasNoTransparentPixels(try Self.image(transparentCenter: true)))
    }

    @Test func aTransparentImageShowsTheBackgroundThroughItsHole() throws {
        let pixels = try Self.render(try Self.image(transparentCenter: true), frame: .none)
        let center = try #require(pixels.colorAt(x: 200, y: 150)?.usingColorSpace(.sRGB))
        #expect(center.redComponent > 0.5)
    }

    @Test(arguments: [ImageFrame.none, .macOSWindow, .browser])
    func anOpaqueCardStillCastsItsShadow(_ frame: ImageFrame) throws {
        let image = try Self.image(transparentCenter: false)
        let shadowed = try Self.render(image, frame: frame)
        let flat = try Self.render(image, frame: frame, shadowRadius: 0)
        var darkest: CGFloat = 0
        for y in 0..<300 {
            for x in 0..<400 {
                guard let a = shadowed.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                    let b = flat.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                darkest = max(darkest, b.redComponent - a.redComponent)
            }
        }
        #expect(darkest > 0.04)
    }
}

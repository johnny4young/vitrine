import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
import VitrineDomain

@testable import VitrineRendering

@MainActor
@Suite("Bounded static image decoding")
struct ImageDecodePolicyTests {
    @Test func metadataInspectionRecognizesAnimationWithoutDecodingIt() throws {
        let data = try Self.animatedGIF()
        let source = try #require(
            CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary))

        let metadata = try ImageDecodePolicy.metadata(
            in: source, maximumFrameCount: 8, maximumSourcePixelCount: 10_000)

        #expect(metadata.frameCount == 2)
        #expect(metadata.isAnimated)
        #expect(metadata.frameDimensions.map { $0.width } == [32, 32])
        #expect(metadata.frameDimensions.map { $0.height } == [24, 24])
        #expect(metadata.totalSourcePixels == 1_536)
    }

    @Test func animatedImportPreloadsExactlyOneStaticRepresentation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VitrineImageDecodeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackgroundImageStore(directory: directory)
        let reference = try await store.importImageConcurrently(
            data: Self.animatedGIF(), preferredExtension: "gif")

        let image = try #require(await store.preloadImage(for: reference))

        #expect(image.representations.count == 1)
        #expect(image.representations.first?.pixelsWide == 32)
        #expect(image.representations.first?.pixelsHigh == 24)
    }

    @Test func thumbnailDecodeStaysInsideDimensionAndAreaBudget() throws {
        let data = try Self.encodedImage(
            width: 120, height: 80, color: .systemIndigo, type: .png)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let metadata = try ImageDecodePolicy.metadata(
            in: source, maximumFrameCount: 1, maximumSourcePixelCount: 20_000)
        let budget = ImageDecodePolicy.Budget(maximumDimension: 40, maximumPixelCount: 1_200)

        let image = try ImageDecodePolicy.decodeStaticFirstFrame(
            in: source, metadata: metadata, budget: budget)

        #expect(image.width <= budget.maximumDimension)
        #expect(image.height <= budget.maximumDimension)
        #expect(image.width * image.height <= budget.maximumPixelCount)
        #expect(image.width < 120)
        #expect(image.height < 80)
    }

    @Test func thumbnailHintHandlesExactAndOversizedInputs() throws {
        let budget = ImageDecodePolicy.Budget(maximumDimension: 100, maximumPixelCount: 8_000)

        #expect(
            try ImageDecodePolicy.thumbnailMaximumPixelSize(
                for: 100, height: 80, budget: budget) == 100)
        let reduced = try ImageDecodePolicy.thumbnailMaximumPixelSize(
            for: 1_000, height: 1_000, budget: budget)
        #expect(reduced <= 89)
        #expect(reduced > 0)
    }

    @Test func thumbnailHintAccountsForRoundedShortAxis() throws {
        let budget = ImageDecodePolicy.Budget(maximumDimension: 1_000, maximumPixelCount: 10_000)
        let maximum = try ImageDecodePolicy.thumbnailMaximumPixelSize(
            for: 1_000, height: 333, budget: budget)

        let projectedHeight = Int((333.0 / 1_000.0 * Double(maximum)).rounded(.up))
        #expect(maximum * projectedHeight <= budget.maximumPixelCount)
    }

    @Test func malformedMetadataCannotTrapTheDecoder() throws {
        let data = try Self.encodedImage(width: 16, height: 16, color: .black, type: .png)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let metadata = ImageDecodePolicy.Metadata(
            frameCount: 1, frameDimensions: [], totalSourcePixels: 0)

        #expect(throws: ImageDecodePolicy.Failure.invalidImage) {
            try ImageDecodePolicy.decodeStaticFirstFrame(in: source, metadata: metadata)
        }
    }

    /// A Retina screenshot records 144 DPI; it lays out at half its pixel size and keeps every
    /// pixel for the @2x export.
    @Test func retinaResolutionSetsThePointSizeNotThePixels() throws {
        let data = try Self.encodedImage(
            width: 200, height: 100, color: .systemTeal, type: .png, dpi: 144)
        let image = try #require(DecodedImageCache.staticImage(from: data))
        #expect(image.size == CGSize(width: 100, height: 50))
        #expect(image.representations.first?.pixelsWide == 200)
        #expect(image.representations.first?.pixelsHigh == 100)
    }

    @Test func standardOrLowResolutionKeepsThePixelSize() throws {
        for dpi in [72.0, 36.0] {
            let data = try Self.encodedImage(
                width: 200, height: 100, color: .systemTeal, type: .png, dpi: dpi)
            let image = try #require(DecodedImageCache.staticImage(from: data))
            #expect(image.size == CGSize(width: 200, height: 100))
        }
    }

    @Test func importedRetinaImageResolvesAtItsPointSize() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "VitrineImageDecodeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BackgroundImageStore(directory: directory)
        let reference = try await store.importImageConcurrently(
            data: Self.encodedImage(
                width: 200, height: 100, color: .systemTeal, type: .png, dpi: 144),
            preferredExtension: "png")

        #expect(store.image(for: reference)?.size == CGSize(width: 100, height: 50))
    }

    private static func animatedGIF() throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data, UTType.gif.identifier as CFString, 2, nil))
        for color in [NSColor.systemRed, .systemBlue] {
            let image = try cgImage(width: 32, height: 24, color: color)
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: 0.1
                ]
            ]
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func encodedImage(
        width: Int, height: Int, color: NSColor, type: UTType, dpi: Double? = nil
    ) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data, type.identifier as CFString, 1, nil))
        let properties = dpi.map {
            [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] as CFDictionary
        }
        CGImageDestinationAddImage(
            destination, try cgImage(width: width, height: height, color: color), properties)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func cgImage(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }
}

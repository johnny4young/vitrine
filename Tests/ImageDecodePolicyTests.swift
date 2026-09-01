import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

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
        width: Int, height: Int, color: NSColor, type: UTType
    ) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, try cgImage(width: width, height: height, color: color), nil)
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

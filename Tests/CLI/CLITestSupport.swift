import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Shared fixtures for focused CLI suites.
enum CLITestFixtures {
    /// A small, representative Swift snippet used as CLI input.
    static let sampleCode = """
        import SwiftUI

        struct CounterView: View {
            @State private var count = 0
            var body: some View {
                Button("Tapped \\(count) times") { count += 1 }
            }
        }
        """
}

/// Common scratch-file and image helpers used by CLI integration-style tests.
@MainActor
protocol CLITestSupport {}

extension CLITestSupport {
    /// Resolves a tracked file relative to the repository root.
    func repoFile(_ components: String...) -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return components.reduce(root) { url, component in
            url.appendingPathComponent(component)
        }
    }

    /// Creates a unique temporary directory for one test and returns its URL.
    /// The directory (and everything written into it) is the test's scratch space;
    /// callers clean it up in a `defer`.
    func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `code` to a file named `name` inside `directory` and returns its path.
    func writeInput(
        _ code: String = CLITestFixtures.sampleCode, named name: String, in directory: URL
    ) throws -> String {
        let url = directory.appendingPathComponent(name)
        try code.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// A decoded raster image, as `CGImage`.
    func decodePNG(at path: String) throws -> CGImage {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Writes a small two-tone PNG fixture without relying on a checked-in asset.
    func writeFixtureImage(to url: URL, size: CGSize) throws {
        let width = Int(size.width)
        let height = Int(size.height)
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemIndigo.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        let image = try #require(context.makeImage())
        let data = try #require(ExportManager.pngData(from: image))
        try data.write(to: url, options: .atomic)
    }

    /// Reads the straight-alpha RGBA of the image's top-left pixel by redrawing it
    /// into a known `RGBA8` context (so the byte order is predictable).
    func cornerRGBA(
        of image: CGImage
    ) throws -> (
        red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
    ) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(
            CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Draw the image's top-left pixel into the 1×1 context.
        context.draw(
            image,
            in: CGRect(
                x: 0, y: CGFloat(1 - image.height), width: CGFloat(image.width),
                height: CGFloat(image.height)))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}

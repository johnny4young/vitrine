import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Color management and transparent-background hardening.
///
/// These tests pin two color guarantees: PNG export is sRGB by
/// default with Display P3 only as an explicit opt-in, and a transparent
/// background exports with a real alpha channel and no matte. They work on the
/// real `ExportManager` pipeline (`SnapshotCanvas` → `ImageRenderer` → ImageIO),
/// decoding the encoded PNG and sampling pixels rather than trusting the
/// in-memory `CGImage`, so they verify what a downstream app would actually open.
@MainActor
@Suite("Color output")
struct ColorOutputTests {
    // MARK: - Fixtures & helpers

    private static func sampleConfig(
        _ mutate: (inout SnapshotConfig) -> Void = { _ in }
    )
        -> SnapshotConfig
    {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        mutate(&config)
        return config
    }

    /// An isolated, empty `UserDefaults` per test (mirrors the migration tests).
    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineColorOutputTests-\(UUID().uuidString)")!
    }

    /// Renders `config` at `profile`, PNG-encodes it, and decodes the PNG back to
    /// a `CGImage` — the same trip a file or clipboard image makes. Returns the
    /// decoded image plus the encoded PNG's ImageIO properties.
    private func decodedPNG(
        _ config: SnapshotConfig, profile: ColorProfile, scale: CGFloat = 1
    ) throws -> (image: CGImage, properties: [CFString: Any]) {
        let rendered = try #require(
            ExportManager.renderCGImage(config, scale: scale, profile: profile))
        let png = try #require(ExportManager.pngData(from: rendered))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (decoded, properties)
    }

    /// Reads a single RGBA8 pixel straight from a decoded PNG's backing bytes.
    ///
    /// Reading the raw provider data (rather than redrawing through a
    /// `CGContext`) keeps the alpha *unassociated*: ImageIO decodes a PNG to
    /// `RGBA8` with straight alpha, so a matte would show up as a non-zero RGB at
    /// zero alpha — which a premultiplied context would have already zeroed out
    /// and hidden. The decoded image is therefore required to be 8-bit RGBA with
    /// `alphaInfo == .last`, which is exactly what `ExportManager.pngData` yields.
    private func pixel(
        _ image: CGImage, x: Int, y: Int
    ) throws -> (
        r: UInt8, g: UInt8, b: UInt8, a: UInt8
    ) {
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        // PNG alpha decodes as straight (.last); reject anything else so the
        // matte check below cannot be silently fooled by premultiplication.
        #expect(image.alphaInfo == .last)
        let provider = try #require(image.dataProvider)
        let data = try #require(provider.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let offset = y * image.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    // MARK: - sRGB is the default (Contract: PNG export defaults to sRGB)

    @Test func defaultProfileIsSRGB() {
        #expect(ColorProfile.fallback == .sRGB)
        #expect(ColorProfile.allCases.first == .sRGB)
    }

    @Test func defaultRenderEncodesAsSRGB() throws {
        // The default render parameter is sRGB; the encoded PNG must be tagged sRGB.
        let decoded = try decodedPNG(Self.sampleConfig(), profile: .sRGB)
        #expect(decoded.image.colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test func renderCGImageDefaultsToSRGBWithoutAnExplicitProfile() throws {
        // Calling without a `profile:` argument must still yield sRGB, so the
        // safe space is the default everywhere, not just where a caller asks.
        let rendered = try #require(ExportManager.renderCGImage(Self.sampleConfig(), scale: 1))
        #expect(rendered.colorSpace?.name == CGColorSpace.sRGB)
    }

    // MARK: - Display P3 is an explicit advanced opt-in

    @Test func displayP3RenderEncodesAsP3() throws {
        let decoded = try decodedPNG(Self.sampleConfig(), profile: .displayP3)
        #expect(decoded.image.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func sRGBExportIsNotTaggedP3() throws {
        // Guards against a regression where everything silently becomes P3.
        let decoded = try decodedPNG(Self.sampleConfig(), profile: .sRGB)
        #expect(decoded.image.colorSpace?.name != CGColorSpace.displayP3)
    }

    @Test func profilesDifferButDimensionsMatch() throws {
        // Same input, two profiles: identical pixel dimensions, different tags.
        let config = Self.sampleConfig()
        let srgb = try decodedPNG(config, profile: .sRGB)
        let p3 = try decodedPNG(config, profile: .displayP3)
        #expect(srgb.image.width == p3.image.width)
        #expect(srgb.image.height == p3.image.height)
        #expect(srgb.image.colorSpace?.name != p3.image.colorSpace?.name)
    }

    @Test func p3ConversionRemapsSaturatedPixelValues() throws {
        // The color-management promise is *predictable* color, and `normalized(_:to:)`
        // documents that it converts (applies the sRGB↔P3 matrix), not merely
        // retags. A pure-saturated red exercises the gamut difference: encoded as
        // sRGB vs P3, the stored RGB bytes of the same logical color must differ.
        // Sampling an opaque solid-color corner isolates the conversion from any
        // anti-aliasing or syntax highlighting. A regression that tagged P3
        // without converting would leave the bytes identical and fail here.
        let config = Self.sampleConfig {
            $0.background = .solid(RGBAColor(Color(hex: "#FF0000")))
            $0.showChrome = false
            $0.showShadow = false
        }
        let srgb = try decodedPNG(config, profile: .sRGB)
        let p3 = try decodedPNG(config, profile: .displayP3)

        let srgbCorner = try pixel(srgb.image, x: 0, y: 0)
        let p3Corner = try pixel(p3.image, x: 0, y: 0)

        // Both corners are the opaque background, so only the color bytes may move.
        #expect(srgbCorner.a == 255)
        #expect(p3Corner.a == 255)
        let bytesDiffer =
            srgbCorner.r != p3Corner.r || srgbCorner.g != p3Corner.g
            || srgbCorner.b != p3Corner.b
        #expect(bytesDiffer, "P3 must convert pixel values, not just relabel the color space")
    }

    // MARK: - Transparent exports have real alpha and no matte

    @Test func transparentExportPNGAdvertisesAlpha() throws {
        let config = Self.sampleConfig {
            $0.background = .transparent
            $0.showShadow = false
        }
        let decoded = try decodedPNG(config, profile: .sRGB)
        // ImageIO reports the alpha channel in the PNG metadata.
        let hasAlpha = decoded.properties[kCGImagePropertyHasAlpha] as? Bool
        #expect(hasAlpha == true)
        // The decoded image must actually carry an alpha channel, not opaque-only.
        #expect(decoded.image.alphaInfo != .none)
        #expect(decoded.image.alphaInfo != .noneSkipFirst)
        #expect(decoded.image.alphaInfo != .noneSkipLast)
    }

    @Test func transparentCornerPixelIsFullyTransparentWithNoMatte() throws {
        // With no chrome/shadow the outer corners are background-only; a
        // transparent background must leave them at zero coverage *and* zero
        // color — a non-zero RGB at zero alpha would betray a matte fill.
        let config = Self.sampleConfig {
            $0.background = .transparent
            $0.showChrome = false
            $0.showShadow = false
        }
        let decoded = try decodedPNG(config, profile: .sRGB)
        let corner = try pixel(decoded.image, x: 0, y: 0)
        #expect(corner.a == 0, "transparent corner should be fully transparent")
        #expect(
            corner.r == 0 && corner.g == 0 && corner.b == 0,
            "transparent corner should carry no matte color")
    }

    @Test func transparentExportInP3AlsoKeepsAlpha() throws {
        // The P3 conversion path must not flatten transparency either.
        let config = Self.sampleConfig {
            $0.background = .transparent
            $0.showChrome = false
            $0.showShadow = false
        }
        let decoded = try decodedPNG(config, profile: .displayP3)
        #expect(decoded.image.colorSpace?.name == CGColorSpace.displayP3)
        #expect((decoded.properties[kCGImagePropertyHasAlpha] as? Bool) == true)
        let corner = try pixel(decoded.image, x: 0, y: 0)
        #expect(corner.a == 0)
    }

    @Test func transparentExportKeepsTheCardOpaque() throws {
        // "Real alpha" means the transparency is *confined to the background*, not
        // the whole image: the code card itself paints an opaque theme background,
        // so a pixel at the canvas center (over the card) must stay fully opaque.
        // The corner-only assertions above would still pass if a regression made
        // the entire canvas transparent; this pins that alpha is selective.
        let config = Self.sampleConfig {
            $0.background = .transparent
            $0.showShadow = false
        }
        let decoded = try decodedPNG(config, profile: .sRGB)
        let center = try pixel(
            decoded.image, x: decoded.image.width / 2, y: decoded.image.height / 2)
        #expect(
            center.a == 255,
            "the card interior must remain fully opaque under a transparent background")
    }

    @Test func opaqueBackgroundCornerIsFullyOpaque() throws {
        // A solid (opaque) background must export with a fully opaque corner, so
        // an opaque export never leaks partial transparency.
        let config = Self.sampleConfig {
            $0.background = .solid(RGBAColor(Color(hex: "#3366CC")))
            $0.showShadow = false
        }
        let decoded = try decodedPNG(config, profile: .sRGB)
        let corner = try pixel(decoded.image, x: 0, y: 0)
        #expect(corner.a == 255, "opaque background corner should be fully opaque")
    }

    @Test func gradientBackgroundCornerIsFullyOpaque() throws {
        let config = Self.sampleConfig {
            $0.background = .gradient(.aurora)
            $0.showShadow = false
        }
        let decoded = try decodedPNG(config, profile: .sRGB)
        let corner = try pixel(decoded.image, x: 0, y: 0)
        #expect(corner.a == 255)
    }

    // MARK: - normalized() unit behavior

    @Test func normalizedPreservesDimensions() throws {
        let rendered = try #require(ExportManager.renderCGImage(Self.sampleConfig(), scale: 2))
        let normalized = ExportManager.normalized(rendered, to: .displayP3)
        #expect(normalized.width == rendered.width)
        #expect(normalized.height == rendered.height)
        #expect(normalized.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func normalizedKeepsAnAlphaChannel() throws {
        // The normalization context is premultipliedLast, so the result always
        // carries alpha regardless of profile.
        let rendered = try #require(ExportManager.renderCGImage(Self.sampleConfig(), scale: 1))
        let normalized = ExportManager.normalized(rendered, to: .sRGB)
        #expect(normalized.alphaInfo == .premultipliedLast)
    }

    // MARK: - Persistence (advanced option round-trips,  fallback)

    @Test func colorProfileResolvesUnknownAndMissingToSRGB() {
        #expect(ColorProfile.resolve(nil) == .sRGB)
        #expect(ColorProfile.resolve("not-a-profile") == .sRGB)
        #expect(ColorProfile.resolve("displayP3") == .displayP3)
    }

    @Test func appSettingsDefaultsColorProfileToSRGB() {
        let settings = AppSettings(defaults: Self.freshDefaults())
        #expect(settings.export.colorProfile == .sRGB)
    }

    @Test func appSettingsPersistsColorProfile() {
        let defaults = Self.freshDefaults()

        let settings = AppSettings(defaults: defaults)
        settings.export.colorProfile = .displayP3

        // A fresh instance over the same store reads the persisted choice back.
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.export.colorProfile == .displayP3)
    }

    @Test func resetRestoresSRGBProfile() {
        let settings = AppSettings(defaults: Self.freshDefaults())
        settings.export.colorProfile = .displayP3
        settings.resetToDefaults()
        #expect(settings.export.colorProfile == .sRGB)
    }

    // MARK: - Sample gallery comparison

    @Test func sampleGalleryEachProfileEncodesConsistently() throws {
        // A small "gallery" pass: across representative backgrounds, the sRGB
        // export is always sRGB and the P3 export is always P3, and both encode
        // to a valid PNG (magic number) — a structural color-output regression net.
        // Qualified: SwiftUI also declares a `BackgroundStyle` shape style.
        let backgrounds: [Vitrine.BackgroundStyle] = [
            .gradient(.aurora), .solid(RGBAColor(Color(hex: "#1F1C2C"))), .transparent,
        ]
        for background in backgrounds {
            let config = Self.sampleConfig {
                $0.background = background
                $0.showShadow = false
            }
            for profile in ColorProfile.allCases {
                let rendered = try #require(
                    ExportManager.renderCGImage(config, scale: 1, profile: profile))
                let png = try #require(ExportManager.pngData(from: rendered))
                #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
                let expected =
                    profile == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3
                #expect(rendered.colorSpace?.name == expected)
            }
        }
    }
}

import Foundation
import SwiftUI
import Testing

@testable import Vitrine

/// SVG export and the deterministic vector fallback.
///
/// A technical evaluation established that there is **no** faithful
/// full-canvas SVG path, so PDF is the supported vector format, and a hand-authored
/// SVG serializer exists **only** for the deterministic simple-template subset
/// (`VectorTemplateSVG`) — never the arbitrary code canvas, and never as a fake
/// raster-in-SVG wrapper. These tests pin exactly those guarantees:
///
/// - the supported vector exports carry the right signatures (SVG `<?xml …><svg …>`)
///   and use native primitives, with no `<image>` element or embedded raster payload
///   anywhere;
/// - a transparent background stays genuinely transparent;
/// - the template SVG is byte-for-byte deterministic for the same input.
///
/// The format catalog and the PDF side of the same promise live in `ExportFormatTests`
/// and `ExportEncodingTests`; this suite is the serializer itself.
@MainActor
@Suite("Export · SVG and vector fallback")
struct VectorTemplateSVGTests {
    private static let cardSize = ExportTestFixtures.cardSize

    // MARK: - Template SVG signature (tests: "exported SVG signature")

    @Test("Solid-background template serializes to a real SVG document")
    func svgSolidSignature() throws {
        let svg = try #require(
            VectorTemplateSVG.background(.solid(RGBAColor(.black)), size: Self.cardSize))
        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains("<svg"))
        #expect(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
        #expect(svg.contains("</svg>"))
        // A solid background is a filled rect with the canvas color — native vector.
        #expect(svg.contains("<rect"))
        #expect(svg.contains("fill=\"#000000\""))
        // The viewBox carries the template aspect (1200×630).
        #expect(svg.contains("viewBox=\"0 0 1200 630\""))
    }

    @Test("Gradient-background template emits a native linearGradient")
    func svgGradientSignature() throws {
        let svg = try #require(
            VectorTemplateSVG.background(.gradient(.aurora), size: Self.cardSize))
        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains("<linearGradient"))
        // Two-stop preset → two <stop> elements painting a filled rect via url(#bg).
        #expect(svg.components(separatedBy: "<stop").count - 1 == 2)
        #expect(svg.contains("fill=\"url(#bg)\""))
    }

    @Test("Custom-gradient template keeps stop colors and opacity")
    func svgCustomGradientStops() throws {
        let gradient = CustomGradient(
            stops: [
                GradientStop(
                    color: RGBAColor(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)),
                    location: 0),
                GradientStop(
                    color: RGBAColor(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 0.5)),
                    location: 1),
            ],
            angle: 90)
        let svg = try #require(
            VectorTemplateSVG.background(.customGradient(gradient), size: Self.cardSize))
        #expect(svg.contains("stop-color=\"#FF0000\""))
        #expect(svg.contains("stop-color=\"#0000FF\""))
        // The translucent stop carries its alpha as a separate stop-opacity.
        #expect(svg.contains("stop-opacity=\"0.5\""))
    }

    // MARK: - No raster-in-SVG fallback (contract & tests)

    @Test("Image background is unsupported, not a raster-in-SVG wrapper")
    func imageBackgroundReturnsNil() {
        let image = BackgroundStyle.image(
            ImageBackground(reference: ImageReference(fileName: "photo.png")))
        // The serializer refuses an image background rather than embedding a raster:
        // there is no fake .svg wrapping a PNG.
        #expect(VectorTemplateSVG.background(image, size: Self.cardSize) == nil)
        #expect(VectorTemplateSVG.supports(image) == false)
        // Every other simple-template background is supported.
        for background in [
            BackgroundStyle.solid(RGBAColor(.white)), .gradient(.aurora),
            .customGradient(.default), .transparent,
        ] {
            #expect(VectorTemplateSVG.supports(background))
        }
    }

    @Test("No template SVG ever contains an embedded raster image")
    func svgNeverEmbedsRaster() throws {
        for background in [
            BackgroundStyle.solid(RGBAColor(.black)), .gradient(.aurora),
            .customGradient(.default), .transparent,
        ] {
            let svg = try #require(
                VectorTemplateSVG.background(background, size: Self.cardSize))
            // A real vector card never embeds a bitmap: no <image> element and no
            // base64 PNG/JPEG payload smuggled in as a data URI.
            #expect(!svg.contains("<image"))
            #expect(!svg.lowercased().contains("data:image"))
            #expect(!svg.contains("base64"))
            #expect(!svg.contains("xlink:href"))
        }
    }

    // MARK: - Transparent vector export

    @Test("Transparent template SVG has no background rectangle")
    func svgTransparentHasNoBackground() throws {
        let svg = try #require(
            VectorTemplateSVG.background(.transparent, size: Self.cardSize))
        // Real transparency: the document carries no painted background, so a viewer
        // composites it over whatever is behind it (no matte) — the SVG analogue of
        // the PNG/PDF transparent guarantee.
        #expect(!svg.contains("<rect"))
        #expect(!svg.contains("fill"))
        // It is still a valid, well-formed (empty-canvas) SVG document.
        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains("<svg"))
        #expect(svg.contains("</svg>"))
    }

    // MARK: - Determinism (the property the template export relies on)

    @Test("Same template input serializes to byte-identical SVG")
    func svgIsDeterministic() throws {
        for background in [
            BackgroundStyle.solid(
                RGBAColor(Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.8))),
            .gradient(.ocean),
            .customGradient(.default),
            .transparent,
        ] {
            let first = try #require(VectorTemplateSVG.background(background, size: Self.cardSize))
            let second = try #require(VectorTemplateSVG.background(background, size: Self.cardSize))
            #expect(first == second)
        }
    }

    @Test("Solid-color serialization is independent of how the Color was built")
    func svgColorIsValueStable() throws {
        // A named color and a hand-built sRGB color for the same value must produce
        // the same hex, mirroring the value-based color equality the app relies on.
        let named = try #require(
            VectorTemplateSVG.background(.solid(RGBAColor(.white)), size: Self.cardSize))
        let built = try #require(
            VectorTemplateSVG.background(
                .solid(RGBAColor(Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1))),
                size: Self.cardSize))
        #expect(named == built)
        #expect(named.contains("fill=\"#FFFFFF\""))
    }

    // MARK: - Well-formed XML (the docstring claims it; parse it to prove it)

    @Test("Every supported background serializes to genuinely well-formed XML")
    func svgIsWellFormedXML() throws {
        // Substring checks pass even on malformed markup (an unbalanced tag, a
        // broken attribute). Parsing with XMLDocument proves the serializer emits a
        // real, well-formed SVG document — the "valid, well-formed SVG" guarantee
        // the serializer makes for every case, including the empty transparent canvas.
        for background in [
            BackgroundStyle.solid(
                RGBAColor(Color(.sRGB, red: 0.1, green: 0.5, blue: 0.9, opacity: 0.7))),
            .gradient(.aurora), .customGradient(.default), .transparent,
        ] {
            let svg = try #require(VectorTemplateSVG.background(background, size: Self.cardSize))
            let data = try #require(svg.data(using: .utf8))
            // Throws if the markup is not well-formed; the root element must be <svg>.
            let document = try XMLDocument(data: data, options: [])
            #expect(document.rootElement()?.name == "svg")
        }
    }

    // MARK: - Gradient direction (angle → endpoint math must reach the SVG)

    @Test("Custom-gradient endpoints in the SVG match the gradient's angle math")
    func svgGradientEndpointsFollowAngle() throws {
        // The serializer documents that the gradient angle maps through the same
        // endpoint math the live SwiftUI gradient uses, so the exported direction
        // matches the on-canvas one. Parse the emitted x1/y1/x2/y2 back out and
        // require them to equal CustomGradient.endpoints — a flipped axis or a
        // dropped angle would otherwise ship silently (every substring check still
        // passes). Cover several angles, not just the default.
        for angle in [0.0, 45, 90, 135, 270] {
            let gradient = CustomGradient(
                stops: [
                    GradientStop(color: RGBAColor(.black), location: 0),
                    GradientStop(color: RGBAColor(.white), location: 1),
                ],
                angle: angle)
            let svg = try #require(
                VectorTemplateSVG.background(.customGradient(gradient), size: Self.cardSize))
            let document = try XMLDocument(
                data: try #require(svg.data(using: .utf8)), options: [])
            let node = try #require(
                try document.nodes(forXPath: "//linearGradient").first as? XMLElement)

            func coordinate(_ name: String) throws -> Double {
                let raw = try #require(node.attribute(forName: name)?.stringValue)
                return try #require(Double(raw))
            }

            let (start, end) = gradient.endpoints
            #expect(abs(try coordinate("x1") - Double(start.x)) < 0.0001)
            #expect(abs(try coordinate("y1") - Double(start.y)) < 0.0001)
            #expect(abs(try coordinate("x2") - Double(end.x)) < 0.0001)
            #expect(abs(try coordinate("y2") - Double(end.y)) < 0.0001)
        }
    }
}

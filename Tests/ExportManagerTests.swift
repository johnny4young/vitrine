import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing

@testable import Vitrine

/// SVG export and the deterministic vector fallback (CS-023).
///
/// CS-023 is a Discovery/spike with a documented decision: there is **no** faithful
/// full-canvas SVG path, so PDF is the supported vector format, and a hand-authored
/// SVG serializer exists **only** for the deterministic simple-template subset
/// (`VectorTemplateSVG`) — never the arbitrary code canvas, and never as a fake
/// raster-in-SVG wrapper. These tests pin exactly those guarantees:
///
/// - the export-format menu states honestly which output is vector (PDF), and the
///   format value round-trips through persistence (CS-050);
/// - the supported vector exports carry the right signatures (PDF `%PDF`, SVG
///   `<?xml …><svg …>`) and the SVG uses native primitives, with no `<image>`
///   element or embedded raster payload anywhere;
/// - a transparent background stays genuinely transparent in both vector outputs;
/// - the template SVG is byte-for-byte deterministic for the same input.
@MainActor
@Suite("Export · SVG and vector fallback (CS-023)")
struct VectorExportTests {
    // MARK: - Fixtures

    private static func sampleConfig(
        _ mutate: (inout SnapshotConfig) -> Void = { _ in }
    ) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        mutate(&config)
        return config
    }

    private static let cardSize = CGSize(width: 1200, height: 630)

    // MARK: - Format menu accuracy (CS-023 acceptance: "menu shows supported vector outputs")

    @Test("PNG, PDF, HEIC, and AVIF are offered; PDF is the only vector option")
    func formatCasesAndVectorFlag() {
        #expect(ExportFormat.allCases == [.png, .pdf, .heic, .avif])
        #expect(ExportFormat.png.isVector == false)
        #expect(ExportFormat.pdf.isVector == true)
        #expect(ExportFormat.heic.isVector == false)
        #expect(ExportFormat.avif.isVector == false)
        // Exactly one supported vector format is advertised, and it is PDF.
        let vectors = ExportFormat.allCases.filter(\.isVector)
        #expect(vectors == [.pdf])
    }

    @Test("Each format has a non-empty display name and summary")
    func formatLabelsArePresent() {
        for format in ExportFormat.allCases {
            #expect(!format.displayName.isEmpty)
            #expect(!format.summary.isEmpty)
        }
        #expect(ExportFormat.png.displayName == "PNG")
        #expect(ExportFormat.pdf.displayName == "PDF")
        #expect(ExportFormat.heic.displayName == "HEIC")
        #expect(ExportFormat.avif.displayName == "AVIF")
        // The vector summary names the scalable nature so the menu reads honestly.
        #expect(ExportFormat.pdf.summary.lowercased().contains("vector"))
    }

    // MARK: - Format round-trip (CS-023 tests: "format round-trip")

    @Test("Format round-trips through its persisted raw value")
    func formatRoundTrip() {
        for format in ExportFormat.allCases {
            #expect(ExportFormat.resolve(format.rawValue) == format)
            #expect(ExportFormat(rawValue: format.rawValue) == format)
        }
        // Raw values are the stable persistence contract (CS-050); they must not
        // drift, or stored preferences would silently change format.
        #expect(ExportFormat.png.rawValue == "png")
        #expect(ExportFormat.pdf.rawValue == "pdf")
        #expect(ExportFormat.heic.rawValue == "heic")
        #expect(ExportFormat.avif.rawValue == "avif")
    }

    @Test("Unknown or missing format falls back to PNG")
    func formatFallback() {
        #expect(ExportFormat.resolve(nil) == .png)
        #expect(ExportFormat.resolve("") == .png)
        #expect(ExportFormat.resolve("svg") == .png)
        #expect(ExportFormat.fallback == .png)
    }

    // MARK: - HEIC encoding

    @Test("HEIC export encodes the rendered image into a real HEIC container")
    func heicEncodesTheRenderedImage() throws {
        let payload = try #require(
            ExportManager.encodedPayload(
                .heic,
                png: { ExportManager.renderCGImage(Self.sampleConfig(), scale: 1) },
                pdf: { nil }))
        #expect(payload.ext == "heic")
        #expect(!payload.data.isEmpty)
        // It decodes back to an image of the same pixel size as a PNG render.
        let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let reference = try #require(ExportManager.renderCGImage(Self.sampleConfig(), scale: 1))
        #expect(decoded.width == reference.width)
        #expect(decoded.height == reference.height)
    }

    @Test("AVIF export encodes a decodable alpha-capable AVIF container")
    func avifEncodesTheRenderedImage() throws {
        let payload = try #require(
            ExportManager.encodedPayload(
                .avif,
                png: {
                    ExportManager.renderCGImage(
                        Self.sampleConfig { $0.background = .transparent }, scale: 1)
                },
                pdf: { nil }))
        #expect(payload.ext == "avif")
        #expect(payload.type.identifier == "public.avif")
        #expect(!payload.data.isEmpty)
        let source = try #require(CGImageSourceCreateWithData(payload.data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let reference = try #require(
            ExportManager.renderCGImage(
                Self.sampleConfig { $0.background = .transparent }, scale: 1))
        #expect(decoded.width == reference.width)
        #expect(decoded.height == reference.height)
        #expect(decoded.alphaInfo != .none)
    }

    // MARK: - Suggested filename

    @Test("Save panel name derives from the metadata filename, then the code")
    func suggestedFilenameDerivation() {
        // 1. The metadata filename chip wins, extension dropped.
        var named = Self.sampleConfig()
        named.metadata.filename = "ContentView.swift"
        #expect(SuggestedFilename.basename(for: named) == "ContentView")

        // Path-ish or spaced chips are sanitized, never emitted verbatim.
        named.metadata.filename = "Sources/App/My View.swift"
        #expect(SuggestedFilename.basename(for: named) == "My-View")

        // 2. Without a chip, the first declared identifier names the file.
        var code = Self.sampleConfig()
        code.code = "import Foundation\n\nfunc renderCard() -> Int { 42 }"
        #expect(SuggestedFilename.basename(for: code) == "vitrine-renderCard")

        // 3. Nothing derivable falls back to the plain app name.
        var bare = Self.sampleConfig()
        bare.code = "let answer = 42"
        #expect(SuggestedFilename.basename(for: bare) == "vitrine")
        var terminal = Self.sampleConfig()
        terminal.language = .terminal
        terminal.code = "$ def not-code\n"
        #expect(SuggestedFilename.basename(for: terminal) == "vitrine")
    }

    // MARK: - PDF signature (CS-023 tests: "exported PDF signature")

    @Test("PDF export is a real PDF document (%PDF magic)")
    func pdfSignature() throws {
        let pdf = try #require(ExportManager.pdfData(Self.sampleConfig()))
        // "%PDF" — a genuine vector PDF, the supported full-canvas vector format.
        #expect(Array(pdf.prefix(4)) == Array("%PDF".utf8))
    }

    @Test("PDF export preserves a transparent background (no opaque matte)")
    func pdfTransparentBackgroundHasAlpha() throws {
        let pdf = try #require(
            ExportManager.pdfData(Self.sampleConfig { $0.background = .transparent }))
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)

        // Rasterize the whole page into a fully transparent bitmap. The padding
        // around the code card has a transparent background, so those regions must
        // stay clear (alpha 0); an opaque matte would force every pixel to alpha
        // 255. This is the same transparency the PNG path guarantees (CS-024),
        // exercised through the supported vector format (CS-023).
        let width = max(Int(box.width), 1)
        let height = max(Int(box.height), 1)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0xFF, count: bytesPerRow * height)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Start fully transparent so untouched regions report alpha 0, then draw.
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.drawPDFPage(page)

        let clearPixels = stride(from: 3, to: pixels.count, by: 4).lazy
            .filter { pixels[$0] == 0 }.count
        // A meaningful fraction of the page is the transparent background; require
        // it to be genuinely clear rather than matted onto an opaque color.
        #expect(clearPixels > 0)
    }

    // MARK: - Template SVG signature (CS-023 tests: "exported SVG signature")

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

    // MARK: - No raster-in-SVG fallback (CS-023 acceptance & tests)

    @Test("Image background is unsupported, not a raster-in-SVG wrapper")
    func imageBackgroundReturnsNil() {
        let image = BackgroundStyle.image(
            ImageBackground(reference: ImageReference(fileName: "photo.png")))
        // The serializer refuses an image background rather than embedding a raster:
        // there is no fake .svg wrapping a PNG (CS-023).
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
            // base64 PNG/JPEG payload smuggled in as a data URI (CS-023).
            #expect(!svg.contains("<image"))
            #expect(!svg.lowercased().contains("data:image"))
            #expect(!svg.contains("base64"))
            #expect(!svg.contains("xlink:href"))
        }
    }

    // MARK: - Transparent vector export (CS-023 acceptance)

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
        // CS-023 makes for every case, including the empty transparent canvas.
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

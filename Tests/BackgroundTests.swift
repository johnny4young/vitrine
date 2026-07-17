import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

// `import SwiftUI` also brings a `BackgroundStyle` (a `ShapeStyle`) into scope,
// which would make the bare name ambiguous here. Pin it to Vitrine's model type
// for this test file.
private typealias BackgroundStyle = Vitrine.BackgroundStyle

/// Custom and image backgrounds (CS-051).
///
/// Pins the ticket's guarantees: every background kind is `Codable` and survives
/// a persistence round-trip; each kind renders with the expected dimensions and
/// alpha (opaque for color/image, real transparency for `transparent`); a
/// solid/custom-gradient color round-trips through fixed sRGB; image access is
/// container-scoped with a graceful fallback for a missing file; and the persisted
/// background reloads (including the pre-CS-051 legacy gradient name).
@MainActor
@Suite("Background (CS-051)")
struct BackgroundTests {
    // MARK: - Fixtures & helpers

    private static func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineBackgroundTests-\(UUID().uuidString)")!
    }

    /// A store rooted in a unique temporary directory, so import/resolve tests
    /// never touch the real app container.
    private static func tempStore() -> BackgroundImageStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "VitrineBackgroundTests-\(UUID().uuidString)", isDirectory: true)
        return BackgroundImageStore(directory: dir)
    }

    /// Writes a small solid-color PNG to a temporary file and returns its URL,
    /// standing in for a user-selected image.
    private static func makeSamplePNG(_ color: NSColor = .systemBlue) throws -> URL {
        let data = try makeSamplePNGData(color)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    /// The PNG bytes of a small solid-color image, standing in for a downloaded
    /// image payload.
    private static func makeSamplePNGData(_ color: NSColor = .systemBlue) throws -> Data {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// An `HTTPURLResponse` (typed as `URLResponse`) for stubbing the download
    /// loader with a given status and optional content type.
    private static func httpResponse(
        for url: URL, status: Int = 200, mime: String? = "image/png"
    ) -> URLResponse {
        var headers: [String: String] = [:]
        if let mime { headers["Content-Type"] = mime }
        return HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private static func encoded(_ style: BackgroundStyle) throws -> BackgroundStyle {
        let data = try JSONEncoder().encode(style)
        return try JSONDecoder().decode(BackgroundStyle.self, from: data)
    }

    /// Reads a single straight-alpha RGBA8 pixel from a decoded PNG (mirrors
    /// `ColorOutputTests`): reading raw provider bytes keeps a matte detectable.
    private func pixel(
        _ image: CGImage, x: Int, y: Int
    ) throws -> (
        r: UInt8, g: UInt8, b: UInt8, a: UInt8
    ) {
        #expect(image.bitsPerComponent == 8)
        #expect(image.bitsPerPixel == 32)
        #expect(image.alphaInfo == .last)
        let provider = try #require(image.dataProvider)
        let data = try #require(provider.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let offset = y * image.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    /// Renders `config` and decodes the encoded PNG back to a `CGImage`, the same
    /// trip a saved/clipboard image makes.
    private func decodedPNG(_ config: SnapshotConfig, scale: CGFloat = 1) throws -> CGImage {
        let rendered = try #require(ExportManager.renderCGImage(config, scale: scale))
        let png = try #require(ExportManager.pngData(from: rendered))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    // MARK: - Codable round-trip (Acceptance: all kinds Codable)

    @Test func solidRoundTrips() throws {
        let original = BackgroundStyle.solid(
            RGBAColor(
                Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1)
            ))
        #expect(try Self.encoded(original) == original)
    }

    @Test func gradientPresetRoundTrips() throws {
        for preset in GradientPreset.allCases {
            let original = BackgroundStyle.gradient(preset)
            #expect(try Self.encoded(original) == original)
        }
    }

    @Test func transparentRoundTrips() throws {
        #expect(try Self.encoded(.transparent) == .transparent)
    }

    @Test func customGradientRoundTripsStopsAndAngle() throws {
        let gradient = CustomGradient(
            stops: [
                GradientStop(color: RGBAColor(.red), location: 0),
                GradientStop(color: RGBAColor(.green), location: 0.5),
                GradientStop(color: RGBAColor(.blue), location: 1),
            ],
            angle: 217)
        let original = BackgroundStyle.customGradient(gradient)
        let roundTripped = try Self.encoded(original)
        #expect(roundTripped == original)
        guard case .customGradient(let decoded) = roundTripped else {
            Issue.record("expected a custom gradient")
            return
        }
        #expect(decoded.stops.count == 3)
        #expect(decoded.angle == 217)
    }

    @Test func imageBackgroundRoundTripsAllParameters() throws {
        let original = BackgroundStyle.image(
            ImageBackground(
                reference: ImageReference(fileName: "abc123.png"),
                fit: .fit, blur: 12, dimming: 0.4))
        let roundTripped = try Self.encoded(original)
        #expect(roundTripped == original)
        guard case .image(let decoded) = roundTripped else {
            Issue.record("expected an image background")
            return
        }
        #expect(decoded.reference.fileName == "abc123.png")
        #expect(decoded.fit == .fit)
        #expect(decoded.blur == 12)
        #expect(decoded.dimming == 0.4)
    }

    @Test func solidColorSurvivesSRGBRoundTrip() {
        // A solid color persists through the fixed-sRGB `RGBAColor` representation
        // with no visible drift.
        let color = Color(.sRGB, red: 0.13, green: 0.55, blue: 0.82, opacity: 0.9)
        let restored = RGBAColor(color).color
        let a = NSColor(color).usingColorSpace(.sRGB)!
        let b = NSColor(restored).usingColorSpace(.sRGB)!
        #expect(abs(a.redComponent - b.redComponent) < 0.001)
        #expect(abs(a.greenComponent - b.greenComponent) < 0.001)
        #expect(abs(a.blueComponent - b.blueComponent) < 0.001)
        #expect(abs(a.alphaComponent - b.alphaComponent) < 0.001)
    }

    // MARK: - Defensive decode (Acceptance: never crash on bad data)

    @Test func unknownGradientPresetDecodesToSignatureDefault() throws {
        // A persisted gradient whose preset name no longer resolves degrades to
        // the signature default instead of failing the decode (CS-050).
        let json = #"{"kind":"gradient","preset":"Retired Preset"}"#
        let decoded = try JSONDecoder().decode(BackgroundStyle.self, from: Data(json.utf8))
        #expect(decoded == .gradient(.aurora))
    }

    @Test func imageNumericFieldsAreClampedOnDecode() throws {
        // Out-of-range or non-finite blur/dimming from a hand-edited store are
        // clamped into their documented ranges on decode.
        let json = #"""
            {"kind":"image","image":{"reference":{"fileName":"x.png"},"fit":"fill","blur":9999,"dimming":-3}}
            """#
        let decoded = try JSONDecoder().decode(BackgroundStyle.self, from: Data(json.utf8))
        guard case .image(let image) = decoded else {
            Issue.record("expected an image background")
            return
        }
        #expect(ImageBackground.blurRange.contains(image.blur))
        #expect(ImageBackground.dimmingRange.contains(image.dimming))
    }

    @Test func customGradientWithTooFewStopsFallsBackToDefault() throws {
        // A degenerate one-stop gradient is not a valid gradient; decode repairs
        // it to the two-stop default rather than rendering nothing.
        let json = #"""
            {"kind":"customGradient","customGradient":{"angle":45,"stops":[{"color":{"red":1,"green":0,"blue":0,"opacity":1},"location":0}]}}
            """#
        let decoded = try JSONDecoder().decode(BackgroundStyle.self, from: Data(json.utf8))
        guard case .customGradient(let gradient) = decoded else {
            Issue.record("expected a custom gradient")
            return
        }
        #expect(gradient.stops.count >= 2)
    }

    // MARK: - Render dimensions & alpha per kind

    private static func sampleConfig(
        background: BackgroundStyle, _ mutate: (inout SnapshotConfig) -> Void = { _ in }
    ) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        config.background = background
        // Strip chrome/shadow so the outer corners are background-only and the
        // alpha checks below sample the background, not the card.
        config.showChrome = false
        config.showShadow = false
        mutate(&config)
        return config
    }

    @Test func everyOpaqueKindRendersAtTheFixedSize() throws {
        // A fixed-size render must produce exactly `size × scale` pixels for every
        // opaque kind, so background choice never changes export dimensions.
        let size = CGSize(width: 200, height: 120)
        let kinds: [BackgroundStyle] = [
            .solid(RGBAColor(Color(hex: "#3366CC"))),
            .gradient(.aurora),
            .customGradient(.default),
        ]
        for kind in kinds {
            let config = Self.sampleConfig(background: kind)
            let image = try #require(
                ExportManager.renderCGImage(config, scale: 2, fixedSize: size))
            #expect(image.width == 400)
            #expect(image.height == 240)
        }
    }

    @Test func solidBackgroundCornerIsFullyOpaque() throws {
        let config = Self.sampleConfig(background: .solid(RGBAColor(Color(hex: "#3366CC"))))
        let image = try decodedPNG(config)
        let corner = try pixel(image, x: 1, y: 1)
        #expect(corner.a == 255, "a solid background corner must be fully opaque")
    }

    @Test func customGradientCornerIsFullyOpaque() throws {
        let config = Self.sampleConfig(background: .customGradient(.default))
        let image = try decodedPNG(config)
        let corner = try pixel(image, x: 1, y: 1)
        #expect(corner.a == 255, "a custom-gradient corner must be fully opaque")
    }

    @Test func transparentBackgroundCornerHasRealAlpha() throws {
        // Transparent export must keep a real, fully-clear corner with no matte
        // (RGB zero at alpha zero), the load-bearing CS-024 guarantee.
        let config = Self.sampleConfig(background: .transparent)
        let image = try decodedPNG(config)
        let corner = try pixel(image, x: 1, y: 1)
        #expect(corner.a == 0, "a transparent background corner must be fully clear")
        #expect(corner.r == 0 && corner.g == 0 && corner.b == 0, "no opaque matte behind the card")
    }

    @Test func imageBackgroundCornerIsOpaqueWhenResolvable() throws {
        // An image background renders through the canvas. Its corner is opaque
        // (the image fills the frame), distinguishing it from transparent export.
        let store = Self.tempStore()
        let reference = try store.importImage(from: Self.makeSamplePNG())
        let config = Self.sampleConfig(
            background: .image(ImageBackground(reference: reference, fit: .fill)))

        // Render the canvas with the test store injected so the image resolves.
        let renderer = ImageRenderer(
            content: SnapshotCanvas(config: config, fixedSize: CGSize(width: 200, height: 120))
                .environment(\.backgroundImageStore, store))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(CGSize(width: 200, height: 120))
        let rendered = try #require(renderer.cgImage)
        let normalized = ExportManager.normalized(rendered, to: .sRGB)
        let png = try #require(ExportManager.pngData(from: normalized))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let corner = try pixel(decoded, x: 1, y: 1)
        #expect(corner.a == 255, "a resolvable image background must render opaque")
    }

    @Test func fittedAndBlurredImageBackgroundEdgesRemainOpaque() throws {
        let store = Self.tempStore()
        let reference = try store.importImage(from: Self.makeSamplePNG())
        for imageBackground in [
            ImageBackground(reference: reference, fit: .fit),
            ImageBackground(reference: reference, fit: .fill, blur: 16, dimming: 0.35),
        ] {
            let config = Self.sampleConfig(background: .image(imageBackground))
            let rendered = try #require(
                ExportManager.renderCGImage(
                    config, scale: 1, fixedSize: CGSize(width: 200, height: 120),
                    backgroundImageStore: store))
            let png = try #require(ExportManager.pngData(from: rendered))
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

            for point in [(1, 1), (decoded.width - 2, 1), (1, decoded.height - 2)] {
                #expect(
                    try pixel(decoded, x: point.0, y: point.1).a == 255,
                    "image-background fit and blur must not leak transparent edges")
            }
        }
    }

    // MARK: - Missing-image fallback (Acceptance: degrade gracefully)

    @Test func missingImageResolvesToNilFromStore() {
        let store = Self.tempStore()
        // Nothing was imported, so any reference is unresolvable.
        #expect(store.url(for: ImageReference(fileName: "nope.png")) == nil)
        #expect(store.image(for: ImageReference(fileName: "nope.png")) == nil)
    }

    @Test func missingImageBackgroundStillRendersWithoutCrashing() throws {
        // A relocated/missing image must not blank the export: the canvas falls
        // back to the signature gradient, so a fixed-size render still produces a
        // fully opaque image of the expected dimensions.
        let store = Self.tempStore()
        let config = Self.sampleConfig(
            background: .image(ImageBackground(reference: ImageReference(fileName: "gone.png"))))
        let renderer = ImageRenderer(
            content: SnapshotCanvas(config: config, fixedSize: CGSize(width: 160, height: 100))
                .environment(\.backgroundImageStore, store))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(CGSize(width: 160, height: 100))
        let rendered = try #require(renderer.cgImage)
        #expect(rendered.width == 160)
        #expect(rendered.height == 100)
        let normalized = ExportManager.normalized(rendered, to: .sRGB)
        let png = try #require(ExportManager.pngData(from: normalized))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let corner = try pixel(decoded, x: 1, y: 1)
        #expect(corner.a == 255, "the missing-image fallback gradient must be opaque")
    }

    // MARK: - Image store: container-scoped, no broad access

    @Test func importCopiesIntoTheContainerAndResolves() throws {
        let store = Self.tempStore()
        let source = try Self.makeSamplePNG()
        let reference = try store.importImage(from: source)

        // The copy lives under the store's directory (the container), never the
        // original path, and resolves back to a readable file.
        let resolved = try #require(store.url(for: reference))
        #expect(resolved.path.hasPrefix(store.directory.path))
        #expect(resolved != source)
        #expect(FileManager.default.fileExists(atPath: resolved.path))
        #expect(store.image(for: reference) != nil)
    }

    @Test func imageIsServedFromCacheOnRepeatedResolves() throws {
        // A live preview resolves the same reference on every body pass; the second
        // resolve must return the cached instance rather than re-decoding from disk
        // (audit Perf-1). Content-addressed names make the path immutable, so the
        // cached image can never be stale.
        let store = Self.tempStore()
        let reference = try store.importImage(from: Self.makeSamplePNG(.systemTeal))
        let first = try #require(store.image(for: reference))
        let second = try #require(store.image(for: reference))
        #expect(first === second)
    }

    @Test func reimportingIdenticalBytesReusesOneFile() throws {
        // Content-addressed names mean the same image imported twice yields the
        // same reference and a single file (no duplicate accumulation).
        let store = Self.tempStore()
        let source = try Self.makeSamplePNG(.systemPink)
        let first = try store.importImage(from: source)
        let second = try store.importImage(from: source)
        #expect(first == second)
    }

    @Test func inMemoryImportSanitizesThePreferredExtension() throws {
        // Clipboard and drag providers supply type identifiers, so the in-memory import
        // path must defend itself instead of trusting the caller-provided suffix.
        let store = Self.tempStore()
        let bytes = try Self.makeSamplePNGData(.systemGreen)

        let reference = try store.importImage(data: bytes, preferredExtension: "../evil.png")
        let resolved = try #require(store.url(for: reference))

        #expect(!reference.fileName.contains("/"))
        #expect(!reference.fileName.contains(".."))
        #expect(resolved.deletingLastPathComponent() == store.directory)
        #expect(resolved.pathExtension == "png")
        #expect(store.image(for: reference) != nil)
    }

    @Test func inMemoryImportKeepsSafeImageExtensions() throws {
        let store = Self.tempStore()
        let bytes = try Self.makeSamplePNGData(.systemOrange)

        let reference = try store.importImage(data: bytes, preferredExtension: "PNG")

        #expect(reference.fileName.hasSuffix(".png"))
        #expect(store.image(for: reference) != nil)
    }

    @Test func importingANonImageThrows() throws {
        // A file that is not a decodable image is rejected, so the store never
        // holds junk.
        let store = Self.tempStore()
        let notImage = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        try Data("not an image".utf8).write(to: notImage)
        #expect(throws: BackgroundImageStore.ImportError.self) {
            try store.importImage(from: notImage)
        }
    }

    // MARK: - Image store: download from URL (CS-082, Phase 4)

    @Test func downloadingFromURLImportsAndResolves() async throws {
        // A stubbed loader returns valid PNG bytes with a 200; the image imports
        // into the container and resolves like a picked file.
        let store = Self.tempStore()
        let bytes = try Self.makeSamplePNGData()
        let url = URL(string: "https://example.com/banner.png")!
        let reference = try await store.importImage(downloadedFrom: url) { url in
            (bytes, Self.httpResponse(for: url))
        }
        let resolved = try #require(store.url(for: reference))
        #expect(resolved.path.hasPrefix(store.directory.path))
        #expect(store.image(for: reference) != nil)
    }

    @Test func downloadedAndLocalImportOfSameBytesDedupe() async throws {
        // A file picked from disk and the same bytes fetched from a URL are
        // content-addressed to one stored file — the shared store path.
        let store = Self.tempStore()
        let color = NSColor.systemTeal
        let local = try store.importImage(from: Self.makeSamplePNG(color))
        let bytes = try Self.makeSamplePNGData(color)
        let remote = try await store.importImage(
            downloadedFrom: URL(string: "https://example.com/x.png")!
        ) { url in (bytes, Self.httpResponse(for: url)) }
        #expect(local == remote)
    }

    @Test func downloadDerivesExtensionFromMIMEWhenURLHasNone() async throws {
        // An endpoint that serves an image from a query carries no path extension;
        // the stored name picks the extension up from the response content type.
        let store = Self.tempStore()
        let bytes = try Self.makeSamplePNGData()
        let url = URL(string: "https://example.com/avatar?id=7")!
        let reference = try await store.importImage(downloadedFrom: url) { url in
            (bytes, Self.httpResponse(for: url, mime: "image/png"))
        }
        #expect(reference.fileName.hasSuffix(".png"))
    }

    @Test func downloadRejectsNonHTTPScheme() async {
        // A non-http(s) URL is refused before any fetch, so the field can never be
        // used to read a local file path.
        let store = Self.tempStore()
        var didLoad = false
        await #expect(throws: BackgroundImageStore.ImportError.downloadFailed) {
            _ = try await store.importImage(downloadedFrom: URL(string: "file:///etc/passwd")!) {
                _ in
                didLoad = true
                return (Data(), Self.httpResponse(for: URL(string: "file:///x")!))
            }
        }
        #expect(!didLoad)
    }

    @Test func downloadRejectsPrivateInitialHostBeforeLoading() async {
        // The image URL field cannot be used as an SSRF gadget for loopback/link-local
        // targets; the loader is never invoked for a refused host.
        let store = Self.tempStore()
        var didLoad = false
        await #expect(throws: BackgroundImageStore.ImportError.downloadFailed) {
            _ = try await store.importImage(
                downloadedFrom: URL(string: "http://169.254.169.254/latest/meta-data.png")!
            ) { url in
                didLoad = true
                return (Data(), Self.httpResponse(for: url))
            }
        }
        #expect(!didLoad)
    }

    @Test func downloadRejectsPrivateFinalResponseURL() async throws {
        // A public URL that ends at a private host is discarded. The production session
        // blocks these redirects before following them; this response guard keeps
        // injected/future loaders honest too.
        let store = Self.tempStore()
        let bytes = try Self.makeSamplePNGData()
        await #expect(throws: BackgroundImageStore.ImportError.downloadFailed) {
            _ = try await store.importImage(
                downloadedFrom: URL(string: "https://example.com/banner.png")!
            ) { _ in
                (
                    bytes,
                    Self.httpResponse(for: URL(string: "http://127.0.0.1/private.png")!)
                )
            }
        }
    }

    @Test func remoteImageDownloadPolicyAllowsOnlyPublicWebURLs() {
        #expect(
            BackgroundImageStore.isAllowedRemoteImageDownloadURL(
                URL(string: "https://example.com/image.png")!))
        #expect(
            !BackgroundImageStore.isAllowedRemoteImageDownloadURL(
                URL(string: "ftp://example.com/image.png")!))
        #expect(
            !BackgroundImageStore.isAllowedRemoteImageDownloadURL(
                URL(string: "http://127.1/image.png")!))
        #expect(
            !BackgroundImageStore.isAllowedRemoteImageDownloadURL(
                URL(string: "http://[::ffff:127.0.0.1]/image.png")!))
    }

    @Test func downloadRejectsNonSuccessStatus() async throws {
        let store = Self.tempStore()
        let bytes = try Self.makeSamplePNGData()
        await #expect(throws: BackgroundImageStore.ImportError.downloadFailed) {
            _ = try await store.importImage(
                downloadedFrom: URL(string: "https://example.com/missing.png")!
            ) { url in (bytes, Self.httpResponse(for: url, status: 404)) }
        }
    }

    @Test func downloadRejectsOversizedPayload() async {
        // A payload past the cap is rejected before decoding, bounding memory/disk
        // against a hostile URL.
        let store = Self.tempStore()
        let huge = Data(count: BackgroundImageStore.maxRemoteImageBytes + 1)
        await #expect(throws: BackgroundImageStore.ImportError.tooLarge) {
            _ = try await store.importImage(
                downloadedFrom: URL(string: "https://example.com/big.png")!
            ) { url in (huge, Self.httpResponse(for: url)) }
        }
    }

    @Test func downloadPreservesBoundedLoaderTooLargeError() async {
        // The production loader enforces the cap while streaming; `importImage`
        // must preserve that specific error instead of remapping it to a generic
        // network failure.
        let store = Self.tempStore()
        await #expect(throws: BackgroundImageStore.ImportError.tooLarge) {
            _ = try await store.importImage(
                downloadedFrom: URL(string: "https://example.com/big.png")!
            ) { _ in throw BackgroundImageStore.ImportError.tooLarge }
        }
    }

    @Test func remoteImageByteCollectorRejectsPayloadPastStreamingCap() async {
        // Exercise the default loader's streaming cap with a tiny in-memory stream
        // rather than building a 25 MB network fixture.
        let stream = AsyncStream<UInt8> { continuation in
            for _ in 0..<9 {
                continuation.yield(0x89)
            }
            continuation.finish()
        }

        await #expect(throws: BackgroundImageStore.ImportError.tooLarge) {
            _ = try await BackgroundImageStore.collectRemoteImageBytes(stream, maxBytes: 8)
        }
    }

    @Test func downloadRejectsNonImageBytes() async {
        // Content type is not trusted: bytes that do not decode as an image are
        // refused even with an image MIME and a 200.
        let store = Self.tempStore()
        let notImage = Data("<html>nope</html>".utf8)
        await #expect(throws: BackgroundImageStore.ImportError.notAnImage) {
            _ = try await store.importImage(
                downloadedFrom: URL(string: "https://example.com/page.png")!
            ) { url in (notImage, Self.httpResponse(for: url)) }
        }
    }

    @Test func downloadSurfacesLoaderFailureAsDownloadFailed() async {
        // A thrown network error (offline, DNS, sandbox-blocked) maps to one clear
        // failure rather than leaking the underlying URLError.
        struct Boom: Error {}
        let store = Self.tempStore()
        await #expect(throws: BackgroundImageStore.ImportError.downloadFailed) {
            _ = try await store.importImage(
                downloadedFrom: URL(string: "https://example.com/x.png")!
            ) { _ in throw Boom() }
        }
    }

    @Test func unsafeReferenceNamesNeverResolve() {
        // A hand-edited store cannot escape the backgrounds directory: names with
        // path separators or traversal segments resolve to nil.
        let store = Self.tempStore()
        #expect(store.url(for: ImageReference(fileName: "")) == nil)
        #expect(store.url(for: ImageReference(fileName: "../secret.png")) == nil)
        #expect(store.url(for: ImageReference(fileName: "sub/dir.png")) == nil)
        #expect(store.url(for: ImageReference(fileName: "..")) == nil)
    }

    // MARK: - Persistence (Acceptance: participates in CS-050 persistence)

    @Test func backgroundPersistsAcrossReloadForEveryKind() {
        let kinds: [BackgroundStyle] = [
            .solid(RGBAColor(Color(hex: "#112233"))),
            .gradient(.forest),
            .customGradient(
                CustomGradient(
                    stops: [
                        GradientStop(color: RGBAColor(.red), location: 0),
                        GradientStop(color: RGBAColor(.blue), location: 1),
                    ], angle: 90)),
            .image(
                ImageBackground(
                    reference: ImageReference(fileName: "saved.png"), fit: .fit, blur: 8,
                    dimming: 0.5)),
            .transparent,
        ]
        for kind in kinds {
            let defaults = Self.freshDefaults()
            let settings = AppSettings(defaults: defaults)
            settings.config.background = kind
            let reloaded = AppSettings(defaults: defaults)
            #expect(reloaded.config.background == kind, "background \(kind) did not survive reload")
        }
    }

    @Test func legacyGradientPresetNameStillLoads() {
        // A pre-CS-051 store wrote only a `gradientPreset` name and no
        // `backgroundStyle` blob. That name must still load so an upgrading user
        // keeps their chosen gradient.
        let defaults = Self.freshDefaults()
        defaults.set(GradientPreset.ocean.rawValue, forKey: "gradientPreset")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.config.background == .gradient(.ocean))
    }

    @Test func writingBackgroundClearsLegacyKey() {
        // Once a background is written through the new path, the legacy key is
        // cleared so a stale name can never shadow the JSON value on a later read.
        let defaults = Self.freshDefaults()
        defaults.set(GradientPreset.ocean.rawValue, forKey: "gradientPreset")
        let settings = AppSettings(defaults: defaults)
        settings.config.background = .solid(RGBAColor(.black))
        #expect(defaults.string(forKey: "gradientPreset") == nil)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.config.background == .solid(RGBAColor(.black)))
    }

    @Test func corruptBackgroundBlobFallsBackToDefault() {
        // A garbage `backgroundStyle` blob must not crash init; the default
        // background applies.
        let defaults = Self.freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "backgroundStyle")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.config.background == SnapshotConfig().background)
    }

    // MARK: - Custom gradient geometry

    @Test func customGradientAngleWrapsAndRejectsNonFinite() {
        #expect(CustomGradient(stops: CustomGradient.default.stops, angle: 450).angle == 90)
        #expect(CustomGradient(stops: CustomGradient.default.stops, angle: -90).angle == 270)
        #expect(CustomGradient(stops: CustomGradient.default.stops, angle: .nan).angle == 135)
    }

    @Test func angleMapsToTheDocumentedAxisDirection() {
        // The angle→endpoint mapping is the load-bearing geometry behind every
        // custom-gradient render, and its contract is specific: `0°` runs
        // left→right and `90°` runs top→bottom (clockwise, screen coordinates).
        // A regression here would silently flip gradient direction in every
        // export, so pin the endpoints rather than trusting the angle field alone.
        let tolerance = 1e-9

        let horizontal = CustomGradient(stops: CustomGradient.default.stops, angle: 0).endpoints
        #expect(abs(horizontal.start.x - 0) < tolerance)
        #expect(abs(horizontal.start.y - 0.5) < tolerance)
        #expect(abs(horizontal.end.x - 1) < tolerance)
        #expect(abs(horizontal.end.y - 0.5) < tolerance)

        let vertical = CustomGradient(stops: CustomGradient.default.stops, angle: 90).endpoints
        #expect(abs(vertical.start.x - 0.5) < tolerance)
        #expect(abs(vertical.start.y - 0) < tolerance)
        #expect(abs(vertical.end.x - 0.5) < tolerance)
        #expect(abs(vertical.end.y - 1) < tolerance)
    }

    @Test func renderStopsAreSortedByLocationRegardlessOfInputOrder() {
        // The editor lets a user add stops in any order, and they persist in that
        // order. `sortedStops` is what actually feeds SwiftUI's `Gradient`, so the
        // rendered ramp must follow ascending location no matter how the stops are
        // stored — otherwise the same saved gradient could render differently.
        let gradient = CustomGradient(
            stops: [
                GradientStop(color: RGBAColor(.blue), location: 1),
                GradientStop(color: RGBAColor(.red), location: 0),
                GradientStop(color: RGBAColor(.green), location: 0.5),
            ],
            angle: 45)
        let locations = gradient.sortedStops.map(\.location)
        #expect(locations == [0, 0.5, 1])
    }

    @Test func presetSeedsAnEquivalentCustomGradient() {
        // "Tweak this preset" seeds the editor: the custom gradient carries the
        // preset's colors as ordered stops spanning 0...1.
        let custom = GradientPreset.ocean.asCustomGradient
        #expect(custom.stops.count == GradientPreset.ocean.colors.count)
        #expect(custom.stops.first?.location == 0)
        #expect(custom.stops.last?.location == 1)
    }

    // MARK: - Diagnostics stay non-PII

    @Test func diagnosticsKindNeverLeaksUserContent() {
        // Solid and image kinds report only their kind, never the RGBA or file
        // name, so a diagnostics bundle cannot echo user-specific data (CS-048).
        #expect(BackgroundStyle.solid(RGBAColor(Color(hex: "#ABCDEF"))).diagnosticsKind == "solid")
        #expect(
            BackgroundStyle.image(
                ImageBackground(reference: ImageReference(fileName: "secret.png"))
            )
            .diagnosticsKind == "image")
        #expect(BackgroundStyle.customGradient(.default).diagnosticsKind == "custom-gradient")
        #expect(BackgroundStyle.gradient(.night).diagnosticsKind == "gradient(Night)")
    }
}

// MARK: - Image cache cost (A6 — memory bound)

extension BackgroundTests {
    /// The decoded-byte cost drives the cache's `totalCostLimit`, so it must track the
    /// real bitmap size (pixels × 4), not the point size — a 2× asset would otherwise
    /// be under-counted fourfold and the memory bound would be meaningless.
    @Test func decodedByteCostMeasuresPixelsNotPoints() {
        let image = NSImage(size: NSSize(width: 100, height: 50))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        image.addRepresentation(bitmap)
        // 200 × 100 pixels × 4 bytes, from the bitmap rep — not 100 × 50 points.
        #expect(BackgroundImageStore.decodedByteCost(of: image) == 200 * 100 * 4)
    }

    /// A vector-only image (no bitmap representation) reports the minimum cost of 1, so
    /// it is still subject to the count limit rather than being exempt at zero cost.
    @Test func decodedByteCostFloorsAtOneForAVectorImage() {
        let empty = NSImage(size: NSSize(width: 10, height: 10))
        #expect(BackgroundImageStore.decodedByteCost(of: empty) == 1)
    }
}

import Testing

@testable import Vitrine

// MARK: - Live capture of a local page (real image)

/// The one suite that rasterizes through `WKWebView`. A live capture cannot use a
/// real network in the test host, and validation rejects a `file:` URL, so this
/// drives the engine through the explicit hermetic hook (`init(localFileURL:)`),
/// which loads a local fixture page while still honoring the privacy default (a
/// nonpersistent data store). The shared bitmap path means a URL snapshot sizes
/// identically to an HTML one — exactly `viewport × scale`. It runs only where a web
/// content process can launch and is reported skipped otherwise.
@MainActor
@Suite(
    "URLSnapshotEngine renders a page offscreen · ",
    .enabled("requires a launchable WKWebView web process (unavailable in a sandboxed test host)") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct URLSnapshotEngineRenderTests {
    @Test func aLocalPageRendersToAnImageOfTheRequestedPixelSize() async throws {
        let engine = URLSnapshotEngine()
        let config = try WebSnapshotConfig(
            localFileURL: try URLFixture.writeLocalPage(),
            viewportPreset: .custom(width: 600, height: 400), scale: 2)
        // The data store is the privacy default even on the live path.
        #expect(config.dataStoreMode == .nonPersistent)
        let image = try await engine.snapshot(of: config)
        // The viewport is fixed and the scale is applied, so the bitmap is exactly
        // viewport × scale — the determinism the documented contract requires.
        #expect(image.width == 1200)
        #expect(image.height == 800)
    }

    @Test func theEngineProducesATaggedAssetForALocalPage() async throws {
        // The engine + the exporter's color step yield a real, color-tagged asset —
        // the same `RenderedAsset` shape a code snapshot yields, so the clipboard and
        // save paths stay uniform across input kinds.
        let engine = URLSnapshotEngine()
        let config = try WebSnapshotConfig(
            localFileURL: try URLFixture.writeLocalPage(),
            viewportPreset: .custom(width: 400, height: 300), scale: 1)
        let image = try await engine.snapshot(of: config)
        let asset = RenderedAsset(
            cgImage: ExportManager.normalized(image, to: .sRGB), profile: .sRGB)
        #expect(asset.pixelWidth == 400)
        #expect(asset.pixelHeight == 300)
        #expect(asset.profile == .sRGB)
    }
}

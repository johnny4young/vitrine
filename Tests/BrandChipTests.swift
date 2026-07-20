import AppKit
import CoreGraphics
import Testing
import Vision

@testable import Vitrine

/// the Brand Kit's QR/link chip and the signature footer bar.
@Suite("Brand chips (QR + footer bar)")
@MainActor
struct BrandChipTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineBrandChip-\(UUID().uuidString)")!
    }

    // MARK: - QR generation

    /// The strongest possible check: the generated chip must scan back to the exact
    /// link, via the OS's own barcode detector — if this passes, any phone can read it.
    @Test func generatedQRDecodesBackToTheLink() throws {
        let link = "https://vitrineframe.app/@jane"
        let qr = try #require(QRCodeGenerator.image(for: link))

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: qr)
        try handler.perform([request])
        let payload = try #require(request.results?.first?.payloadStringValue)
        #expect(payload == link)
    }

    @Test func emptyOrBlankLinkGeneratesNoQR() {
        #expect(QRCodeGenerator.image(for: "") == nil)
        #expect(QRCodeGenerator.image(for: "   \n") == nil)
    }

    /// The link persists on the kit, decodes tolerantly when absent (an older store),
    /// and rides into the resolved watermark as the QR identity.
    @Test func linkURLPersistsAndResolvesIntoTheMark() {
        let defaults = isolatedDefaults()
        let store = BrandKitStore(defaults: defaults)
        store.isEnabled = true
        store.brandKit = BrandKit(handle: "@jane", linkURL: "https://example.com/jane")

        let reloaded = BrandKitStore(defaults: defaults)
        #expect(reloaded.brandKit.linkURL == "https://example.com/jane")

        let mark = reloaded.resolvedWatermark(isPro: true)
        #expect(mark?.qrImage != nil)
        #expect(mark?.qrIdentity == "https://example.com/jane")
    }

    /// A kit with only a link still resolves a mark (the QR alone is content), and the
    /// PRO gate still wins.
    @Test func linkOnlyKitResolvesAMarkOnlyUnderPro() {
        let store = BrandKitStore(defaults: isolatedDefaults())
        store.isEnabled = true
        store.brandKit = BrandKit(linkURL: "https://example.com")
        #expect(store.resolvedWatermark(isPro: true) != nil)
        #expect(store.resolvedWatermark(isPro: false) == nil)
    }

    /// The QR chip changes the exported pixels.
    @Test func qrChipChangesTheRenderedPixels() throws {
        var plain = SnapshotConfig()
        plain.code = "let x = 1"
        var marked = plain
        var watermark = Watermark(text: "@jane")
        watermark.qrImage = QRCodeGenerator.image(for: "https://example.com").map {
            NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
        }
        watermark.qrIdentity = "https://example.com"
        marked.watermark = watermark
        #expect(try png(plain) != png(marked))
    }

    // MARK: - Footer bar

    /// The footer bar renders (pixels change) and differs from the corner badge for
    /// the same mark content.
    @Test func footerBarRendersAndDiffersFromTheCornerBadge() throws {
        var base = SnapshotConfig()
        base.code = "let x = 1"

        var corner = base
        corner.watermark = Watermark(text: "@jane · vitrine", placement: .bottomTrailing)
        var footer = base
        footer.watermark = Watermark(text: "@jane · vitrine", placement: .footerBar)

        #expect(try png(base) != png(footer), "the footer bar must change the exported image")
        #expect(
            try png(corner) != png(footer),
            "the footer bar must render differently from the corner badge")
    }

    /// `.footerBar` persists through the kit and an unknown placement in an older
    /// build's store degrades to the default rather than failing the decode.
    @Test func footerBarPlacementPersists() {
        let defaults = isolatedDefaults()
        let store = BrandKitStore(defaults: defaults)
        store.brandKit = BrandKit(handle: "@jane", placement: .footerBar)
        #expect(BrandKitStore(defaults: defaults).brandKit.placement == .footerBar)
    }

    // MARK: - Render helper (mirrors AnnotationTests.png)

    private func png(
        _ config: SnapshotConfig, size: CGSize = CGSize(width: 320, height: 200)
    ) throws -> Data {
        let cg = try #require(
            ExportManager.renderCGImage(config, scale: 1, fixedSize: size))
        return try #require(ExportManager.pngData(from: cg))
    }
}

// MARK: - reload() cache invalidation

extension BrandChipTests {
    /// `reload()` mirrors an external change into memory; the QR cache must rebuild
    /// from the NEW link, not serve the stale bitmap. The link is written straight to
    /// the backing defaults (bypassing the observed setter) so only reload() can pick
    /// it up — the scenario a settings reset/import produces.
    @Test func reloadRebuildsTheQRCacheFromTheStoredLink() throws {
        let defaults = isolatedDefaults()
        let store = BrandKitStore(defaults: defaults)
        store.isEnabled = true
        store.brandKit = BrandKit(handle: "@jane", linkURL: "https://example.com/old")
        #expect(store.resolvedWatermark(isPro: true)?.qrIdentity == "https://example.com/old")

        // Simulate an external writer: persist a different link behind the store's back.
        var external = store.brandKit
        external.linkURL = "https://example.com/new"
        defaults.set(try JSONEncoder().encode(external), forKey: BrandKitStore.storageKey)

        store.reload()
        let mark = try #require(store.resolvedWatermark(isPro: true))
        #expect(mark.qrIdentity == "https://example.com/new")
        #expect(mark.qrImage != nil)
    }
}

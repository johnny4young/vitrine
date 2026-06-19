import AppKit
import Foundation
import Testing

@testable import Vitrine

/// CS-092 — the PRO Brand Kit: the brand-kit model, the store's resolver gate
/// (disabled / not-PRO / empty all yield no watermark), persistence, the logo
/// round-trip, and the render-core guarantee that a watermark is purely additive —
/// `nil` renders byte-identically to today's output, and a present watermark visibly
/// changes the image.
@Suite("Brand Kit · CS-092")
@MainActor
struct BrandKitTests {
    /// A throwaway defaults suite so each test's persistence is isolated from the
    /// real app container and from the other tests.
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineBrandKit-\(UUID().uuidString)")!
    }

    /// A store rooted at an isolated defaults suite and a temporary image directory,
    /// so logo imports never touch the user's container.
    private func isolatedStore() -> (BrandKitStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineBrandKitTest-\(UUID().uuidString)", isDirectory: true)
        let store = BrandKitStore(
            defaults: isolatedDefaults(), imageStore: BackgroundImageStore(directory: dir))
        return (store, dir)
    }

    // MARK: - Model

    @Test func hasContentReflectsLogoOrText() {
        #expect(!BrandKit().hasContent)
        #expect(BrandKit(handle: "@jane").hasContent)
        #expect(BrandKit(project: "vitrine").hasContent)
        // All-whitespace is normalized away, so it counts as empty.
        #expect(!BrandKit(handle: "   ").hasContent)
    }

    @Test func watermarkTextComposesAndOmitsBlanks() {
        #expect(BrandKit(handle: "@jane", project: "vitrine").watermarkText == "@jane · vitrine")
        #expect(BrandKit(handle: "@jane").watermarkText == "@jane")
        #expect(BrandKit(project: "vitrine").watermarkText == "vitrine")
        #expect(BrandKit().watermarkText.isEmpty)
    }

    @Test func everyPlacementHasALabelAndAlignment() {
        for placement in Watermark.Placement.allCases {
            #expect(!placement.label.isEmpty)
        }
        // The four corner placements map to a real corner alignment; `.free` has no
        // corner anchor — it is positioned by `freePosition`, so `.center` is just its
        // exhaustive fallback.
        for placement in Watermark.Placement.allCases where placement != .free {
            #expect(placement.alignment != .center)
        }
    }

    // MARK: - Free placement (CS-092 follow-up)

    @Test func freePlacementPersistsItsPositionAndResolvesIntoTheMark() {
        let defaults = isolatedDefaults()
        let first = BrandKitStore(defaults: defaults)
        first.isEnabled = true
        first.brandKit = BrandKit(
            handle: "@jane", placement: .free, freePosition: CGPoint(x: 0.25, y: 0.7))

        // Persists across instances.
        let second = BrandKitStore(defaults: defaults)
        #expect(second.brandKit.placement == .free)
        #expect(second.brandKit.freePosition == CGPoint(x: 0.25, y: 0.7))

        // The resolver carries the free position into the render-ready mark.
        let mark = second.resolvedWatermark(isPro: true)
        #expect(mark?.placement == .free)
        #expect(mark?.freePosition == CGPoint(x: 0.25, y: 0.7))
    }

    @Test func freePositionIsClampedIntoTheCanvas() {
        #expect(Watermark.clampFreePosition(CGPoint(x: -0.5, y: 2)) == CGPoint(x: 0, y: 1))
        #expect(Watermark.clampFreePosition(CGPoint(x: 0.3, y: 0.6)) == CGPoint(x: 0.3, y: 0.6))
        // BrandKit's init clamps an out-of-range position.
        let kit = BrandKit(placement: .free, freePosition: CGPoint(x: 5, y: -1))
        #expect(kit.freePosition == CGPoint(x: 1, y: 0))
    }

    @Test func brandKitDecodesWithoutAFreePositionToTheDefault() throws {
        // A kit persisted before free placement (no freePosition key) decodes cleanly.
        let json = #"{"handle":"@jane","project":"","placement":"bottomTrailing"}"#
        let kit = try JSONDecoder().decode(BrandKit.self, from: Data(json.utf8))
        #expect(kit.freePosition == CGPoint(x: 0.84, y: 0.9))
    }

    @Test func aspectFitRectLetterboxesByAspectRatio() {
        // A 2:1 image in a 100×100 box fits to 100×50, centered vertically.
        let rect = FreeWatermarkDragHandle.aspectFitRect(
            imageSize: CGSize(width: 200, height: 100), in: CGSize(width: 100, height: 100))
        #expect(rect == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    // MARK: - Resolver gate

    @Test func resolverYieldsNothingUnlessEnabledProAndNonEmpty() {
        let (store, _) = isolatedStore()
        store.brandKit = BrandKit(handle: "@jane")

        // Disabled → no mark even with PRO and content.
        store.isEnabled = false
        #expect(store.resolvedWatermark(isPro: true) == nil)

        // Enabled but free → no mark (the open-core gate).
        store.isEnabled = true
        #expect(store.resolvedWatermark(isPro: false) == nil)

        // Enabled + PRO but empty → no mark.
        store.brandKit = BrandKit()
        #expect(store.resolvedWatermark(isPro: true) == nil)
    }

    @Test func resolverProducesTheMarkWhenEnabledProAndNonEmpty() {
        let (store, _) = isolatedStore()
        store.isEnabled = true
        store.brandKit = BrandKit(
            handle: "@jane", project: "vitrine", placement: .topLeading)
        let mark = store.resolvedWatermark(isPro: true)
        #expect(mark?.text == "@jane · vitrine")
        #expect(mark?.placement == .topLeading)
        #expect(mark?.logoImageData == nil)  // text-only kit
    }

    // MARK: - Persistence + logo

    @Test func brandKitAndSwitchPersistAcrossInstances() {
        let defaults = isolatedDefaults()
        let first = BrandKitStore(defaults: defaults)
        first.isEnabled = true
        first.brandKit = BrandKit(handle: "@jane", project: "vitrine", placement: .bottomLeading)

        let second = BrandKitStore(defaults: defaults)
        #expect(second.isEnabled)
        #expect(second.brandKit.handle == "@jane")
        #expect(second.brandKit.project == "vitrine")
        #expect(second.brandKit.placement == .bottomLeading)
    }

    @Test func importingALogoMakesItAvailableAndCarriesItIntoTheMark() throws {
        let (store, dir) = isolatedStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.isEnabled = true

        // A tiny real PNG written to a temp file, then imported through the store.
        let source = dir.appendingPathComponent("logo-source.png")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.tinyPNG().write(to: source)

        #expect(store.importLogo(from: source))
        #expect(store.logoImage != nil)
        // A logo alone is enough content, and it rides into the resolved mark.
        let mark = store.resolvedWatermark(isPro: true)
        #expect(mark?.logoImageData != nil)
        #expect(mark?.logoImage != nil)
    }

    @Test func resetToDefaultsClearsPersistedBrandKitState() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        let store = BrandKitStore(defaults: defaults)

        store.isEnabled = true
        store.brandKit = BrandKit(handle: "@jane", project: "vitrine", placement: .topTrailing)

        settings.resetToDefaults()
        store.reload()

        #expect(!store.isEnabled)
        #expect(store.brandKit == BrandKit())
        #expect(defaults.object(forKey: BrandKitStore.storageKey) == nil)
        #expect(defaults.object(forKey: BrandKitStore.enabledStorageKey) == nil)
    }

    // MARK: - Render core (additive + byte-stable)

    @Test func defaultConfigHasNoWatermark() {
        // The additive default-off guarantee at the unit level: every freshly built
        // config (the golden suite's starting point) carries no watermark, so the
        // canvas takes its unchanged path.
        #expect(SnapshotConfig().watermark == nil)
    }

    @Test func aWatermarkChangesTheRenderWhileNilIsStable() throws {
        var config = SnapshotConfig()
        config.code = "let answer = 42"

        // Rendering is deterministic: the same watermark-free config twice → identical bytes.
        let plainA = try render(config)
        let plainB = try render(config)
        #expect(plainA == plainB)

        // Adding a watermark visibly changes the output (the overlay is actually drawn).
        config.watermark = Watermark(text: "@jane · vitrine", logoImageData: nil, tint: nil)
        let marked = try render(config)
        #expect(marked != plainA)
    }

    private func render(_ config: SnapshotConfig) throws -> Data {
        let image = try #require(ExportManager.renderCGImage(config, scale: 2, fixedSize: nil))
        return try #require(ExportManager.pngData(from: image))
    }

    /// A minimal valid PNG (a 2×2 image) for the logo import round-trip.
    private static func tinyPNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}

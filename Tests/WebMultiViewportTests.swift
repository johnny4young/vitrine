import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

/// CS-044 multi-resolution capture: the viewport selection set and the composite
/// "responsive board". The single-viewport baseline lives in `WebSnapshotConfigTests`.

@Suite("Web multi-viewport selection · CS-044")
@MainActor
struct WebMultiViewportSelectionTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineWebMultiViewport-\(UUID().uuidString)")!
    }

    @Test func viewportsDefaultsToTheSingleViewportWhenUnset() {
        #expect(WebDefaults.viewports(from: defaults()) == [.openGraph])
    }

    @Test func viewportsRoundTripsInSelectionOrder() {
        let store = defaults()
        store.set(["mobile", "desktop", "fullHD"], forKey: "webViewports")
        #expect(WebDefaults.viewports(from: store) == [.mobile, .desktop, .fullHD])
    }

    @Test func loggedInSessionIsOffByDefaultAndDrivesTheDataStoreMode() {
        let store = defaults()
        let settings = WebCaptureSettings(defaults: store)
        // Privacy default: no cookies, private per-render store (CS-043).
        #expect(settings.usesLoggedInSession == false)
        #expect(settings.dataStoreMode == .nonPersistent)

        // Opting in switches to the persistent (cookie) store and persists.
        settings.usesLoggedInSession = true
        #expect(settings.dataStoreMode == .persistent)
        #expect(WebCaptureSettings(defaults: store).usesLoggedInSession == true)
    }

    @Test func loggedInSessionPreferenceIsPartOfTheCurrentSettingsSchema() {
        // Adding a persisted key must advance the schema so installs already stamped at
        // the previous version are still recognized as needing this additive step.
        #expect(SettingsSchema.current >= 11)
        #expect(SettingsCodec.Keys.all.contains(SettingsCodec.Keys.webUsesLoggedInSession))
    }

    @Test func viewportsDropsDuplicatesKeepingFirstOrder() {
        let store = defaults()
        store.set(["mobile", "desktop", "mobile"], forKey: "webViewports")
        #expect(WebDefaults.viewports(from: store) == [.mobile, .desktop])
    }

    @Test func viewportsDropsUnknownRawValues() {
        let store = defaults()
        store.set(["mobile", "totally-bogus", "custom"], forKey: "webViewports")
        #expect(WebDefaults.viewports(from: store) == [.mobile, .custom])
    }

    @Test func viewportsFallsBackToTheSingleViewportWhenStoredEmpty() {
        let store = defaults()
        store.set([String](), forKey: "webViewports")
        store.set("desktop", forKey: "webViewportKind")
        #expect(WebDefaults.viewports(from: store) == [.desktop])
    }

    @Test func selectionPersistsAcrossReloads() {
        let store = defaults()
        let first = AppSettings(defaults: store)
        first.webCapture.viewports = [.mobile, .fullHD]
        let second = AppSettings(defaults: store)
        #expect(second.webCapture.viewports == [.mobile, .fullHD])
    }

    @Test func selectedPresetsResolveTheStoredCustomSize() {
        let settings = AppSettings(defaults: defaults())
        settings.webCapture.customViewportWidth = 800
        settings.webCapture.customViewportHeight = 600
        settings.webCapture.viewports = [.mobile, .custom]
        let presets = settings.webCapture.selectedViewportPresets
        #expect(presets == [.mobile, .custom(width: 800, height: 600)])
    }

    @Test func selectedPresetsFallBackToTheSingleViewportWhenEmpty() {
        let settings = AppSettings(defaults: defaults())
        settings.webCapture.viewports = []
        #expect(settings.webCapture.selectedViewportPresets == [settings.webCapture.viewportPreset])
    }

    @Test func selectedPresetsDropDuplicateKindsKeepingFirstOrder() {
        // `viewports` is an unconstrained array; a repeated kind must not render — or compose
        // into the board — the same viewport twice (PR #2 review).
        let settings = AppSettings(defaults: defaults())
        settings.webCapture.viewports = [.mobile, .desktop, .mobile, .desktop]
        #expect(settings.webCapture.selectedViewportPresets == [.mobile, .desktop])
    }
}

@Suite("Responsive board composite · CS-044")
@MainActor
struct ResponsiveBoardComposerTests {
    @Test func composingAnEmptySetReturnsNil() {
        #expect(ResponsiveBoardComposer.compose([], scale: 1, profile: .sRGB) == nil)
    }

    @Test func boardSizeIsDeterministicFromTheInputs() throws {
        let captures = [capture(.mobile, 200, 400), capture(.desktop, 600, 200)]
        let asset = try #require(
            ResponsiveBoardComposer.compose(captures, scale: 1, profile: .sRGB))

        // Height is fixed: padding*2 + cardImageHeight + labelGap + labelHeight. Width is
        // padding*2 + each card's column width + the inter-card spacing, where a column is
        // at least `minColumnWidth` wide so a narrow capture still hosts a legible caption.
        let expectedHeight =
            ResponsiveBoardComposer.padding * 2 + ResponsiveBoardComposer.cardImageHeight
            + ResponsiveBoardComposer.labelGap + ResponsiveBoardComposer.labelHeight
        let columnWidths = captures.map { item -> CGFloat in
            let width = CGFloat(item.asset.cgImage.width)
            let height = CGFloat(item.asset.cgImage.height)
            let imageWidth = (ResponsiveBoardComposer.cardImageHeight * (width / height)).rounded()
            return max(imageWidth, ResponsiveBoardComposer.minColumnWidth)
        }
        let expectedWidth =
            ResponsiveBoardComposer.padding * 2 + columnWidths.reduce(0, +)
            + ResponsiveBoardComposer.spacing * CGFloat(captures.count - 1)

        // ImageRenderer can round the final bitmap by a pixel; allow a small tolerance.
        #expect(abs(CGFloat(asset.cgImage.height) - expectedHeight) <= 2)
        #expect(abs(CGFloat(asset.cgImage.width) - expectedWidth) <= 2)

        // Determinism: identical inputs yield identical dimensions.
        let again = try #require(
            ResponsiveBoardComposer.compose(captures, scale: 1, profile: .sRGB))
        #expect(again.cgImage.width == asset.cgImage.width)
        #expect(again.cgImage.height == asset.cgImage.height)
    }

    @Test func boardCaptionSplitsNameFromDimensions() {
        // The board caption is two lines: the name above its dimensions. The split is
        // asserted structurally (not against a translated name) so it stays locale-robust:
        // every preset yields a non-empty name with no parenthesized size, and the
        // dimensions track the displayName's shape — present (and carrying the "×") when it
        // has a parenthesized size, empty when it does not (the property's documented
        // fallback).
        let presets =
            WebSnapshotConfig.ViewportPreset.fixedPresets
            + [.custom(clampingWidth: 800, height: 600)]
        for preset in presets {
            #expect(!preset.boardName.isEmpty)
            #expect(!preset.boardName.contains("("))
            if preset.displayName.contains("(") {
                #expect(preset.boardDimensions.contains("×"))
            } else {
                #expect(preset.boardDimensions.isEmpty)
            }
        }
    }

    @Test func capturedViewportsKeepASeparateBoundedThumbnail() {
        let capture = capture(.desktop, 4_000, 3_000)

        #expect(capture.asset.cgImage.width == 4_000)
        #expect(capture.asset.cgImage.height == 3_000)
        #expect(capture.thumbnailAsset.cgImage.width <= CapturedViewport.thumbnailMaxPixelWidth)
        #expect(capture.thumbnailAsset.cgImage.height <= CapturedViewport.thumbnailMaxPixelHeight)
        #expect(capture.thumbnailAsset.cgImage.width < capture.asset.cgImage.width)
        #expect(capture.thumbnailAsset.cgImage.height < capture.asset.cgImage.height)
    }

    private func capture(
        _ kind: WebSnapshotConfig.ViewportPreset.Kind, _ width: Int, _ height: Int
    ) -> CapturedViewport {
        CapturedViewport(
            kind: kind,
            preset: .resolve(kind: kind, customWidth: width, customHeight: height),
            asset: RenderedAsset(cgImage: Self.solid(width, height), profile: .sRGB))
    }

    private static func solid(_ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

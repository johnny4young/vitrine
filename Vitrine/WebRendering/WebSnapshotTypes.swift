import AppKit
import SwiftUI

/// Which kind of web input the Web Snapshot surface is composing.
enum WebInputMode: String, CaseIterable, Identifiable {
    /// A user-provided `http`/`https` URL, captured locally in WebKit.
    case url
    /// A pasted HTML fragment or document, rendered locally with remote subresources
    /// blocked.
    case html

    var id: String { rawValue }
}

/// One viewport's capture in a multi-resolution batch: the size it was
/// rendered at and the resulting asset, for the result gallery and the responsive board.
struct CapturedViewport: Identifiable {
    let kind: WebSnapshotConfig.ViewportPreset.Kind
    let preset: WebSnapshotConfig.ViewportPreset
    let asset: RenderedAsset
    let thumbnailAsset: RenderedAsset
    /// Unique within a batch — the selected viewport set is de-duplicated by kind.
    var id: WebSnapshotConfig.ViewportPreset.Kind { kind }
    /// A short label for the result tile, e.g. "Desktop (1440 × 900)".
    var label: String { preset.displayName }

    /// The filmstrip renders thumbnails at 92×58 pt. Keeping a 2× bitmap avoids
    /// handing SwiftUI full-page captures to downscale on every layout pass.
    static let thumbnailMaxPixelWidth = 184
    static let thumbnailMaxPixelHeight = 116

    init(
        kind: WebSnapshotConfig.ViewportPreset.Kind,
        preset: WebSnapshotConfig.ViewportPreset,
        asset: RenderedAsset,
        thumbnailAsset: RenderedAsset? = nil
    ) {
        self.kind = kind
        self.preset = preset
        self.asset = asset
        self.thumbnailAsset = thumbnailAsset ?? Self.makeThumbnail(from: asset)
    }

    static func makeThumbnail(from asset: RenderedAsset) -> RenderedAsset {
        let source = asset.cgImage
        guard source.width > 0, source.height > 0 else { return asset }

        let scale = min(
            CGFloat(thumbnailMaxPixelWidth) / CGFloat(source.width),
            CGFloat(thumbnailMaxPixelHeight) / CGFloat(source.height),
            1)
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard width < source.width || height < source.height else { return asset }

        let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard
            let colorSpace,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return asset
        }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage() else { return asset }
        return RenderedAsset(cgImage: thumbnail, profile: asset.profile)
    }
}

/// One viewport's rendering strategy, injected into ``WebSnapshotModel`` so the
/// document orchestration is testable independently of WebKit's process host.
/// Production always uses ``live``; UI automation can use the DEBUG-only fixture
/// because ad-hoc-signed XCTest hosts do not consistently launch WebKit's
/// out-of-process renderer.
struct WebSnapshotViewportRenderer {
    let render:
        @MainActor (CaptureInput, WebSnapshotConfig.ViewportPreset, AppSettings) async throws ->
            RenderedAsset

    /// The production strategy: route local HTML through `HTMLRenderer` and URLs
    /// through `URLRenderer`, preserving the user's viewport, scale, color, wait,
    /// session, and loopback policies.
    static let live = Self { input, preset, settings in
        switch input {
        case .html:
            let renderer = HTMLRenderer(
                viewport: preset.size,
                scale: CGFloat(settings.export.scale),
                profile: settings.export.colorProfile)
            return try await renderer.render(input, config: settings.config)
        case .url:
            let renderer = URLRenderer(
                scale: CGFloat(settings.export.scale),
                viewportPreset: preset,
                captureMode: settings.webCapture.captureMode,
                waitStrategy: settings.webCapture.waitStrategy,
                profile: settings.export.colorProfile,
                dataStoreMode: settings.webCapture.dataStoreMode,
                allowsLoopbackCapture: settings.webCapture.allowsLoopbackCapture)
            return try await renderer.render(input, config: settings.config)
        case .code:
            // The Web Snapshot flow only resolves `.url`/`.html`; keep an impossible
            // route typed instead of returning a blank image.
            throw RenderError.noRendererFor(kind: "code")
        }
    }

    #if DEBUG
        /// Deterministic local pixels for the strict UI journey. This substitutes only
        /// the process boundary that XCTest cannot host; the model still performs the
        /// real multi-viewport scheduling, responsive-board composition, selection,
        /// export, clipboard, and feedback paths.
        static let uiTestFixture = Self { input, preset, settings in
            guard case .html(let html) = input,
                !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw RenderError.renderFailed
            }

            let scale = CGFloat(settings.export.scale)
            let allocation: RenderBudget.Allocation
            do throws(RenderBudgetError) {
                allocation = try RenderBudget.export.allocation(
                    for: preset.size, scale: scale)
            } catch .tooLarge(let rejection) {
                throw RenderError.renderTooLarge(rejection)
            } catch {
                throw RenderError.renderFailed
            }
            guard let colorSpace = settings.export.colorProfile.cgColorSpace,
                let context = CGContext(
                    data: nil,
                    width: allocation.pixelWidth,
                    height: allocation.pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                throw RenderError.renderFailed
            }

            let width = CGFloat(allocation.pixelWidth)
            let height = CGFloat(allocation.pixelHeight)
            let canvas = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(srgbRed: 0.043, green: 0.063, blue: 0.125, alpha: 1))
            context.fill(canvas)

            let inset = max(24, min(CGFloat(width), CGFloat(height)) * 0.12)
            context.setFillColor(CGColor(srgbRed: 0.082, green: 0.122, blue: 0.235, alpha: 1))
            context.fill(canvas.insetBy(dx: inset, dy: inset))
            context.setFillColor(CGColor(srgbRed: 0.655, green: 0.957, blue: 0.816, alpha: 1))
            context.fill(
                CGRect(
                    x: inset * 1.35,
                    y: CGFloat(height) * 0.48,
                    width: max(1, CGFloat(width) - inset * 2.7),
                    height: max(8, CGFloat(height) * 0.035)))

            guard let image = context.makeImage() else { throw RenderError.renderFailed }
            return RenderedAsset(cgImage: image, profile: settings.export.colorProfile)
        }
    #endif
}

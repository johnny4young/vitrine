import CoreGraphics
import Foundation
import OSLog

/// Captures a user-provided URL by loading the page **locally** in an offscreen
/// `WKWebView` and rasterizing it.
///
/// URL screenshots are part of web capture, but they keep Vitrine's privacy promise:
/// the page is loaded on this Mac and turned into a bitmap on-device — there is
/// **no remote render service**. The renderer slots into the existing `Renderer`
/// abstraction so a coordinator routes a `.url` input here exactly as it
/// routes code to `CodeRenderer` and HTML to `HTMLRenderer`.
///
/// ## Safety gate
///
/// Two gates stand in front of any load:
///
/// 1. **The network entitlement.** URL capture is disabled until the app target
///    carries `com.apple.security.network.client`; without it the renderer throws
///    `RenderError.urlCaptureDisabled` before touching WebKit, because a sandboxed
///    build with no network entitlement cannot reach a remote page anyway. The network-free
///    distribution ships without the entitlement, so this renderer remains unavailable there.
/// 2. **URL validation.** Only `http`/`https` URLs are accepted; `file:`, `data:`,
///    `javascript:`, private localhost, and malformed URLs are refused as typed
///    `URLValidationError`s mapped to `RenderError.renderFailed`. Validation runs
///    even when the input already carries a `URL`, so a malformed or non-web URL
///    that reached classification is still rejected here.
///
/// ## Privacy defaults
///
/// The offscreen engine uses `WKWebsiteDataStore.nonPersistent()` by default, so
/// cookies, caches, and local storage live only for the single render; cookies and
/// persistent website data are opt-in only (`WebSnapshotConfig.DataStoreMode`). The
/// web view is never added to a window, so the snapshot reads the view's own layer
/// and no Screen Recording permission is involved.
struct URLRenderer: Renderer {
    /// Output scale (1/2/3), matching `ExportManager`'s default.
    var scale: CGFloat = 2

    /// The viewport preset the page is laid out in. Defaults to Open Graph's 1200×630,
    /// with desktop, full-HD, mobile, and custom alternatives.
    var viewportPreset: WebSnapshotConfig.ViewportPreset = .openGraph

    /// Whether to capture the visible viewport or the full scrollable page.
    /// `.visibleViewport` by default — the deterministic, preset-sized capture.
    var captureMode: WebSnapshotConfig.CaptureMode = .visibleViewport

    /// How long, and on what signal, to wait before snapshotting.
    /// `.domContentLoaded` by default — snapshot as soon as the load settles.
    var waitStrategy: WebSnapshotConfig.WaitStrategy = .domContentLoaded

    /// The memory- and time-safety ceilings applied to every capture.
    /// Always applied; bounds the captured page height and the total wait.
    var safetyCaps: WebSnapshotConfig.SafetyCaps = .standard

    /// Color profile to tag the output with — sRGB by default.
    var profile: ColorProfile = .sRGB

    /// What the web view may persist. `.nonPersistent` by default; `.persistent` is
    /// an explicit opt-in that enables cookies and persistent website data.
    var dataStoreMode: WebSnapshotConfig.DataStoreMode = .nonPersistent

    /// Whether this capture may reach this Mac's loopback interface. Default-off and
    /// deliberately narrower than access to local or private networks.
    var allowsLoopbackCapture = false

    /// Whether the build is permitted to reach the network for a capture. Injectable
    /// so the gate is testable without an entitlement; defaults to the running app's
    /// real entitlement, so production behavior matches the build's capabilities.
    var isNetworkCaptureEnabled: Bool = NetworkCapability.isURLCaptureEnabled

    /// The offscreen engine that actually loads and rasterizes the page. Injectable
    /// for tests; defaults to the real WebKit-backed engine.
    var engine: URLSnapshotEngine = .init()

    /// Accepts only the URL input; code and HTML are handled by their own renderers.
    func canRender(_ input: CaptureInput) -> Bool {
        if case .url = input { return true }
        return false
    }

    /// Renders a `.url` input to a `RenderedAsset` by loading the page locally.
    ///
    /// Order of operations: confirm the network entitlement, validate the URL into a
    /// `WebSnapshotConfig` (which can only hold an approved `http`/`https` URL),
    /// load it offscreen with the chosen data-store mode, then normalize and tag the
    /// bitmap with `profile` so a URL snapshot flows through the same
    /// clipboard/save/share paths as a code snapshot. Any failure throws a typed
    /// error — never a blank image.
    func render(_ input: CaptureInput, config: SnapshotConfig) async throws -> RenderedAsset {
        guard case .url(let url) = input else {
            throw RenderError.noRendererFor(kind: input.diagnosticKind)
        }

        // Gate 1: the network entitlement. Without it, URL capture is disabled — a
        // sandboxed build with no network entitlement cannot load a remote page, so
        // refuse early with a clear, typed reason instead of failing inside WebKit.
        guard isNetworkCaptureEnabled else {
            Log.render.error("URL capture is disabled: the network client entitlement is absent")
            throw RenderError.urlCaptureDisabled
        }

        // Gate 2: validation. Build the config from the URL; an unsupported scheme,
        // a private localhost host, or a malformed URL throws here. Never log the URL
        // itself — only the non-PII validation reason.
        let webConfig: WebSnapshotConfig
        do {
            webConfig = try WebSnapshotConfig(
                captureURL: url,
                viewportPreset: viewportPreset,
                captureMode: captureMode,
                waitStrategy: waitStrategy,
                safetyCaps: safetyCaps,
                scale: scale,
                profile: profile,
                dataStoreMode: dataStoreMode,
                allowsLoopbackCapture: allowsLoopbackCapture)
        } catch let error as URLValidationError {
            Log.render.error(
                "URL capture rejected the URL (\(error.diagnosticReason, privacy: .public))")
            if error == .privateLocalhost, !allowsLoopbackCapture, let host = url.host,
                WebSnapshotConfig.isLoopbackHost(host: host)
            {
                throw RenderError.loopbackCaptureDisabled
            }
            throw RenderError.renderFailed
        }

        let rawImage: CGImage
        do {
            rawImage = try await engine.snapshot(of: webConfig)
        } catch let error as WebSnapshotError {
            // Non-PII only: the typed failure mode, never the URL.
            Log.render.error(
                "URL capture failed to snapshot the page (\(error.diagnosticReason, privacy: .public))"
            )
            throw RenderError.renderFailed
        }

        let normalized = ExportManager.normalized(rawImage, to: profile)
        return RenderedAsset(cgImage: normalized, profile: profile)
    }
}

extension URLRenderer {
    /// Builds a renderer configured from the user's persisted web-capture settings:
    /// the chosen viewport preset, capture mode, and wait strategy, plus
    /// the shared export scale and color profile.
    ///
    /// This is the seam that connects the Input pane's controls to the URL render
    /// path. URL capture stays gated on the network entitlement, so the resulting
    /// renderer is still inert in a network-free build; when the entitlement is added, the
    /// coordinator can build the renderer from settings so a capture uses exactly the
    /// viewport and timing the user selected.
    static func configured(from settings: AppSettings) -> URLRenderer {
        URLRenderer(
            scale: CGFloat(settings.export.scale),
            viewportPreset: settings.webCapture.viewportPreset,
            captureMode: settings.webCapture.captureMode,
            waitStrategy: settings.webCapture.waitStrategy,
            profile: settings.export.colorProfile,
            dataStoreMode: settings.webCapture.dataStoreMode,
            allowsLoopbackCapture: settings.webCapture.allowsLoopbackCapture)
    }
}

extension URLValidationError {
    /// A stable, non-PII label for the refusal reason, for diagnostics. Never
    /// includes the rejected URL — only the kind of refusal (and, for an
    /// unsupported scheme, the scheme token, which is a fixed identifier).
    var diagnosticReason: String {
        switch self {
        case .malformed: "malformed-url"
        case .unsupportedScheme(let scheme): "unsupported-scheme-\(scheme)"
        case .privateLocalhost: "private-localhost"
        }
    }
}

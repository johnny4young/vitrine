import Foundation

extension RenderCoordinator {
    /// The production coordinator wired with the renderers Vitrine ships: the
    /// `CodeRenderer`, the local `HTMLRenderer`, and the `URLRenderer`.
    ///
    /// HTML renders locally on every build. URL capture stays gated on the network
    /// entitlement (`NetworkCapability`): a `.url` render is inert — it throws
    /// `urlCaptureDisabled` before touching WebKit — on a build that lacks the
    /// entitlement (the App Store build), and runs on a build that carries it (the
    /// direct-download DMG). The Web Snapshot surface configures its own `URLRenderer`
    /// from the user's viewport/wait settings; this default carries the renderers for
    /// routing and the clipboard path.
    ///
    /// This lives in `WebRendering/` (not next to the `RenderCoordinator` struct)
    /// because it names `HTMLRenderer`/`URLRenderer`, which the CLI target excludes
    /// along with the rest of WebKit. Keeping the wiring here lets the shared
    /// `Renderer.swift` stay platform-neutral.
    static var standard: RenderCoordinator {
        RenderCoordinator(renderers: [CodeRenderer(), HTMLRenderer(), URLRenderer()])
    }
}

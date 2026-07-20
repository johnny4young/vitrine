import Foundation

/// The app's composition root (/§8): the one place the long-lived data stores
/// are constructed and wired together, instead of each owning a scattered
/// `static let shared = X(defaults: AppDefaults.current)`.
///
/// Constructing them here fixes the dependency order in a single, reviewable place — the
/// entitlement and Brand Kit are built first and handed to `AppSettings`, so every store
/// shares one consistent graph rather than each reaching for another's `.shared` at an
/// arbitrary time. The individual `Store.shared` accessors are kept as thin forwarders to
/// this root, so the existing call sites (and the non-view action layer, which cannot read
/// `@Environment`) are unchanged while the construction is centralized. A test — or a
/// preview — can build its own `AppEnvironment(defaults:)` over an isolated suite to get an
/// independent, fully-wired graph.
///
/// Only the **data** stores live here. Window controllers and HUD presenters are UI
/// lifecycle singletons (they manage AppKit window state, not injectable data) and keep
/// their own `.shared`; `HighlightManager` is a stateless engine cache with a private init
/// and stays a leaf singleton.
@MainActor
final class AppEnvironment {
    /// The app-wide graph, built once over the standard defaults. `Store.shared`
    /// forwards here, so this is the single construction site for the whole app.
    static let shared = AppEnvironment()

    let entitlements: Entitlements
    let brandKit: BrandKitStore
    let appSettings: AppSettings
    let recents: RecentsStore
    let customThemes: CustomThemeStore
    let presets: PresetStore

    /// Builds the whole store graph over `defaults` in dependency order: the entitlement
    /// and Brand Kit first, then `AppSettings` (which takes them), then the independent
    /// catalog/recents stores. Nothing here reads a `.shared`, so constructing the root
    /// never re-enters itself.
    init(defaults: UserDefaults = AppDefaults.current) {
        entitlements = Entitlements(provider: Entitlements.defaultProvider())
        brandKit = BrandKitStore(defaults: defaults)
        appSettings = AppSettings(
            defaults: defaults, brandKit: brandKit, entitlements: entitlements)
        recents = RecentsStore(defaults: defaults)
        customThemes = CustomThemeStore(defaults: defaults)
        presets = PresetStore(defaults: defaults)
    }
}

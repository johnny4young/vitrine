import Foundation

/// Catalog of themes (CS-006/031). Built-in themes resolve to a bundled Highlight.js
/// stylesheet; custom themes (CS-031) come from `CustomThemeStore` and carry their
/// own palette. Highlightr / `HighlightManager` are configured per theme at render
/// time.
enum ThemeManager {
    /// The built-in themes only, in display order. Used where the immutable, always
    /// present set is wanted (menus that do not show user themes, the coverage matrix).
    static let builtIns: [Theme] = Theme.builtIns

    /// Backwards-compatible alias for the built-in catalog.
    static var available: [Theme] { Theme.builtIns }

    /// Every theme offered in the UI, built-ins first then the user's custom themes,
    /// resolved through the shared `CustomThemeStore` (CS-031).
    @MainActor
    static var all: [Theme] { CustomThemeStore.shared.allThemes }

    /// Resolves a theme id to a `Theme`, preferring a custom theme and falling back
    /// to the built-in lookup (CS-031). Off-main-actor call sites that only ever deal
    /// in built-ins (`Capture`, `StyleSnapshot`) continue to use the `nonisolated`
    /// `Theme.theme(withID:)` directly.
    @MainActor
    static func theme(withID id: String) -> Theme {
        CustomThemeStore.shared.theme(withID: id)
    }
}

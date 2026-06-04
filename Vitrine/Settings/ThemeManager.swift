import Foundation

/// Catalog of bundled themes (CS-006). Highlightr is configured with each
/// theme's `hlJsTheme` name at render time (see `HighlightManager`).
enum ThemeManager {
    /// Themes offered in the UI, in display order.
    static let available: [Theme] = Theme.all

    static func theme(withID id: String) -> Theme {
        Theme.theme(withID: id)
    }
}

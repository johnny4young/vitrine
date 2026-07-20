import KeyboardShortcuts

/// Global keyboard shortcuts, persisted by the KeyboardShortcuts package.
///
/// With the module's default actor isolation set to `MainActor`, these statics are
/// main-actor isolated and need no `Sendable`/`nonisolated(unsafe)` annotations.
extension KeyboardShortcuts.Name {
    /// ⌘⇧S — run a quick capture from the clipboard.
    static let quickCapture = Self(
        "quickCapture", default: .init(.s, modifiers: [.command, .shift]))

    /// Open the editor window.
    static let openEditor = Self("openEditor")
}

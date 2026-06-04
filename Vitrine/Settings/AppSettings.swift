import SwiftUI

/// The app's persisted settings and the live `SnapshotConfig` shared across the
/// UI, the quick-capture path, and the exporter (CS-010).
///
/// A single shared instance keeps the SwiftUI scenes and the AppKit-driven
/// preferences window in sync. The module defaults to `@MainActor` isolation.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// The current snapshot configuration (theme, font, padding, …).
    @Published var config: SnapshotConfig { didSet { persist() } }

    /// Whether quick mode copies the rendered image to the clipboard automatically.
    @Published var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) } }

    /// Export resolution multiplier: 1, 2 (retina), or 3.
    @Published var exportScale: Int {
        didSet { defaults.set(exportScale, forKey: Keys.exportScale) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let themeID = "themeID"
        static let autoCopy = "autoCopy"
        static let exportScale = "exportScale"
    }

    private init() {
        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        exportScale = defaults.object(forKey: Keys.exportScale) as? Int ?? 2

        var initial = SnapshotConfig()
        if let id = defaults.string(forKey: Keys.themeID) {
            initial.theme = Theme.theme(withID: id)
        }
        config = initial
    }

    /// Sets the default theme (used by the "Theme" submenu).
    func selectTheme(_ theme: Theme) {
        config.theme = theme
    }

    private func persist() {
        defaults.set(config.theme.id, forKey: Keys.themeID)
    }
}

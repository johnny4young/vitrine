import Foundation
import Observation

/// App-wide clipboard and save behavior (Output). Unlike ``ExportSettings`` it is never
/// seeded into an editor session: the app-wide `AppSettings` creates the one instance and
/// every session references it, so a window always reads the live preference.
///
/// Persists under the same `SettingsCodec.Keys` these values have always used.
@Observable
final class OutputBehavior {
    private typealias Keys = SettingsCodec.Keys

    /// Copy the rendered image to the clipboard automatically (quick mode).
    var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) } }

    /// Also save the rendered image to a file.
    var alsoSaveToFile: Bool {
        didSet { defaults.set(alsoSaveToFile, forKey: Keys.alsoSaveToFile) }
    }

    /// Close the editor window after a successful "Copy image". On by default: once the
    /// image is on the clipboard the window's job is done.
    var closeAfterCopy: Bool {
        didSet { defaults.set(closeAfterCopy, forKey: Keys.closeAfterCopy) }
    }

    /// Ask cooperating clipboard managers to conceal exports.
    var concealClipboard: Bool {
        didSet { defaults.set(concealClipboard, forKey: Keys.concealClipboard) }
    }

    private let defaults: UserDefaults

    /// A missing or garbage value falls back to the documented default.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        alsoSaveToFile = defaults.object(forKey: Keys.alsoSaveToFile) as? Bool ?? false
        closeAfterCopy = defaults.object(forKey: Keys.closeAfterCopy) as? Bool ?? true
        concealClipboard = defaults.object(forKey: Keys.concealClipboard) as? Bool ?? false
    }

    /// Resets the live state; `AppSettings.resetToDefaults()` clears the persisted keys.
    func resetToDefaults() {
        autoCopy = true
        alsoSaveToFile = false
        closeAfterCopy = true
        concealClipboard = false
    }
}

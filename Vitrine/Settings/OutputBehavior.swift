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

    /// Float a draggable preview of each copied image near the screen corner.
    var showsCopyPreview: Bool {
        didSet { defaults.set(showsCopyPreview, forKey: Keys.showsCopyPreview) }
    }

    /// Ask cooperating clipboard managers to conceal exports.
    var concealClipboard: Bool {
        didSet { defaults.set(concealClipboard, forKey: Keys.concealClipboard) }
    }

    /// Save the editable project inside PNG files. Off by default: it carries the source.
    var embedsEditableProject: Bool {
        didSet { defaults.set(embedsEditableProject, forKey: Keys.embedEditableProject) }
    }

    /// Ask before a dropped PNG with a project opens as code; off beautifies it as an image.
    var asksToOpenEmbeddedProjects: Bool {
        didSet {
            defaults.set(asksToOpenEmbeddedProjects, forKey: Keys.askToOpenEmbeddedProjects)
        }
    }

    private let defaults: UserDefaults

    /// A missing or garbage value falls back to the documented default.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        alsoSaveToFile = defaults.object(forKey: Keys.alsoSaveToFile) as? Bool ?? false
        closeAfterCopy = defaults.object(forKey: Keys.closeAfterCopy) as? Bool ?? true
        showsCopyPreview = defaults.object(forKey: Keys.showsCopyPreview) as? Bool ?? true
        concealClipboard = defaults.object(forKey: Keys.concealClipboard) as? Bool ?? false
        embedsEditableProject =
            defaults.object(forKey: Keys.embedEditableProject) as? Bool ?? false
        asksToOpenEmbeddedProjects =
            defaults.object(forKey: Keys.askToOpenEmbeddedProjects) as? Bool ?? true
    }

    /// Resets the live state; `AppSettings.resetToDefaults()` clears the persisted keys.
    func resetToDefaults() {
        autoCopy = true
        alsoSaveToFile = false
        closeAfterCopy = true
        showsCopyPreview = true
        concealClipboard = false
        embedsEditableProject = false
        asksToOpenEmbeddedProjects = true
    }
}

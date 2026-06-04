import SwiftUI

/// The app's persisted settings and the live `SnapshotConfig`, shared across the
/// UI, the quick-capture path, and the exporter (CS-010). `UserDefaults` is
/// injectable so persistence can be unit-tested.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// The current snapshot configuration (theme, font, padding, …).
    @Published var config: SnapshotConfig { didSet { persistStyle() } }

    /// Copy the rendered image to the clipboard automatically (quick mode).
    @Published var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) } }

    /// Also save the rendered image to a file (CS-010 · Output).
    @Published var alsoSaveToFile: Bool {
        didSet { defaults.set(alsoSaveToFile, forKey: Keys.alsoSaveToFile) }
    }

    /// Export resolution multiplier: 1, 2 (retina), or 3.
    @Published var exportScale: Int {
        didSet { defaults.set(exportScale, forKey: Keys.exportScale) }
    }

    /// Exported image format (CS-010 · Output).
    @Published var exportFormat: ExportFormat {
        didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }

    /// What the global hotkey does (CS-002).
    @Published var hotkeyAction: HotkeyAction {
        didSet { defaults.set(hotkeyAction.rawValue, forKey: Keys.hotkeyAction) }
    }

    /// Treat clipboard URLs as a screenshot target (CS-010 · Input). Phase B.
    @Published var treatURLsAsScreenshot: Bool {
        didSet { defaults.set(treatURLsAsScreenshot, forKey: Keys.treatURLs) }
    }

    /// Recently used languages, most-recent first (CS-004).
    @Published private(set) var recentLanguages: [Language] {
        didSet { defaults.set(recentLanguages.map(\.rawValue), forKey: Keys.recentLanguages) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let themeID = "themeID"
        static let languageID = "languageID"
        static let fontSize = "fontSize"
        static let padding = "padding"
        static let cornerRadius = "cornerRadius"
        static let showChrome = "showChrome"
        static let showShadow = "showShadow"
        static let gradientPreset = "gradientPreset"
        static let autoCopy = "autoCopy"
        static let alsoSaveToFile = "alsoSaveToFile"
        static let exportScale = "exportScale"
        static let exportFormat = "exportFormat"
        static let hotkeyAction = "hotkeyAction"
        static let treatURLs = "treatURLsAsScreenshot"
        static let recentLanguages = "recentLanguages"
        static let fontName = "fontName"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        alsoSaveToFile = defaults.bool(forKey: Keys.alsoSaveToFile)
        exportScale = defaults.object(forKey: Keys.exportScale) as? Int ?? 2
        exportFormat =
            ExportFormat(rawValue: defaults.string(forKey: Keys.exportFormat) ?? "") ?? .png
        hotkeyAction =
            HotkeyAction(rawValue: defaults.string(forKey: Keys.hotkeyAction) ?? "")
            ?? .quickCapture
        treatURLsAsScreenshot = defaults.bool(forKey: Keys.treatURLs)
        recentLanguages =
            (defaults.array(forKey: Keys.recentLanguages) as? [String] ?? [])
            .compactMap(Language.init(rawValue:))

        var initial = SnapshotConfig()
        if let id = defaults.string(forKey: Keys.themeID) {
            initial.theme = Theme.theme(withID: id)
        }
        if let id = defaults.string(forKey: Keys.languageID), let language = Language(rawValue: id)
        {
            initial.language = language
        }
        if let value = defaults.object(forKey: Keys.fontSize) as? Double {
            initial.fontSize = value
        }
        if let value = defaults.string(forKey: Keys.fontName) { initial.fontName = value }
        if let value = defaults.object(forKey: Keys.padding) as? Double { initial.padding = value }
        if let value = defaults.object(forKey: Keys.cornerRadius) as? Double {
            initial.cornerRadius = value
        }
        if defaults.object(forKey: Keys.showChrome) != nil {
            initial.showChrome = defaults.bool(forKey: Keys.showChrome)
        }
        if defaults.object(forKey: Keys.showShadow) != nil {
            initial.showShadow = defaults.bool(forKey: Keys.showShadow)
        }
        if let raw = defaults.string(forKey: Keys.gradientPreset),
            let preset = GradientPreset(rawValue: raw)
        {
            initial.background = .gradient(preset)
        }
        config = initial
    }

    /// Sets the default theme (used by the "Theme" submenu).
    func selectTheme(_ theme: Theme) { config.theme = theme }

    /// Records a language as recently used (MRU, capped at 6).
    func noteLanguageUsed(_ language: Language) {
        var list = recentLanguages.filter { $0 != language }
        list.insert(language, at: 0)
        recentLanguages = Array(list.prefix(6))
    }

    /// Languages ordered recent-first, then the rest of the catalog (CS-004).
    var orderedLanguages: [Language] {
        recentLanguages + Language.allCases.filter { !recentLanguages.contains($0) }
    }

    private func persistStyle() {
        defaults.set(config.theme.id, forKey: Keys.themeID)
        defaults.set(config.language.rawValue, forKey: Keys.languageID)
        defaults.set(config.fontName, forKey: Keys.fontName)
        defaults.set(config.fontSize, forKey: Keys.fontSize)
        defaults.set(config.padding, forKey: Keys.padding)
        defaults.set(config.cornerRadius, forKey: Keys.cornerRadius)
        defaults.set(config.showChrome, forKey: Keys.showChrome)
        defaults.set(config.showShadow, forKey: Keys.showShadow)
        if case .gradient(let preset) = config.background {
            defaults.set(preset.rawValue, forKey: Keys.gradientPreset)
        }
    }
}

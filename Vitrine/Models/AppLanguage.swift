import Foundation

/// The app's UI language, chosen in Settings and persisted across launches (CS-047).
///
/// macOS resolves an app's localization at launch from `AppleLanguages` in the app's
/// preferences domain, so a change takes effect the next time Vitrine opens (the Settings
/// picker says so). `.system` removes the per-app override and follows the system language
/// order; `.english` / `.spanish` pin one of the shipped locales.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case spanish

    var id: String { rawValue }

    /// The locale code written into `AppleLanguages`, or `nil` to follow the system.
    var localeCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .spanish: "es"
        }
    }

    /// The picker label. `.system` is localized through the String Catalog so it reads
    /// in the user's current language; the concrete languages use their own *autonym*
    /// (their name in their own language), so a speaker always recognizes their
    /// language regardless of the current UI language — the convention System Settings
    /// uses (CS-047).
    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .english, .spanish: autonym
        }
    }

    /// The language's own name (its autonym), e.g. "English" / "Español". `.system` is
    /// handled in `displayName` and never reaches here, so a missing `localeCode`
    /// falls back defensively to the localized "System".
    private var autonym: String {
        guard let code = localeCode else { return String(localized: "System") }
        let name = Locale(identifier: code).localizedString(forLanguageCode: code) ?? code
        // Some autonyms come back lowercased (e.g. "español"); present them capitalized
        // so the picker reads "Español", matching System Settings.
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Resolves a persisted raw value to a case, defaulting to `.system` for a missing or
    /// unrecognized value (CS-050 defensive read).
    static func resolve(_ raw: String?) -> AppLanguage {
        raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}

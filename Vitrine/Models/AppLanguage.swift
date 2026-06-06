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

    /// The picker label, localized through the String Catalog so the names read in the
    /// user's current language (CS-047).
    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .english: String(localized: "English")
        case .spanish: String(localized: "Spanish")
        }
    }

    /// Resolves a persisted raw value to a case, defaulting to `.system` for a missing or
    /// unrecognized value (CS-050 defensive read).
    static func resolve(_ raw: String?) -> AppLanguage {
        raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}

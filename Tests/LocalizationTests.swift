import Foundation
import Testing

@testable import Vitrine

/// Localization and internationalization coverage (CS-047).
///
/// These tests pin the three things the ticket's Acceptance and Tests sections
/// call for that can be verified headlessly (the pseudolocale UI smoke lives in
/// `UITests/VitrineUITests.swift`):
///
/// 1. **A real second locale exists end to end.** The app bundle carries both an
///    `en` (development language) and an `es` localization produced by the String
///    Catalog, and representative user-facing strings actually resolve to their
///    Spanish values — proving strings flow through the catalog, not baked-in
///    English.
/// 2. **A guard that flags new non-localized user-facing strings.** Every
///    `String(localized:)` key used in the shipping sources must be present in the
///    catalog and translated for `es`; a verbatim-bypass scan flags patterns (raw
///    `NSAttributedString(string:)`, `Text("…" + "…")`) that would smuggle an
///    untranslated string past the catalog in a localizable view.
/// 3. **Locale-aware number and date formatting.** Counts use the catalog's plural
///    variants and locale-grouped numerals; relative dates are locale-aware.
@Suite("Localization (CS-047)")
struct LocalizationTests {

    // MARK: - Bundle locations

    /// The repository root, anchored to this file (`<repo>/Tests/…`), so the
    /// source-scanning guard reads the committed sources rather than the built
    /// bundle. Mirrors `GoldenPaths`, which reads fixtures the same way.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    /// The shipping app's `Vitrine/` source directory.
    private static var sourceRoot: URL {
        repositoryRoot.appendingPathComponent("Vitrine", isDirectory: true)
    }

    /// The String Catalog file itself, for structural assertions.
    private static var catalogURL: URL {
        sourceRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localizable.xcstrings")
    }

    /// The per-language `.lproj` bundle compiled into the test host app, or `nil`
    /// when that localization is absent. The unit-test host is the built
    /// `Vitrine.app` (`TEST_HOST`/`BUNDLE_LOADER`), so `Bundle.main` is the app
    /// bundle and its `<lang>.lproj` folders are the catalog's compiled output.
    private func bundle(for language: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    // MARK: - A real second locale exists end to end

    @Test func bundleShipsEnglishAndSpanishLocalizations() throws {
        let localizations = Set(Bundle.main.localizations)
        #expect(
            localizations.contains("en"),
            "The app must ship the English development localization.")
        #expect(
            localizations.contains("es"),
            "The app must ship a real second locale (Spanish) to prove the pipeline (CS-047).")

        // The compiled `.lproj` folders back those advertised localizations.
        #expect(bundle(for: "en") != nil, "Missing compiled en.lproj")
        #expect(bundle(for: "es") != nil, "Missing compiled es.lproj")
    }

    @Test func developmentLanguageIsEnglish() {
        // English is the development language, so unknown keys fall back to English.
        #expect(Bundle.main.developmentLocalization == "en")
    }

    @Test func representativeStringsResolveToSpanish() throws {
        let spanish = try #require(bundle(for: "es"), "es.lproj is required for CS-047")

        // A spread across menus, the editor, feedback, settings, and help — each
        // must come back translated, not as the English key echoed back.
        let expected: [String: String] = [
            "Copy Image": "Copiar imagen",
            "Open Editor": "Abrir editor",
            "About Vitrine": "Acerca de Vitrine",
            "Quit Vitrine": "Salir de Vitrine",
            "Clipboard is empty — copy some code first":
                "El portapapeles está vacío; copia algo de código primero",
            "Nothing to show yet": "Aún no hay nada que mostrar",
            "help.topic.editor.title": "El editor",
            // The AppKit main-menu chrome: NSMenu/NSMenuItem titles are plain
            // strings that AppKit never auto-localizes, so they must resolve
            // through the catalog like any other copy (CS-047).
            "Edit": "Edición",
            "Services": "Servicios",
            "Bring All to Front": "Traer todo al frente",
        ]
        for (key, value) in expected {
            let resolved = spanish.localizedString(forKey: key, value: "\u{0}MISSING", table: nil)
            #expect(
                resolved == value,
                "Spanish localization for \"\(key)\" should be \"\(value)\", got \"\(resolved)\"")
        }
    }

    @Test func developmentLanguageStringsResolveForOpaqueKeys() throws {
        // Keys that are stable identifiers (not English prose) must carry an English
        // value in the catalog, or they would render as the raw key for an English
        // user.
        let english = try #require(bundle(for: "en"))
        let opaqueKeys = [
            "help.topic.hotkey.title", "help.topic.privacy.body", "welcome.privacy.badge",
        ]
        for key in opaqueKeys {
            let resolved = english.localizedString(forKey: key, value: "\u{0}MISSING", table: nil)
            #expect(
                resolved != "\u{0}MISSING" && resolved != key,
                "Opaque key \"\(key)\" must have an English value in the catalog.")
        }
    }

    // MARK: - Catalog structure

    /// The decoded String Catalog, so structural rules can be asserted directly on
    /// the committed source of truth.
    private func decodedCatalog() throws -> Catalog {
        let data = try Data(contentsOf: Self.catalogURL)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test func catalogSourceLanguageIsEnglish() throws {
        let catalog = try decodedCatalog()
        #expect(catalog.sourceLanguage == "en")
    }

    @Test func catalogPluralEntriesCoverSingularAndPlural() throws {
        let catalog = try decodedCatalog()
        // The count-aware strings must carry both `one` and `other` variants in each
        // locale they translate, or a non-English plural would silently fall back.
        let pluralKeys = ["Added %lld presets", "Added %lld themes"]
        for key in pluralKeys {
            let entry = try #require(catalog.strings[key], "Missing plural key \"\(key)\"")
            for (language, localization) in entry.localizations {
                let variations = try #require(
                    localization.variations?.plural,
                    "\"\(key)\" (\(language)) must use plural variations")
                #expect(variations["one"] != nil, "\"\(key)\" (\(language)) is missing `one`")
                #expect(variations["other"] != nil, "\"\(key)\" (\(language)) is missing `other`")
            }
        }
    }

    // MARK: - Guard: new non-localized user-facing strings

    /// Every `String(localized: "literal")` key in the shipping sources must exist
    /// in the catalog and be translated for Spanish. This is the "flag new
    /// non-localized user-facing strings" check: adding a `String(localized:)` call
    /// without adding its key (or its Spanish translation) fails here.
    ///
    /// Interpolated keys (e.g. `String(localized: "Added \(count) presets")`) are
    /// covered by the dedicated plural/format tests, so this scan skips literals
    /// that contain a Swift interpolation.
    @Test func everyLocalizedKeyInSourceIsTranslated() throws {
        let catalog = try decodedCatalog()
        let keys = try Self.localizedLiteralKeys()
        #expect(!keys.isEmpty, "Expected to find String(localized:) keys in the sources")

        for key in keys {
            // Membership in the catalog, plus an explicit Spanish localization, is the
            // precise signal — not value inequality, since some words are identical
            // across languages (e.g. "General"). A `String(localized:)` added without
            // a catalog entry, or without an `es` translation, fails here.
            guard let entry = catalog.strings[key] else {
                Issue.record(
                    "String(localized: \"\(key)\") is used in code but missing from the catalog.")
                continue
            }
            #expect(
                entry.localizations["es"]?.isTranslated == true,
                "String(localized: \"\(key)\") has no Spanish translation in the catalog (CS-047).")
        }
    }

    /// Localizable views must not smuggle user-facing copy past the catalog with a
    /// verbatim initializer. Flags `Text("…" + "…")` (the verbatim `String`
    /// overload) and raw `NSAttributedString(string: "literal")` in the surfaces
    /// that present user copy.
    @Test func localizableViewsDoNotUseVerbatimStringConstruction() throws {
        let offenders = try Self.verbatimStringOffenders()
        #expect(
            offenders.isEmpty,
            """
            Found user-facing strings built verbatim (bypassing the String Catalog, CS-047):
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// Every implicit-`LocalizedStringKey` literal in the shipping SwiftUI views —
    /// `Text("…")`, `Button("…")`, `Toggle("…", …)`, `Picker`, `Section`, `Label`,
    /// `TextField`, `LabeledContent`, `Link`, `Menu`, `ColorPicker`, the
    /// `KeyboardShortcuts.Recorder`, a `prompt: Text("…")`, and the
    /// `.help`/`.accessibilityLabel`/`.navigationTitle`/`.alert`/`.confirmationDialog`
    /// modifiers — must exist in the catalog and carry a Spanish translation.
    ///
    /// This is the gap the older `String(localized:)`-only guard left open: a
    /// SwiftUI literal compiles to a `LocalizedStringKey` and renders English under
    /// `es` if it never reaches the catalog. Adding such a literal without a catalog
    /// entry (or its `es` value) now fails here. Literals shown verbatim
    /// (`Text(verbatim:)`) deliberately bypass localization and are not matched.
    @Test func everyLocalizedStringKeyLiteralInViewsIsTranslated() throws {
        let catalog = try decodedCatalog()
        let keys = try Self.localizedStringKeyLiterals()
        #expect(!keys.isEmpty, "Expected to find LocalizedStringKey literals in the views")

        for key in keys {
            guard let entry = catalog.strings[key] else {
                Issue.record(
                    """
                    A SwiftUI LocalizedStringKey literal "\(key)" is used in a view but is \
                    missing from the String Catalog. Add it (with an `es` translation), or use \
                    `Text(verbatim:)` if it is a non-localizable symbol/brand string (CS-047).
                    """)
                continue
            }
            #expect(
                entry.localizations["es"]?.isTranslated == true,
                "LocalizedStringKey \"\(key)\" has no Spanish translation in the catalog (CS-047).")
        }
    }

    // MARK: - Locale-aware number and date formatting

    @Test func countMessagesUseLocaleGroupedNumeralsAndPlurals() throws {
        let spanish = try #require(bundle(for: "es"))
        let english = try #require(bundle(for: "en"))

        // Singular vs. plural selection comes from the catalog's `.stringsdict`.
        let oneEN = String(
            format: english.localizedString(forKey: "Added %lld presets", value: "", table: nil),
            locale: Locale(identifier: "en"), 1)
        let manyEN = String(
            format: english.localizedString(forKey: "Added %lld presets", value: "", table: nil),
            locale: Locale(identifier: "en"), 5)
        #expect(oneEN == "Added 1 preset.")
        #expect(manyEN == "Added 5 presets.")

        let oneES = String(
            format: spanish.localizedString(forKey: "Added %lld presets", value: "", table: nil),
            locale: Locale(identifier: "es"), 1)
        let manyES = String(
            format: spanish.localizedString(forKey: "Added %lld presets", value: "", table: nil),
            locale: Locale(identifier: "es"), 3)
        #expect(oneES == "Se agregó 1 ajuste preestablecido.")
        #expect(manyES == "Se agregaron 3 ajustes preestablecidos.")
    }

    @Test func integerFormattingIsLocaleAware() {
        // A large count groups digits per the user's locale: en uses "," and es-ES
        // uses ".". This is the locale-aware numeral formatting CS-047 requires for
        // any number Vitrine shows.
        let value = 1_234_567
        let enGrouped = value.formatted(.number.locale(Locale(identifier: "en_US")))
        let esGrouped = value.formatted(.number.locale(Locale(identifier: "es_ES")))
        #expect(enGrouped.contains(","))
        #expect(esGrouped.contains("."))
        #expect(enGrouped != esGrouped, "Grouping separators must differ across locales")
    }

    @Test func relativeDateFormattingIsLocaleAware() {
        // Recents timestamps are rendered with a locale-aware relative formatter
        // (RecentsGalleryView), so the same instant reads differently per locale.
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let past = Date().addingTimeInterval(-3600)

        formatter.locale = Locale(identifier: "en")
        let english = formatter.localizedString(for: past, relativeTo: Date())
        formatter.locale = Locale(identifier: "es")
        let spanish = formatter.localizedString(for: past, relativeTo: Date())

        #expect(!english.isEmpty)
        #expect(!spanish.isEmpty)
        #expect(
            english.lowercased() != spanish.lowercased(),
            "A relative date should localize (en \"\(english)\" vs es \"\(spanish)\")")
    }

    @Test func captureFeedbackMessagesAreLocalizedNotEmpty() {
        // The capture-feedback policy layer (Notifier) routes its messages through
        // the catalog; under the test host's English locale they resolve to real
        // copy, never an empty or key-like string.
        let outcomes: [QuickCapture.Outcome] = [
            .copied, .empty, .url("https://example.com"), .deferredToEditor(blocks: 3),
        ]
        for outcome in outcomes {
            let message = Notifier.feedback(for: outcome).message
            #expect(!message.isEmpty)
        }
        #expect(Notifier.successMessage(copied: true, saved: true).contains("clipboard"))
    }

    // MARK: - Source scanning helpers

    /// All `String(localized: "literal")` keys used across the shipping sources,
    /// skipping literals that contain a Swift interpolation (`\(`).
    private static func localizedLiteralKeys() throws -> Set<String> {
        // Matches `String(localized:` optionally across whitespace/newlines, then a
        // double-quoted literal with no interpolation or embedded quote.
        let pattern = #"String\(\s*localized:\s*"([^"\\]*)""#
        let regex = try NSRegularExpression(pattern: pattern)
        var keys: Set<String> = []
        for url in try swiftSources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                let key = String(text[keyRange])
                // Skip interpolated keys; those map to %-specifier catalog keys and
                // are validated by the plural/format tests.
                if key.contains("\\(") { continue }
                if key.isEmpty { continue }
                keys.insert(key)
            }
        }
        return keys
    }

    /// Every implicit-`LocalizedStringKey` literal across the shipping SwiftUI
    /// views, collected by matching the view/modifier initializers whose first
    /// `String` argument is a `LocalizedStringKey`.
    ///
    /// The match is whitespace/newline tolerant so multi-line calls (a `ColorPicker`
    /// or `.alert` whose literal sits on the next line) are not missed — the exact
    /// shape that let these literals slip past a naive line-by-line scan. Literals
    /// with a Swift interpolation (`\(`) are skipped: those compile to
    /// `%`-specifier catalog keys covered by the plural/format tests. The
    /// `verbatim:` overloads are not matched because the literal does not follow the
    /// opening paren directly, so genuinely non-localizable symbol/brand strings
    /// (e.g. `Text(verbatim: "© …")`) are correctly excluded.
    private static func localizedStringKeyLiterals() throws -> Set<String> {
        let literal = #""([^"\\]*)""#
        // Initializers whose first argument is a `LocalizedStringKey`.
        let initializers = [
            "Text", "Button", "Toggle", "Picker", "Section", "Label", "TextField",
            "LabeledContent", "Link", "Menu", "ColorPicker",
        ]
        // View modifiers whose (first) argument is a `LocalizedStringKey`.
        let modifiers = [
            "help", "accessibilityLabel", "navigationTitle", "alert", "confirmationDialog",
        ]
        var patterns = initializers.map { #"\b\#($0)\(\s*\#(literal)"# }
        patterns += modifiers.map { #"\.\#($0)\(\s*\#(literal)"# }
        // `KeyboardShortcuts.Recorder("label", …)` and a `prompt: Text("…")`.
        patterns.append(#"\bRecorder\(\s*\#(literal)"#)
        patterns.append(#"prompt:\s*Text\(\s*\#(literal)"#)

        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        var keys: Set<String> = []
        for url in try swiftSources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for regex in regexes {
                for match in regex.matches(in: text, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                    let key = String(text[keyRange])
                    if key.isEmpty { continue }
                    if key.contains("\\(") { continue }
                    keys.insert(key)
                }
            }
        }
        return keys
    }

    /// Source lines that build user-facing strings verbatim in localizable surfaces,
    /// reported as `path:line  snippet` for an actionable failure message.
    private static func verbatimStringOffenders() throws -> [String] {
        // `Text("…" + …)` — the verbatim String initializer of Text — and a raw
        // NSAttributedString built from a string *literal*. A localized attributed
        // string is built from `String(localized:)` first, so only a bare literal
        // trips this.
        let verbatimText = try NSRegularExpression(pattern: #"\bText\(\s*"[^"]*"\s*\+"#)
        let rawAttributed = try NSRegularExpression(
            pattern: #"NSAttributedString\(\s*string:\s*"[^"]*""#)

        var offenders: [String] = []
        for url in try swiftSources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if verbatimText.firstMatch(in: line, range: range) != nil
                    || rawAttributed.firstMatch(in: line, range: range) != nil
                {
                    offenders.append(
                        "\(relative):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        return offenders
    }

    /// Every `.swift` file under `Vitrine/`, excluding the previews-only and CLI
    /// trees that do not present localized UI copy.
    private static func swiftSources() throws -> [URL] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: sourceRoot, includingPropertiesForKeys: nil)
        else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            urls.append(url)
        }
        return urls
    }
}

// MARK: - Minimal String Catalog model

/// A minimal decoder for the parts of the `.xcstrings` String Catalog these tests
/// assert on. Only the fields used here are modeled; unknown fields are ignored.
private struct Catalog: Decodable {
    let sourceLanguage: String
    let strings: [String: Entry]

    struct Entry: Decodable {
        var localizations: [String: Localization] = [:]
    }

    struct Localization: Decodable {
        var stringUnit: StringUnit?
        var variations: Variations?

        /// Whether this localization carries a real translation: a `translated`
        /// string unit, or plural variations whose cases are themselves translated.
        var isTranslated: Bool {
            if let stringUnit { return stringUnit.state == "translated" }
            if let plural = variations?.plural, !plural.isEmpty {
                return plural.values.allSatisfy { $0.stringUnit.state == "translated" }
            }
            return false
        }
    }

    struct StringUnit: Decodable {
        var state: String
        var value: String
    }

    struct Variations: Decodable {
        var plural: [String: PluralCase]?
    }

    struct PluralCase: Decodable {
        var stringUnit: StringUnit
    }
}

// MARK: - App language picker model (CS-047)

/// The Settings language picker's model: persisted-value resolution and the
/// autonym labels. This is the contract the picker and the relaunch flow rely on,
/// independent of any UI.
@Suite("App language model resolves and labels correctly · CS-047")
struct AppLanguageTests {
    @Test func resolveDefaultsToSystemForMissingOrGarbageValues() {
        // CS-050 defensive read: a missing or hand-edited defaults value must
        // never crash or mis-pin a language — it falls back to following macOS.
        #expect(AppLanguage.resolve(nil) == .system)
        #expect(AppLanguage.resolve("") == .system)
        #expect(AppLanguage.resolve("klingon") == .system)
        #expect(AppLanguage.resolve("English") == .system, "Raw values are case-sensitive")
    }

    @Test func resolveRoundTripsEveryCase() {
        for language in AppLanguage.allCases {
            #expect(AppLanguage.resolve(language.rawValue) == language)
        }
    }

    @Test func localeCodesMatchTheShippedLocalizations() {
        // The codes written into AppleLanguages must be exactly the locales the
        // bundle ships (en/es), and `.system` must write none at all.
        #expect(AppLanguage.system.localeCode == nil)
        #expect(AppLanguage.english.localeCode == "en")
        #expect(AppLanguage.spanish.localeCode == "es")
    }

    @Test func concreteLanguagesDisplayTheirCapitalizedAutonym() {
        // System Settings convention: a language is always recognizable to its own
        // speakers. Locale returns "español" lowercased; the picker must show
        // "Español".
        #expect(AppLanguage.english.displayName == "English")
        #expect(AppLanguage.spanish.displayName == "Español")
    }
}

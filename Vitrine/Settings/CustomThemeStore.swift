import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Owns the user's custom themes and brokers every custom-theme operation: import
/// from a documented file schema, export, rename, delete, and resolve a theme id to
/// a `Theme` for the rest of the app (CS-031).
///
/// ## Design
///
/// - **Built-ins are immutable.** `Theme.builtIns` are the always-present catalog;
///   a custom theme can never use a built-in's id (the store re-keys or refuses one
///   that would collide), so importing or hand-editing a file can never overwrite or
///   shadow a built-in (CS-031 "built-in themes remain immutable").
/// - **Only user themes persist.** They are stored as one JSON blob under a single
///   `UserDefaults` key, mirroring `PresetStore`. Reads are defensive: a missing or
///   corrupt blob yields an empty user list rather than trapping, so a hand-edited
///   store can never crash the app (CS-050 spirit). Each stored theme is re-validated
///   on load, so a value that was somehow corrupted to a bad color is dropped.
/// - **`UserDefaults` is injectable** so the whole store is unit-testable without
///   touching the real app container, exactly like `PresetStore`.
///
/// This store is the app's resolver for *all* theme ids: `theme(withID:)` returns a
/// matching custom theme, falling back to the built-in lookup for a built-in or
/// unknown id. `AppSettings` routes its theme reads through the shared store so a
/// persisted custom theme survives relaunch.
@Observable
final class CustomThemeStore {
    /// The shared store backed by the app's resolved defaults.
    static let shared = CustomThemeStore(defaults: AppDefaults.current)

    /// The user's custom themes, most-recently-added last. Persisted on change.
    private(set) var customThemes: [Theme] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    /// The single `UserDefaults` key holding the JSON-encoded user themes.
    static let storageKey = "userCustomThemes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.customThemes = Self.readCustomThemes(from: defaults)
    }

    /// Re-reads the custom themes from the backing store. Used after a global "Reset
    /// all settings" (which clears the persisted blob through `AppSettings`) so this
    /// store's in-memory copy reflects the cleared state without re-persisting an
    /// empty list redundantly.
    func reload() {
        let reloaded = Self.readCustomThemes(from: defaults)
        if reloaded != customThemes { customThemes = reloaded }
    }

    // MARK: - Catalog

    /// The full catalog shown in the UI: built-ins first, then the user's themes.
    /// Built-ins lead so the curated set is the obvious starting point.
    var allThemes: [Theme] { Theme.builtIns + customThemes }

    /// Resolves a theme id across custom and built-in themes, falling back to One
    /// Dark for an unknown id. A custom theme wins only on a non-built-in id, so a
    /// custom theme can never resolve in place of a built-in.
    func theme(withID id: String) -> Theme {
        if !Theme.builtInIDs.contains(id),
            let custom = customThemes.first(where: { $0.id == id })
        {
            return custom
        }
        return Theme.theme(withID: id)
    }

    /// Whether `id` names a built-in theme (and is therefore immutable).
    func isBuiltIn(id: String) -> Bool { Theme.builtInIDs.contains(id) }

    // MARK: - Add / rename / delete (user themes only)

    /// Adds a validated custom theme built from `palette` under `name`, returning the
    /// created theme. The name is sanitized and de-duplicated, and a fresh id is
    /// minted so an added theme can never collide with a built-in or an existing
    /// custom theme.
    @discardableResult
    func addTheme(named name: String, palette: ThemePalette) -> Theme {
        let theme = Theme(
            id: Self.freshID(), displayName: uniqueName(name), palette: palette)
        customThemes.append(theme)
        Log.settings.info("Added a custom theme")
        return theme
    }

    /// Renames a custom theme. A built-in is immutable, so a rename targeting one is
    /// ignored. Returns whether a rename happened.
    @discardableResult
    func rename(id: String, to newName: String) -> Bool {
        guard let index = customThemes.firstIndex(where: { $0.id == id }) else { return false }
        let renamed = Theme(
            id: customThemes[index].id,
            displayName: uniqueName(newName, excluding: id),
            palette: customThemes[index].palette ?? Self.fallbackPalette)
        customThemes[index] = renamed
        return true
    }

    /// Deletes a custom theme by id. Built-ins cannot be deleted, so an id that is
    /// not a custom theme is a no-op. Returns whether a delete happened.
    @discardableResult
    func delete(id: String) -> Bool {
        let before = customThemes.count
        customThemes.removeAll { $0.id == id }
        return customThemes.count != before
    }

    // MARK: - Import / export

    /// The exportable document for the user's custom themes (built-ins are not
    /// exported; they ship with every install).
    func exportDocument() -> CustomThemeDocument {
        CustomThemeDocument(themes: customThemes)
    }

    /// Pretty-printed JSON for the user's custom themes, suitable for writing to a file.
    func exportJSONData() throws -> Data {
        try exportDocument().jsonData()
    }

    /// Imports themes from theme-file `data`, validating the envelope and every
    /// palette, then adding the contained themes as new custom themes (CS-031).
    ///
    /// Imported themes are re-keyed with fresh ids so importing the same file twice,
    /// or a file that happens to reuse an id, never overwrites an existing theme or
    /// collides with a built-in id — an import only ever *adds*. Throws a specific
    /// `CustomThemeDocument.ImportError` (with user-facing copy) on an invalid file or
    /// a bad/missing color; the live state is left untouched on failure.
    ///
    /// - Returns: the themes that were added.
    @discardableResult
    func importThemes(from data: Data) throws -> [Theme] {
        let incoming = try CustomThemeDocument.themes(from: data)
        let added = incoming.map { theme in
            // Re-key onto a fresh id and de-duplicate the name so the import is
            // purely additive and can never shadow an existing or built-in theme.
            Theme(
                id: Self.freshID(), displayName: uniqueName(theme.displayName),
                palette: theme.palette ?? Self.fallbackPalette)
        }
        customThemes.append(contentsOf: added)
        Log.settings.info("Imported \(added.count, privacy: .public) custom theme(s)")
        return added
    }

    // MARK: - Naming / ids

    /// A name unique across the whole catalog, suffixing " 2", " 3", … on a clash.
    /// `excluding` lets a rename keep its own current name without colliding with
    /// itself. Keeps the picker unambiguous without ever rejecting an import.
    private func uniqueName(_ proposed: String, excluding id: String? = nil) -> String {
        let base = Self.sanitizedName(proposed)
        let taken = Set(
            allThemes.filter { $0.id != id }.map { $0.displayName.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    /// Trims a user-entered name and collapses an empty result to a friendly
    /// default, so a custom theme always has a non-empty, tidy label.
    static func sanitizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Custom Theme" : trimmed
    }

    /// A fresh, collision-proof id for a custom theme. The `custom.` prefix keeps a
    /// custom id visibly distinct from a built-in slug and out of the built-in id set.
    static func freshID() -> String { "custom.\(UUID().uuidString)" }

    /// A neutral dark palette used only as a structural fallback when reconstructing
    /// a theme whose palette is somehow absent (it never is for a stored or imported
    /// theme, which always carry one). Keeps reconstruction total without optionals.
    private static let fallbackPalette = ThemePalette(
        background: HexColor("#1E1E1E")!, foreground: HexColor("#D4D4D4")!)

    // MARK: - Persistence

    /// Reads the persisted custom themes, tolerating any missing or corrupt value
    /// (CS-050 / CS-031 "invalid theme files do not crash"). A garbage blob simply
    /// yields an empty list, leaving the built-ins available. Any theme whose id
    /// collides with a built-in's reserved id is dropped so a hand-edited store
    /// cannot shadow or "overwrite" a built-in.
    private static func readCustomThemes(from defaults: UserDefaults) -> [Theme] {
        guard let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([StoredCustomTheme].self, from: data)
        else { return [] }
        return
            decoded
            .filter { !Theme.builtInIDs.contains($0.id) }
            .map { $0.theme }
    }

    /// Persists the user themes as a JSON array of stored records. An unexpected
    /// encode failure drops the key rather than leaving a stale blob behind,
    /// mirroring `PresetStore`.
    private func persist() {
        let records = customThemes.compactMap(StoredCustomTheme.init)
        guard let data = try? JSONEncoder().encode(records) else {
            defaults.removeObject(forKey: Self.storageKey)
            Log.settings.error("Custom theme encode failed; not persisting")
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Stored / file representations (CS-031)

/// The persisted/on-disk record for one custom theme: a stable id, a display name,
/// and the palette (CS-031).
///
/// `Theme` itself is a SwiftUI-facing value with a non-`Codable` `Source`, so themes
/// are stored and shared through this flat, fully-`Codable` record. Decoding routes
/// through `ThemePalette`'s strict decoder, so a record with a bad or missing color
/// fails to decode and is skipped on load (or rejected on import) — origin and
/// validity are recomputed, never trusted from the file.
struct StoredCustomTheme: Codable, Equatable {
    var id: String
    var name: String
    var palette: ThemePalette

    init(id: String, name: String, palette: ThemePalette) {
        self.id = id
        self.name = name
        self.palette = palette
    }

    /// Captures a custom `theme` for storage, or `nil` for a built-in (which is never
    /// stored — built-ins ship with the app).
    init?(_ theme: Theme) {
        guard let palette = theme.palette else { return nil }
        self.id = theme.id
        self.name = theme.displayName
        self.palette = palette
    }

    /// The reconstructed `Theme`, with its id and name sanitized so a hand-edited
    /// record always yields a usable, addressable theme.
    var theme: Theme {
        let resolvedID = id.isEmpty ? CustomThemeStore.freshID() : id
        return Theme(
            id: resolvedID, displayName: CustomThemeStore.sanitizedName(name), palette: palette)
    }

    private enum CodingKeys: String, CodingKey { case id, name, palette }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        // The palette is required and strictly validated: a record without a valid
        // palette is not a usable theme, so the decode fails and the record is
        // skipped on load / rejected on import.
        palette = try container.decode(ThemePalette.self, forKey: .palette)
    }
}

/// The on-disk JSON envelope for exporting and importing custom themes (CS-031) —
/// the documented file schema.
///
/// Themes are shared as a single self-describing file: a `format` marker, a
/// `schemaVersion`, and the array of themes. Import is **strict** both about the
/// envelope (a wrong format or unsupported version fails fast with a clear error)
/// and within each theme (a missing required color or a bad hex value is rejected
/// with a specific message). This satisfies CS-031 "import from a documented schema"
/// and "bad colors or missing keys fail with clear validation errors", while a
/// totally unrelated JSON file simply fails as "not a theme file" rather than
/// crashing.
struct CustomThemeDocument: Codable, Equatable {
    /// A fixed marker so a Vitrine theme file is recognizable and a random JSON file
    /// (or a different app's export) is rejected before any field is trusted.
    static let formatMarker = "vitrine.custom-themes"
    /// The current theme-file schema version. Bump when the envelope's shape or
    /// meaning changes; older files are migrated or rejected, never misread.
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var themes: [StoredCustomTheme]

    /// Errors surfaced while importing a theme file. Each maps to clear, user-facing
    /// copy at the call site (CS-031 "clear validation errors").
    enum ImportError: Error, Equatable {
        /// The bytes are not valid JSON / not a theme document at all.
        case notAThemeFile
        /// The file is a theme file but from an unsupported (usually newer) schema
        /// this build cannot read.
        case unsupportedSchemaVersion(Int)
        /// A theme had a missing required color or an invalid hex value.
        case invalidPalette(ThemePalette.ValidationError)
        /// The file decoded but contained no usable themes.
        case empty

        /// A short, human-readable explanation for an alert.
        var message: String {
            switch self {
            case .notAThemeFile:
                "This file is not a Vitrine theme file."
            case .unsupportedSchemaVersion(let version):
                "This theme file uses a newer format (version \(version)) this app can't read."
            case .invalidPalette(let error):
                error.message
            case .empty:
                "This theme file does not contain any themes."
            }
        }
    }

    /// Wraps themes for export at the current format and schema version.
    init(themes: [Theme]) {
        self.format = Self.formatMarker
        self.schemaVersion = Self.currentSchemaVersion
        self.themes = themes.compactMap(StoredCustomTheme.init)
    }

    private enum CodingKeys: String, CodingKey { case format, schemaVersion, themes }

    /// Decodes the envelope, tolerating its scalar fields so envelope validation is
    /// explicit in `themes(from:)`. The `themes` array is decoded with the strict
    /// palette validator so a bad color surfaces as a thrown error there.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? container.decode(String.self, forKey: .format)) ?? ""
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0
        themes = try container.decode([StoredCustomTheme].self, forKey: .themes)
    }

    /// Encodes a theme document as pretty, stable JSON (sorted keys) so an exported
    /// file is human-readable and diffable.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Parses and validates theme-file `data`, returning the contained themes or
    /// throwing a specific `ImportError` (CS-031).
    ///
    /// Validation order is deliberate: a bad/missing color (surfaced by the palette
    /// decoder) → malformed JSON / not a theme file → wrong format marker →
    /// unsupported schema → empty. A valid document with at least one theme yields
    /// themes whose palettes have all been validated, so the caller can adopt them
    /// without any further checking.
    static func themes(from data: Data) throws -> [Theme] {
        let document: CustomThemeDocument
        do {
            document = try JSONDecoder().decode(CustomThemeDocument.self, from: data)
        } catch let error as ThemePalette.ValidationError {
            // A present-but-invalid palette is a *theme* problem, not an "unknown
            // file" one, so surface the precise color error rather than a generic message.
            throw ImportError.invalidPalette(error)
        } catch {
            throw ImportError.notAThemeFile
        }
        guard document.format == formatMarker else { throw ImportError.notAThemeFile }
        guard document.schemaVersion <= currentSchemaVersion, document.schemaVersion >= 1 else {
            throw ImportError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard !document.themes.isEmpty else { throw ImportError.empty }
        return document.themes.map(\.theme)
    }
}

// MARK: - File panels (CS-031)

/// The user-initiated import/export of custom-theme files (CS-031).
///
/// Both directions use only the existing user-selected file-access entitlement — the
/// same one `PresetFileExchange` and `DiagnosticsExporter` rely on — so no new
/// entitlement is required, nothing is uploaded, and the user explicitly chooses
/// every file. The panels are separated from `CustomThemeStore` so the store stays
/// free of AppKit and remains unit-testable.
enum CustomThemeFileExchange {
    /// The document type for a Vitrine theme file: plain JSON.
    static let contentType: UTType = .json

    /// Presents a save panel and writes the user's custom themes to the chosen file.
    /// Returns the URL written, or `nil` on cancel/failure.
    @discardableResult
    static func exportWithSavePanel(store: CustomThemeStore = .shared) -> URL? {
        let data: Data
        do {
            data = try store.exportJSONData()
        } catch {
            Log.export.error("Failed to encode custom themes for export")
            return nil
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "vitrine-themes.json"
        panel.title = "Export Themes"
        panel.nameFieldLabel = "Save as:"
        panel.message =
            "Export your custom themes to a JSON file. Themes are saved only to the file you choose — nothing is sent anywhere."
        panel.prompt = "Export"

        Log.export.info("Presenting custom theme export save panel")
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("Custom theme export cancelled")
            return nil
        }
        do {
            try data.write(to: url, options: .atomic)
            Log.export.notice("Wrote \(data.count, privacy: .public) bytes of themes")
            return url
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "Failed to write theme file (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return nil
        }
    }

    /// Presents an open panel and imports themes from the chosen file. Returns the
    /// number added on success, or throws the import error on an invalid file so the
    /// caller can show clear validation copy. Returns `0` if the user cancels.
    static func importWithOpenPanel(store: CustomThemeStore = .shared) throws -> Int {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Themes"
        panel.prompt = "Import"
        panel.message = "Choose a Vitrine theme file (.json) to add its themes."

        Log.export.info("Presenting custom theme import open panel")
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("Custom theme import cancelled")
            return 0
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Treat an unreadable file as an invalid theme file so the user sees a
            // single, clear message rather than a low-level I/O error.
            throw CustomThemeDocument.ImportError.notAThemeFile
        }
        let added = try store.importThemes(from: data)
        return added.count
    }
}

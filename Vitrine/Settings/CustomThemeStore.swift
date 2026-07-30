import Foundation
import OSLog
import Observation

/// Owns the user's custom themes and brokers every custom-theme operation: import
/// from a documented file schema, export, rename, delete, and resolve a theme id to
/// a `Theme` for the rest of the app.
///
/// ## Design
///
/// - **Built-ins are immutable.** `Theme.builtIns` are the always-present catalog;
///   a custom theme can never use a built-in's id (the store re-keys or refuses one
///   that would collide), so importing or hand-editing a file can never overwrite or
///   shadow a built-in.
/// - **Only user themes persist.** They are stored as one JSON blob under a single
///   `UserDefaults` key, mirroring `PresetStore`. Reads are defensive: a missing or
///   corrupt blob yields an empty user list rather than trapping, so a hand-edited
///   store can never crash the app (defensive behavior). Each stored theme is re-validated
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
    /// The shared store, constructed by the composition root (``AppEnvironment``) and
    /// reached here as a thin forwarder so existing call sites are unchanged.
    static var shared: CustomThemeStore { AppEnvironment.shared.customThemes }

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
            id: StoredCustomTheme.freshID(), displayName: uniqueName(name), palette: palette)
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
    /// palette, then adding the contained themes as new custom themes.
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
                id: StoredCustomTheme.freshID(), displayName: uniqueName(theme.displayName),
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
        let base = StoredCustomTheme.sanitizedName(proposed)
        let taken = Set(
            allThemes.filter { $0.id != id }.map { $0.displayName.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    /// A neutral dark palette used only as a structural fallback when reconstructing
    /// a theme whose palette is somehow absent (it never is for a stored or imported
    /// theme, which always carry one). Keeps reconstruction total without optionals.
    private static let fallbackPalette = ThemePalette(
        background: HexColor("#1E1E1E") ?? .black,
        // Contrasting fallback: should the foreground hex ever fail to parse, fall back to
        // white before black so it stays readable instead of collapsing to dark-on-dark.
        foreground: HexColor("#D4D4D4") ?? HexColor("#FFFFFF") ?? .black)

    // MARK: - Persistence

    /// Reads the persisted custom themes, tolerating any missing or corrupt value.
    /// A garbage blob simply
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

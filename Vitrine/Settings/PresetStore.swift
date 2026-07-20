import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Owns the user's saved style presets and the built-in catalog, and brokers
/// every preset operation: save the current style, apply, duplicate, rename,
/// delete, and import/export as JSON.
///
/// ## Design
///
/// - **Built-ins are immutable.** `StylePreset.builtIns` are merged in front of
///   the user's presets for display but are never persisted, renamed, edited, or
///   deleted. The mutating operations refuse to touch a built-in and offer
///   *duplicate* instead, which copies it into an editable user preset. This is
///   the rule that built-in presets can be duplicated but not overwritten.
/// - **Only user presets persist.** They are stored as one JSON blob under a
///   single `UserDefaults` key, mirroring how `AppSettings` persists the
///   background. Reads are defensive: a missing or corrupt blob yields an empty
///   user list rather than trapping, so a hand-edited store can never crash the
///   app (defensive behavior).
/// - **`UserDefaults` is injectable** so the whole store is unit-testable without
///   touching the real app container, exactly like `AppSettings`.
///
/// Applying a preset is delegated to `AppSettings` so the existing "diverged from
/// preset" bookkeeping for destination presets is untouched; a style
/// preset only writes presentation fields into the live config.
@Observable
final class PresetStore {
    /// The shared store, constructed by the composition root (``AppEnvironment``) and
    /// reached here as a thin forwarder so existing call sites are unchanged.
    static var shared: PresetStore { AppEnvironment.shared.presets }

    /// The user's saved presets, most-recently-saved last. Persisted on change.
    private(set) var userPresets: [StylePreset] {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    /// The single `UserDefaults` key holding the JSON-encoded user presets.
    static let storageKey = "userStylePresets"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.userPresets = Self.readUserPresets(from: defaults)
    }

    /// Re-reads the user presets from the backing store. Used after a global
    /// "Reset all settings" (which clears the persisted blob through
    /// `AppSettings`) so this store's in-memory copy reflects the cleared state
    /// without re-persisting an empty list redundantly.
    func reload() {
        let reloaded = Self.readUserPresets(from: defaults)
        if reloaded != userPresets { userPresets = reloaded }
    }

    // MARK: - Catalog

    /// The full catalog shown in the UI: built-ins first, then the user's presets.
    /// Built-ins lead so the curated set is the obvious starting point.
    var allPresets: [StylePreset] { StylePreset.builtIns + userPresets }

    /// Looks up a preset by id across both built-ins and user presets.
    func preset(withID id: String) -> StylePreset? {
        allPresets.first { $0.id == id }
    }

    // MARK: - Save / duplicate

    /// Saves the current style of `config` as a new user preset named `name`,
    /// returning the created preset ("save current style as a named
    /// preset"). The capture is presentation-only — code and language are never
    /// stored — and the name is sanitized to be non-empty.
    @discardableResult
    func savePreset(named name: String, from config: SnapshotConfig) -> StylePreset {
        let preset = StylePreset.capturing(config, name: uniqueName(name))
        userPresets.append(preset)
        Log.settings.info("Saved a style preset")
        return preset
    }

    /// Duplicates any preset — built-in or user — into a new, fully editable user
    /// preset, appending " Copy" to the name. This is the only way to get
    /// an editable version of a built-in.
    @discardableResult
    func duplicate(_ preset: StylePreset) -> StylePreset {
        let copy = StylePreset(name: uniqueName("\(preset.name) Copy"), style: preset.style)
        userPresets.append(copy)
        Log.settings.info("Duplicated a style preset")
        return copy
    }

    // MARK: - Rename / delete (user presets only)

    /// Renames a **user** preset. A built-in is immutable, so a rename targeting one
    /// is ignored (the UI never offers it). Returns whether a rename happened.
    @discardableResult
    func rename(id: String, to newName: String) -> Bool {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return false }
        userPresets[index].name = StylePreset.sanitizedName(uniqueName(newName, excluding: id))
        return true
    }

    /// Deletes a **user** preset by id. Built-ins cannot be deleted, so an id that
    /// is not a user preset is a no-op. Returns whether a delete happened.
    @discardableResult
    func delete(id: String) -> Bool {
        let before = userPresets.count
        userPresets.removeAll { $0.id == id }
        return userPresets.count != before
    }

    /// Whether `id` names a built-in preset (and is therefore immutable).
    func isBuiltIn(id: String) -> Bool { StylePreset.builtInIDs.contains(id) }

    // MARK: - Import / export

    /// The exportable document for the user's presets (built-ins are not exported;
    /// they ship with every install). Empty user lists still produce a valid,
    /// importable document so "Export" never fails — though the UI gates the action
    /// on having at least one user preset.
    func exportDocument() -> StylePresetDocument {
        StylePresetDocument(presets: userPresets)
    }

    /// Pretty-printed JSON for the user's presets, suitable for writing to a file.
    func exportJSONData() throws -> Data {
        try exportDocument().jsonData()
    }

    /// Imports presets from preset-file `data`, validating the envelope and adding
    /// the contained presets as new user presets.
    ///
    /// Imported presets are re-keyed with fresh ids so importing the same file
    /// twice, or a file that happens to reuse an id, never overwrites an existing
    /// preset or collides with a built-in id — an import only ever *adds*. Throws a
    /// specific `StylePresetDocument.ImportError` (with user-facing copy) on an
    /// invalid file; the live state is left untouched on failure.
    ///
    /// - Returns: the presets that were added.
    @discardableResult
    func importPresets(from data: Data) throws -> [StylePreset] {
        let incoming = try StylePresetDocument.presets(from: data)
        let added = incoming.map { preset in
            // Re-key onto a fresh id and de-duplicate the name so the import is
            // purely additive and can never shadow an existing or built-in preset.
            StylePreset(name: uniqueName(preset.name), style: preset.style)
        }
        userPresets.append(contentsOf: added)
        Log.settings.info("Imported \(added.count, privacy: .public) style preset(s)")
        return added
    }

    // MARK: - Naming

    /// A name unique across the whole catalog, suffixing " 2", " 3", … on a clash.
    /// `excluding` lets a rename keep its own current name without colliding with
    /// itself. Keeps the picker unambiguous without ever rejecting a save.
    private func uniqueName(_ proposed: String, excluding id: String? = nil) -> String {
        let base = StylePreset.sanitizedName(proposed)
        let taken = Set(
            allPresets.filter { $0.id != id }.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    // MARK: - Persistence

    /// Reads the persisted user presets, tolerating any missing or corrupt value
    /// ("invalid preset files do not crash"). A garbage blob simply
    /// yields an empty list, leaving the built-ins available. Any preset whose id
    /// collides with a built-in's reserved id is dropped so a hand-edited store
    /// cannot shadow or "overwrite" a built-in.
    private static func readUserPresets(from defaults: UserDefaults) -> [StylePreset] {
        guard let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(
                [FailableDecodable<StylePreset>].self, from: data)
        else { return [] }
        // One corrupt element drops itself rather than wiping every user preset on the
        // next launch.
        return decoded.compactMap(\.value).filter { !StylePreset.builtInIDs.contains($0.id) }
    }

    /// Persists the user presets as a JSON array. An unexpected encode failure
    /// drops the key rather than leaving a stale blob behind, mirroring how
    /// `AppSettings` persists the background.
    private func persist() {
        guard let data = try? JSONEncoder().encode(userPresets) else {
            defaults.removeObject(forKey: Self.storageKey)
            Log.settings.error("Style preset encode failed; not persisting")
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - File panels

/// The user-initiated import/export of preset files.
///
/// Both directions use only the existing user-selected file-access entitlement —
/// the same one `DiagnosticsExporter` relies on — so no new entitlement is
/// required, nothing is uploaded, and the user explicitly chooses every file. The
/// panels are separated from `PresetStore` so the store stays free of AppKit and
/// remains unit-testable.
enum PresetFileExchange {
    /// The document type for a Vitrine preset file: plain JSON.
    static let contentType: UTType = .json

    /// Presents a save panel and writes the user's presets to the chosen file.
    /// No-op if the user cancels or there is nothing to export. Returns the URL
    /// written, or `nil` on cancel/failure.
    @discardableResult
    static func exportWithSavePanel(store: PresetStore = .shared) -> URL? {
        let data: Data
        do {
            data = try store.exportJSONData()
        } catch {
            Log.export.error("Failed to encode style presets for export")
            return nil
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "vitrine-presets.json"
        // Modern macOS largely ignores `title` for the panel's window title, so the
        // orienting wording lives in `message` (which always surfaces) rather than
        // relying on a title the user may never see.
        panel.title = "Export Presets"
        panel.nameFieldLabel = "Save as:"
        panel.message =
            "Export your saved presets to a JSON file. Presets are saved only to the file you choose — nothing is sent anywhere."
        panel.prompt = "Export"

        Log.export.info("Presenting preset export save panel")
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("Preset export cancelled")
            return nil
        }
        do {
            try data.write(to: url, options: .atomic)
            Log.export.notice("Wrote \(data.count, privacy: .public) bytes of presets")
            return url
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "Failed to write preset file (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return nil
        }
    }

    /// Presents an open panel and imports presets from the chosen file. Returns the
    /// number added on success, or throws the import error on an invalid file so the
    /// caller can show clear validation copy. Returns `0` if the user cancels.
    static func importWithOpenPanel(store: PresetStore = .shared) throws -> Int {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // As with the export panel, `title` is largely ignored for the window
        // title on modern macOS, so the orienting wording lives in `message`.
        panel.title = "Import Presets"
        panel.prompt = "Import"
        panel.message = "Choose a Vitrine preset file (.json) to add its presets."

        Log.export.info("Presenting preset import open panel")
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("Preset import cancelled")
            return 0
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Treat an unreadable file as an invalid preset file so the user sees a
            // single, clear message rather than a low-level I/O error.
            throw StylePresetDocument.ImportError.notAPresetFile
        }
        let added = try store.importPresets(from: data)
        return added.count
    }
}

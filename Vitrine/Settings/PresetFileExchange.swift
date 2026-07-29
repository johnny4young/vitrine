import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

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

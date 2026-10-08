import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers
import VitrineDomain

/// The user-initiated import/export of custom-theme files.
///
/// Both directions use only the existing user-selected file-access entitlement — the
/// same one `PresetFileExchange` and `DiagnosticsExporter` rely on — so no new
/// entitlement is required, nothing is uploaded, and the user explicitly chooses
/// every file. The panels are separated from `CustomThemeStore` so the store stays
/// free of AppKit and remains unit-testable.
enum CustomThemeFileExchange {
    /// The document type for a Vitrine theme file: plain JSON.
    static let contentType: UTType = .json
    static let maximumByteCount = 1_048_576

    /// Presents a save panel and writes the user's custom themes to the chosen file.
    @discardableResult
    static func exportWithSavePanel(store: CustomThemeStore) -> FileExchangePanel.SaveOutcome {
        let data: Data
        do {
            data = try store.exportJSONData()
        } catch {
            Log.export.error("Failed to encode custom themes for export")
            return .failed
        }
        return FileExchangePanel.save(
            data, contentType: contentType, suggestedFilename: "vitrine-themes.json",
            copy: FileExchangePanel.Copy(
                title: String(localized: "Export Themes"),
                message: String(
                    localized:
                        "Export your custom themes to a JSON file. Themes are saved only to the file you choose — nothing is sent anywhere."
                ),
                prompt: String(localized: "panel.prompt.export", defaultValue: "Export")),
            logLabel: "custom themes")
    }

    /// Presents an open panel and imports themes from the chosen file. Returns the
    /// number added on success, or throws the import error on an invalid file so the
    /// caller can show clear validation copy. Returns `0` if the user cancels.
    static func importWithOpenPanel(store: CustomThemeStore) throws -> Int {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = String(localized: "Import Themes")
        panel.prompt = String(localized: "Import")
        panel.message = String(localized: "Choose a Vitrine theme file (.json) to add its themes.")

        Log.export.info("Presenting custom theme import open panel")
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("Custom theme import cancelled")
            return 0
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let added = try importFile(at: url, store: store)
        return added.count
    }

    /// Imports a selected file after the caller has established any required
    /// security-scoped access. Kept separate from the panel so file-policy tests do
    /// not need to drive AppKit.
    static func importFile(at url: URL, store: CustomThemeStore) throws -> [Theme] {
        let data: Data
        do {
            data = try BoundedFileReader.read(from: url, limit: maximumByteCount)
        } catch BoundedFileReader.ReadError.tooLarge {
            throw CustomThemeDocument.ImportError.fileTooLarge
        } catch {
            throw CustomThemeDocument.ImportError.notAThemeFile
        }
        return try store.importThemes(from: data)
    }
}

import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers
import VitrineDomain

/// User-initiated recipe export and folder association panels.
///
/// The model and store remain AppKit-free. This boundary asks for each folder or
/// file explicitly and never scans a repository for conventional filenames.
enum WorkspaceRecipeFileExchange {
    enum ExchangeError: Error, Equatable {
        case encodingFailed
        case writeFailed

        var message: String {
            switch self {
            case .encodingFailed:
                String(localized: "The workspace recipe could not be encoded.")
            case .writeFailed:
                String(localized: "The workspace recipe could not be written to the selected file.")
            }
        }
    }

    static let contentType: UTType = .json

    /// Writes a portable recipe to the exact location selected by the user.
    /// Returns `false` when the panel is cancelled.
    static func exportWithSavePanel(_ recipe: WorkspaceRecipe) throws -> Bool {
        let data: Data
        do {
            data = try WorkspaceRecipeDocument(recipe: recipe).validatedJSONData()
        } catch {
            throw ExchangeError.encodingFailed
        }

        let outcome = FileExchangePanel.save(
            data, contentType: contentType,
            suggestedFilename: "\(filenameStem(recipe.name)).vitrine-recipe.json",
            copy: FileExchangePanel.Copy(
                title: String(localized: "Export Workspace Recipe"),
                message: String(
                    localized:
                        "Save a portable style and output recipe. It contains no workspace path, source text, output path, history, or credentials."
                ),
                prompt: String(localized: "panel.prompt.export", defaultValue: "Export")),
            logLabel: "workspace recipe")
        switch outcome {
        case .saved: return true
        case .cancelled: return false
        case .failed: throw ExchangeError.writeFailed
        }
    }

    enum StyleSaveOutcome: Equatable {
        case cancelled
        case savedToRecipe
        case savedElsewhere
    }

    /// Writes changed style fields into an association's recipe after the user confirms
    /// the file in a save panel. Associations hold read-only bookmarks, so the panel is
    /// what grants write access. The write is atomic or fails, never in place.
    static func saveStyleChanges(
        _ style: StyleSnapshot, fields: Set<String>, customTheme: StoredCustomTheme?,
        associationID: UUID, store: WorkspaceRecipeStore
    ) throws -> StyleSaveOutcome {
        let source = try store.recipeFile(id: associationID)
        let data = try WorkspaceRecipeDocument.updatingStyle(
            in: source.data, to: style, fields: fields, customTheme: customTheme)
        let filename = source.url.lastPathComponent
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.directoryURL = source.url.deletingLastPathComponent()
        panel.nameFieldStringValue = filename
        panel.message = String(localized: "Save this editor's style changes to “\(filename)”.")
        panel.prompt = String(localized: "Save")
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let nsError = error as NSError
            Log.settings.error(
                "Failed to save a workspace recipe (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            throw ExchangeError.writeFailed
        }
        Log.settings.notice(
            "Saved \(fields.count, privacy: .public) style fields to a workspace recipe")
        let saved = url.standardizedFileURL.resolvingSymlinksInPath()
        return saved == source.url ? .savedToRecipe : .savedElsewhere
    }

    /// Asks for a workspace folder first and an existing recipe file second.
    /// Returning both URLs together prevents partially persisted associations when
    /// the second panel is cancelled.
    static func chooseAssociationURLs() -> (workspace: URL, recipe: URL)? {
        let workspacePanel = NSOpenPanel()
        workspacePanel.canChooseFiles = false
        workspacePanel.canChooseDirectories = true
        workspacePanel.allowsMultipleSelection = false
        workspacePanel.title = String(localized: "Choose Workspace")
        workspacePanel.prompt = String(localized: "Choose")
        workspacePanel.message =
            String(
                localized:
                    "Choose the folder or repository whose explicitly dropped files should use one recipe."
            )
        guard workspacePanel.runModal() == .OK, let workspace = workspacePanel.url else {
            return nil
        }

        let recipePanel = NSOpenPanel()
        recipePanel.allowedContentTypes = [contentType]
        recipePanel.canChooseFiles = true
        recipePanel.canChooseDirectories = false
        recipePanel.allowsMultipleSelection = false
        recipePanel.directoryURL = workspace
        recipePanel.title = String(localized: "Choose Workspace Recipe")
        recipePanel.prompt = String(localized: "Associate")
        recipePanel.message =
            String(
                localized:
                    "Choose the portable Vitrine recipe to apply when you explicitly drop a file from that workspace."
            )
        guard recipePanel.runModal() == .OK, let recipe = recipePanel.url else { return nil }
        return (workspace, recipe)
    }

    private static func filenameStem(_ name: String) -> String {
        let scalars = name.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let collapsed = String(scalars).split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "workspace" : collapsed
    }
}

import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

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
                "The workspace recipe could not be encoded."
            case .writeFailed:
                "The workspace recipe could not be written to the selected file."
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

        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "\(filenameStem(recipe.name)).vitrine-recipe.json"
        panel.title = String(localized: "Export Workspace Recipe")
        panel.nameFieldLabel = String(localized: "Save as:")
        panel.message =
            String(
                localized:
                    "Save a portable style and output recipe. It contains no workspace path, source text, output path, history, or credentials."
            )
        panel.prompt = String(localized: "Export")
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try data.write(to: url, options: .atomic)
            Log.export.notice("Wrote a workspace recipe (\(data.count, privacy: .public) bytes)")
            return true
        } catch {
            Log.export.error("Failed to write a workspace recipe")
            throw ExchangeError.writeFailed
        }
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

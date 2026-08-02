import SwiftUI

/// Manages machine-local folder associations and exports the current default as a
/// portable recipe the CLI can consume explicitly.
struct WorkspaceRecipeSettingsSection: View {
    @Bindable var settings: AppSettings
    var store: WorkspaceRecipeStore

    @State private var selectedID: UUID?
    @State private var showExportPrompt = false
    @State private var exportName = ""
    @State private var noticeTitle: String?
    @State private var noticeMessage: String?

    private static let noneTag = "__none__"

    var body: some View {
        TokenGroup(title: Text("Workspace recipes")) {
            TokenRow(
                label: Text("Association"),
                caption: Text("Apply a recipe when you explicitly drop a file from a folder")
            ) {
                Picker("Workspace recipe association", selection: pickerBinding) {
                    Text("Choose an association…").tag(Self.noneTag)
                    ForEach(store.associations) { association in
                        Text("\(association.workspaceName) — \(association.recipeFilename)")
                            .tag(association.id.uuidString)
                    }
                }
                .labelsHidden()
                .frame(width: 250)
                .help(
                    "Associations stay on this Mac as security-scoped bookmarks. Recipe files remain portable and path-free."
                )
                .accessibilityIdentifier("workspace-recipe-picker")
            }

            TokenRow(
                label: Text("Manage"),
                caption: Text("No repository scanning or implicit recipe discovery")
            ) {
                HStack(spacing: VitrineTokens.Spacing.xs) {
                    Button("Add…", action: addAssociation)
                        .buttonStyle(.borderedProminent)
                        .help("Choose one folder and one existing Vitrine recipe file.")
                        .accessibilityIdentifier("add-workspace-recipe-button")
                    Button("Apply to Default", action: applySelected)
                        .disabled(selectedAssociation == nil)
                        .help(
                            "Apply the selected recipe to Vitrine's default style and export settings."
                        )
                        .accessibilityIdentifier("apply-workspace-recipe-button")
                    Button("Remove", role: .destructive, action: removeSelected)
                        .disabled(selectedAssociation == nil)
                        .help("Remove only the local association. The recipe file is not deleted.")
                        .accessibilityIdentifier("remove-workspace-recipe-button")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }

            TokenRow(
                label: Text("Portable file"),
                caption: Text("Export the current default for vitrine --recipe")
            ) {
                Button("Export Current…") {
                    exportName = settings.config.metadata.title ?? "Workspace"
                    showExportPrompt = true
                }
                .buttonStyle(.bordered)
                .help(
                    "Export style, safe metadata, and output defaults without source or workspace paths."
                )
                .accessibilityIdentifier("export-workspace-recipe-button")
            }
        }
        .alert("Export Workspace Recipe", isPresented: $showExportPrompt) {
            TextField("Name", text: $exportName)
                .accessibilityIdentifier("workspace-recipe-name-field")
            Button("Continue", action: exportCurrent)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Name this portable recipe, then choose where to save it. The file never includes a workspace path or source text."
            )
        }
        .alert(
            noticeTitle ?? "Workspace Recipe",
            isPresented: Binding(
                get: { noticeMessage != nil },
                set: {
                    if !$0 {
                        noticeTitle = nil
                        noticeMessage = nil
                    }
                })
        ) {
            Button("OK", role: .cancel) {
                noticeTitle = nil
                noticeMessage = nil
            }
        } message: {
            Text(noticeMessage ?? "")
        }
    }

    private var pickerBinding: Binding<String> {
        Binding(
            get: { selectedID?.uuidString ?? Self.noneTag },
            set: { selectedID = $0 == Self.noneTag ? nil : UUID(uuidString: $0) })
    }

    private var selectedAssociation: WorkspaceRecipeAssociation? {
        guard let selectedID else { return nil }
        return store.associations.first { $0.id == selectedID }
    }

    private func addAssociation() {
        guard let urls = WorkspaceRecipeFileExchange.chooseAssociationURLs() else { return }
        do {
            let association = try store.associate(
                workspaceURL: urls.workspace, recipeURL: urls.recipe)
            selectedID = association.id
            showNotice(
                title: String(localized: "Association Saved"),
                message: String(
                    localized:
                        "Files you explicitly drop from \(association.workspaceName) can now use \(association.recipeFilename)."
                )
            )
        } catch let error as WorkspaceRecipeStore.StoreError {
            showNotice(title: String(localized: "Association Not Saved"), message: error.message)
        } catch {
            showNotice(
                title: String(localized: "Association Not Saved"),
                message: String(
                    localized: "Vitrine could not save that workspace recipe association."))
        }
    }

    private func applySelected() {
        guard let selectedID else { return }
        do {
            let resolved = try store.resolvedRecipe(id: selectedID)
            let ignoredCanvas = settings.applyWorkspaceRecipe(resolved.recipe)
            let message =
                ignoredCanvas
                ? String(
                    localized:
                        "Applied \(resolved.recipe.name) to Vitrine's default. Its custom canvas size remains available to the CLI but is not applied by the app."
                )
                : String(localized: "Applied \(resolved.recipe.name) to Vitrine's default.")
            showNotice(
                title: String(localized: "Recipe Applied"),
                message: message)
        } catch let error as WorkspaceRecipeStore.StoreError {
            showNotice(title: String(localized: "Recipe Not Applied"), message: error.message)
        } catch {
            showNotice(
                title: String(localized: "Recipe Not Applied"),
                message: String(localized: "Vitrine could not load the associated recipe."))
        }
    }

    private func removeSelected() {
        guard let selectedID else { return }
        if store.remove(id: selectedID) {
            self.selectedID = nil
            showNotice(
                title: String(localized: "Association Removed"),
                message: String(
                    localized:
                        "The local association was removed. No folder or recipe file was deleted."))
        }
    }

    private func exportCurrent() {
        let recipe = settings.workspaceRecipe(named: exportName)
        do {
            _ = try WorkspaceRecipeFileExchange.exportWithSavePanel(recipe)
        } catch let error as WorkspaceRecipeFileExchange.ExchangeError {
            showNotice(title: String(localized: "Recipe Not Exported"), message: error.message)
        } catch {
            showNotice(
                title: String(localized: "Recipe Not Exported"),
                message: String(localized: "The workspace recipe could not be exported.")
            )
        }
    }

    private func showNotice(title: String, message: String) {
        noticeTitle = title
        noticeMessage = message
    }
}

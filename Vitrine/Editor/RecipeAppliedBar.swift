import SwiftUI
import VitrineDomain
import VitrineRendering

/// The recipe a drop applied to a window and the style it left behind, so the bar
/// can count real style changes against it and restore it.
struct AppliedRecipe {
    var associationID: UUID
    var name: String
    var workspaceName: String
    /// The window's render inputs right after the recipe and the file applied.
    var baseline: SnapshotConfig
    var documentGeneration: Int

    /// Judged under the current language, so switching it alone is not a style change.
    func changedFields(in style: SnapshotConfig) -> Set<String> {
        var reference = baseline
        reference.language = style.language
        return StyleSnapshot(capturing: style).changedFields(
            from: StyleSnapshot(capturing: reference))
    }

    /// `style` with the recipe's look restored; code, marks and metadata stay.
    func reverted(_ style: SnapshotConfig) -> SnapshotConfig {
        var updated = style
        StyleSnapshot(capturing: baseline).apply(to: &updated) { _ in baseline.theme }
        updated.terminalPalette = baseline.terminalPalette
        updated.terminalCursor = baseline.terminalCursor
        return updated
    }
}

extension AppliedRecipe {
    init(_ resolved: WorkspaceRecipeStore.ResolvedRecipe, settings: AppSettings) {
        self.init(
            associationID: resolved.association.id, name: resolved.recipe.name,
            workspaceName: resolved.association.workspaceName, baseline: settings.style,
            documentGeneration: settings.documentGeneration)
    }
}

/// Floats over the top of the stage, so showing it never moves the preview. It reads
/// the style, not the document text, which keeps keystrokes from reaching it.
struct RecipeAppliedBar: View {
    let session: EditorSession
    let settings: AppSettings

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let applied = session.appliedRecipe,
            applied.documentGeneration == settings.documentGeneration
        {
            bar(applied, changes: applied.changedFields(in: settings.style))
        }
    }

    private func bar(_ applied: AppliedRecipe, changes: Set<String>) -> some View {
        let canSave = session.environment.workspaceRecipes.associations.contains {
            $0.id == applied.associationID
        }
        // A narrow stage, or a longer translation, gets icon buttons rather than clipping.
        return ViewThatFits(in: .horizontal) {
            row(applied, changes: changes, canSave: canSave, labelStyle: .titleOnly)
            row(applied, changes: changes, canSave: canSave, labelStyle: .iconOnly)
            row(
                applied, changes: changes, canSave: canSave, labelStyle: .iconOnly,
                showsFolder: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: VitrineTokens.FontSize.caption))
        .padding(.vertical, 5)
        .padding(.horizontal, VitrineTokens.Spacing.sm)
        .background(Capsule(style: .continuous).fill(VitrineTokens.Chrome.statusCapsule))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
        )
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe-applied-bar")
    }

    private func row(
        _ applied: AppliedRecipe, changes: Set<String>, canSave: Bool,
        labelStyle: some LabelStyle, showsFolder: Bool = true
    ) -> some View {
        HStack(spacing: VitrineTokens.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .accessibilityHidden(true)
                // The icon says "recipe" on screen, which leaves Spanish room for the name.
                Text(verbatim: applied.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(VitrineTokens.Text.primary)
                    .accessibilityLabel(Text("\(applied.name) recipe"))
                if showsFolder {
                    Label {
                        Text(verbatim: applied.workspaceName)
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .fixedSize()
                    .accessibilityLabel(Text("Folder \(applied.workspaceName)"))
                }
                if !changes.isEmpty {
                    Text("\(changes.count) changes")
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .fixedSize()
                }
            }
            .lineLimit(1)
            .help(Text("\(applied.name) recipe"))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("recipe-bar-summary")

            Group {
                Button {
                    revert(applied)
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .help("Revert")
                .disabled(changes.isEmpty)
                .accessibilityIdentifier("recipe-bar-revert")
                Button {
                    save(applied, fields: changes)
                } label: {
                    Label("Save to Recipe…", systemImage: "square.and.arrow.down")
                }
                .help("Save to Recipe…")
                .disabled(changes.isEmpty || !canSave)
                .accessibilityIdentifier("recipe-bar-save")
            }
            .labelStyle(labelStyle)
            .fixedSize()
            Button {
                session.appliedRecipe = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("recipe-bar-close")
        }
    }

    private func revert(_ applied: AppliedRecipe) {
        let previous = settings.style
        undoManager?.registerUndo(withTarget: settings) { settings in
            settings.style = previous
        }
        undoManager?.setActionName(String(localized: "Revert to Recipe"))
        settings.style = applied.reverted(previous)
    }

    private func save(_ applied: AppliedRecipe, fields: Set<String>) {
        let style = settings.style
        do {
            let outcome = try WorkspaceRecipeFileExchange.saveStyleChanges(
                StyleSnapshot(capturing: style), fields: fields,
                customTheme: StoredCustomTheme(style.theme),
                associationID: applied.associationID,
                store: session.environment.workspaceRecipes)
            guard outcome != .cancelled else { return }
            if outcome == .savedToRecipe {
                session.appliedRecipe?.baseline = style
            }
            session.feedback(Notifier.confirmation(String(localized: "Recipe saved")))
        } catch let error as WorkspaceRecipeStore.StoreError {
            session.feedback(Notifier.failure(error.message))
        } catch let error as WorkspaceRecipeDocument.ImportError {
            session.feedback(Notifier.failure(error.localizedMessage))
        } catch {
            session.feedback(
                Notifier.failure(WorkspaceRecipeFileExchange.ExchangeError.writeFailed.message))
        }
    }
}

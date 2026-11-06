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
        var fields = StyleSnapshot(capturing: style).changedFields(
            from: StyleSnapshot(capturing: reference))
        // A snapshot swaps an image background for a gradient, so compare the raw value.
        fields.remove("background")
        if style.background != baseline.background { fields.insert("background") }
        return fields
    }

    /// The style fields Revert writes, taken raw so an image background round-trips.
    struct Look {
        var snapshot: StyleSnapshot
        var theme: Theme
        var terminalPalette: TerminalPaletteMode
        var terminalCursor: TerminalCursorStyle
        var background: VitrineDomain.BackgroundStyle

        init(_ config: SnapshotConfig) {
            snapshot = StyleSnapshot(capturing: config)
            theme = config.theme
            terminalPalette = config.terminalPalette
            terminalCursor = config.terminalCursor
            background = config.background
        }

        func apply(to config: inout SnapshotConfig) {
            snapshot.apply(to: &config) { _ in theme }
            config.terminalPalette = terminalPalette
            config.terminalCursor = terminalCursor
            config.background = background
        }
    }

    /// Writes `look` into the style only, and registers its inverse so undo and redo
    /// never touch code, marks or redactions made in between.
    static func restore(_ look: Look, to settings: AppSettings, undoManager: UndoManager?) {
        let current = Look(settings.style)
        undoManager?.registerUndo(withTarget: settings) { settings in
            restore(current, to: settings, undoManager: undoManager)
        }
        undoManager?.setActionName(String(localized: "Revert to Recipe"))
        var style = settings.style
        look.apply(to: &style)
        settings.style = style
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

/// Floats over the top of the stage, inside the margin the card is fitted with, so
/// showing it never moves or covers the preview. It never reads the document text.
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
        // Narrower stages and longer translations lose the folder first, then the labels.
        ViewThatFits(in: .horizontal) {
            row(applied, changes: changes, labelStyle: .titleOnly, showsFolder: true)
            row(applied, changes: changes, labelStyle: .titleOnly, showsFolder: false)
            row(applied, changes: changes, labelStyle: .iconOnly, showsFolder: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: VitrineTokens.FontSize.caption))
        .padding(.horizontal, VitrineTokens.Spacing.sm)
        .frame(height: 26)
        .background(Capsule(style: .continuous).fill(VitrineTokens.Chrome.statusCapsule))
        .overlay(
            // Drawn over the buttons, so it must not take their clicks.
            Capsule(style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                .allowsHitTesting(false)
        )
        .padding(.horizontal, 12)
        // 6 + 26 stays inside the 36 pt the stage keeps above a height-fitted card.
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recipe-applied-bar")
    }

    private func row(
        _ applied: AppliedRecipe, changes: Set<String>, labelStyle: some LabelStyle,
        showsFolder: Bool
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

            Button {
                AppliedRecipe.restore(
                    AppliedRecipe.Look(applied.baseline), to: settings, undoManager: undoManager)
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }
            .labelStyle(labelStyle)
            .fixedSize()
            .help("Revert")
            .disabled(changes.isEmpty)
            .accessibilityIdentifier("recipe-bar-revert")
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
}

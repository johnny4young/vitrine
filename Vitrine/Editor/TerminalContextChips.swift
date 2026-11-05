import SwiftUI
import VitrineDomain
import VitrineRendering

/// The header's project, branch and command as removable chips. They read only the header's
/// filename and title, and rewrite those plus any copy in the alt text and window title.
struct TerminalContextChips: View {
    @Bindable var settings: AppSettings
    @Environment(\.undoManager) private var undoManager

    private var context: TerminalHeaderContext {
        TerminalHeaderContext(
            filename: settings.style.metadata.filename, title: settings.style.metadata.title)
    }

    var body: some View {
        let context = context
        if !context.labels.isEmpty || context.command != nil {
            FlowLayout {
                ForEach(Array(context.labels.enumerated()), id: \.offset) { index, label in
                    chip(label, identifier: "terminal-context-label-\(index)") {
                        update(undoName: String(localized: "Remove Header Item")) {
                            $0.labels.remove(at: index)
                        }
                    }
                }
                if let command = context.command {
                    chip(command, identifier: "terminal-context-command") {
                        update(undoName: String(localized: "Remove Header Item")) {
                            $0.removeTitle()
                        }
                    }
                }
            }
        }
        if context.titleText != nil {
            InspectorRow(label: Text("Prompt")) {
                TokenSegmentedPicker(
                    options: [
                        (
                            TerminalHeaderContext.Prompt.dollar,
                            Text(verbatim: "$").accessibilityLabel(Text("Dollar sign"))
                        ),
                        (
                            TerminalHeaderContext.Prompt.chevron,
                            Text(verbatim: "›").accessibilityLabel(Text("Chevron"))
                        ),
                        (TerminalHeaderContext.Prompt.none, Text("None")),
                    ],
                    selection: Binding(
                        get: { context.prompt },
                        set: { prompt in update { $0.prompt = prompt } })
                )
                .accessibilityLabel("Prompt")
                .accessibilityIdentifier("terminal-prompt-picker")
            }
        }
        if context.canRemoveArguments {
            Button("Remove arguments") {
                update(undoName: String(localized: "Remove Arguments")) { $0.removeArguments() }
            }
            .help("Keep only the command's name.")
            .accessibilityIdentifier("terminal-remove-arguments-button")
        }
    }

    private func update(undoName: String? = nil, _ change: (inout TerminalHeaderContext) -> Void) {
        var edited = context
        change(&edited)
        Self.apply(edited, to: settings, undoName: undoName, undoManager: undoManager)
    }

    /// One write, so one edit is one render. Undo holds the old text in memory only.
    static func apply(
        _ edited: TerminalHeaderContext, to settings: AppSettings, undoName: String?,
        undoManager: UndoManager?
    ) {
        var style = settings.style
        let (metadata, altText, windowTitle) = (style.metadata, style.altText, style.windowTitle)
        style.applyTerminalHeader(edited)
        if let undoName {
            undoManager?.registerUndo(withTarget: settings) { settings in
                settings.style.metadata = metadata
                settings.style.altText = altText
                settings.style.windowTitle = windowTitle
            }
            undoManager?.setActionName(undoName)
        }
        settings.style = style
    }

    private func chip(
        _ text: String, identifier: String, remove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: text)
                .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(Text(verbatim: text))
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    // A 24 pt target that lays out, and looks, like the 14 pt glyph box.
                    .padding(-5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(text)"))
            .accessibilityIdentifier("\(identifier)-remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: 240, alignment: .leading)
        .background(Capsule().fill(VitrineTokens.Chrome.segmentTrack))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

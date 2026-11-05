import SwiftUI
import VitrineDomain
import VitrineRendering

/// The header's project, branch and command as removable chips. They edit only the header's
/// filename and title, read nothing else, and add nothing the header doesn't already draw.
struct TerminalContextChips: View {
    @Bindable var settings: AppSettings

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
                        update { $0.labels.remove(at: index) }
                    }
                }
                if let command = context.command {
                    chip(command, identifier: "terminal-context-command") {
                        update { $0.command = nil }
                    }
                }
            }
        }
        if context.command != nil {
            InspectorRow(label: Text("Prompt")) {
                TokenSegmentedPicker(
                    options: [
                        (TerminalHeaderContext.Prompt.dollar, Text(verbatim: "$")),
                        (TerminalHeaderContext.Prompt.chevron, Text(verbatim: "›")),
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
        if context.canHideArguments {
            Button("Hide arguments") { update { $0.hideArguments() } }
                .help("Keep only the command's name. Type it in Title to bring the rest back.")
                .accessibilityIdentifier("terminal-hide-arguments-button")
        }
    }

    /// Writes both fields at once, so one edit is one render.
    private func update(_ change: (inout TerminalHeaderContext) -> Void) {
        var context = context
        change(&context)
        var metadata = settings.style.metadata
        metadata.filename = context.filename
        metadata.title = context.title
        settings.style.metadata = metadata
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
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
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

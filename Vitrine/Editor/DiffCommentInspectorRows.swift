import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// The diff inspector's comment rows: pin a comment to the caret's line, and clear the
/// comments whose line was edited away.
struct DiffCommentInspectorRows: View {
    @Bindable var settings: AppSettings
    @State private var window = WeakWindowReference()
    /// The code editor's caret line, followed through its selection notifications.
    @State private var caretRow: Int?

    var body: some View {
        InspectorRow(label: Text("Comment on selected line")) {
            Button {
                NotificationCenter.default.post(
                    name: .vitrineCommentOnSelectedLine, object: window.value)
            } label: {
                Text(verbatim: "⇧⌘M")
                    .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!caretRowIsShown)
            .help(VitrineCommand.commentOnLine.accessibilityLabel)
            .accessibilityLabel(VitrineCommand.commentOnLine.accessibilityLabel)
            .accessibilityIdentifier("diff-comment-button")
        }
        .background(
            WindowAccessor { resolved in
                window.value = resolved
                caretRow = EditorView.caretRow(in: resolved)
            }
        )
        .onReceive(
            NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)
        ) { notification in
            guard let textView = notification.object as? NSTextView,
                textView.window === window.value,
                textView.accessibilityIdentifier() == "code-editor-text-view"
            else { return }
            caretRow = EditorView.caretRow(
                in: textView.string, at: textView.selectedRange().location)
        }
        let detached = settings.style.annotations.filter { $0.lineAnchor?.isDetached == true }
        if !detached.isEmpty {
            InspectorRow(label: Text("Detached comments")) {
                HStack(spacing: 8) {
                    Text(verbatim: "\(detached.count)")
                        .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                        .accessibilityIdentifier("diff-detached-comment-count")
                    Button("Remove") {
                        NotificationCenter.default.post(
                            name: .vitrineRemoveDetachedComments, object: window.value)
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Remove detached comments")
                    .accessibilityIdentifier("diff-remove-detached-comments")
                }
            }
        }
    }

    /// A comment on a folded or unpicked row would not draw, so the button waits for one
    /// that shows. Reads the document text, which this small view alone observes.
    private var caretRowIsShown: Bool {
        guard let caretRow else { return false }
        var config = settings.style
        config.code = settings.documentCode
        return config.showsDiffRow(caretRow)
    }
}

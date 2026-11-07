import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// The diff inspector's comment rows: pin a comment to the caret's line, and clear the
/// comments whose line was edited away.
struct DiffCommentInspectorRows: View {
    @Bindable var settings: AppSettings

    var body: some View {
        InspectorRow(label: Text("Comment on selected line")) {
            Button {
                NotificationCenter.default.post(
                    name: .vitrineCommentOnSelectedLine, object: NSApp.keyWindow)
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
            .disabled(settings.documentIsEmpty)
            .help(VitrineCommand.commentOnLine.accessibilityLabel)
            .accessibilityLabel(VitrineCommand.commentOnLine.accessibilityLabel)
            .accessibilityIdentifier("diff-comment-button")
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
                        settings.style.annotations.removeAll { $0.lineAnchor?.isDetached == true }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Remove detached comments")
                    .accessibilityIdentifier("diff-remove-detached-comments")
                }
            }
        }
    }
}

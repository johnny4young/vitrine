import AppKit
import SwiftUI

/// The Web Snapshot composer's glass toolbar (export/copy/share actions).
extension WebSnapshotEditorView {
    // MARK: - Toolbar

    var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(verbatim: "Web Snapshot")
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
            }

            Spacer(minLength: 0)

            if model.results.count > 1 {
                iconButton(
                    "web-snapshot-export-all-button", label: "Export all sizes",
                    help: "Export every captured size, plus the board, to a folder",
                    systemImage: "rectangle.stack.badge.plus", action: exportAll)
            }
            iconButton(
                "web-snapshot-save-button", label: VitrineCommand.saveImage.accessibilityLabel,
                help: "Save the snapshot as a file", systemImage: "square.and.arrow.down",
                shortcut: KeyboardShortcut("s", modifiers: .command), action: saveImage)
            iconButton(
                "web-snapshot-share-button", label: VitrineCommand.shareImage.accessibilityLabel,
                help: "Share the snapshot", systemImage: "square.and.arrow.up", action: shareImage)

            GradientCTAButton {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                Text("Copy image")
            } action: {
                copyImage()
            }
            .help("Copy the snapshot to the clipboard")
            .disabled(!hasResult)
            // ⇧⌘C, matching the editor's image-copy command (the menu's image commands
            // are gated to editor windows, so this window provides its own shortcut).
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityLabel(VitrineCommand.copyImage.accessibilityLabel)
            .accessibilityIdentifier("web-snapshot-copy-button")
        }
        .padding(.vertical, 10)
        .padding(.trailing, VitrineTokens.Spacing.md)
        .padding(.leading, 86)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(height: Brand.Stroke.hairline)
        }
        .accessibilityContainerIdentifier("web-snapshot-toolbar")
        .accessibilityLabel("Toolbar")
    }

    @ViewBuilder
    func iconButton(
        _ identifier: String, label: String, help: String, systemImage: String,
        shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void
    ) -> some View {
        let button = GlassIconButton(systemImage: systemImage, action: action)
            .help(help)
            .disabled(!hasResult)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
        if let shortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}

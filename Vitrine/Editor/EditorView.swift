import AppKit
import SwiftUI

/// The editor window: code input + live preview + export (CS-005/006/007/008).
struct EditorView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                CodeEditorView(
                    text: $settings.config.code,
                    language: settings.config.language,
                    theme: settings.config.theme,
                    fontName: settings.config.fontName,
                    fontSize: settings.config.fontSize
                )
            }
            .frame(minWidth: 320)

            ScrollView([.horizontal, .vertical]) {
                SnapshotCanvas(config: settings.config)
                    .padding()
            }
            .frame(minWidth: 440)
            .background(Color.black.opacity(0.18))
        }
        .frame(minWidth: 820, minHeight: 480)
        .toolbar { toolbar }
    }

    private var header: some View {
        HStack {
            Picker("Language", selection: $settings.config.language) {
                ForEach(settings.orderedLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            .accessibilityLabel("Language")
            Spacer()
        }
        .padding(8)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                ExportManager.copyToPasteboard(
                    settings.config, scale: CGFloat(settings.exportScale))
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .help("Render and copy the image to the clipboard")
            .accessibilityLabel("Copy image to clipboard")

            Button {
                ExportManager.saveToFile(
                    settings.config, scale: CGFloat(settings.exportScale),
                    format: settings.exportFormat)
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .help("Render and save the image as a file")
            .accessibilityLabel("Save image to a file")

            Button(action: share) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share the rendered image")
            .accessibilityLabel("Share image")
        }
    }

    private func share() {
        guard
            let image = ExportManager.renderNSImage(
                settings.config, scale: CGFloat(settings.exportScale)),
            let view = NSApp.keyWindow?.contentView
        else { return }
        ShareManager.share(image, relativeTo: view)
    }
}

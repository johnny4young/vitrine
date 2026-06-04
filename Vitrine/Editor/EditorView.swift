import SwiftUI

/// The editor window: code input + live preview + export (CS-005/006/007).
struct EditorView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                CodeEditorView(
                    text: $settings.config.code,
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
                ForEach(Language.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 180)
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

            Button {
                ExportManager.saveToFile(settings.config, scale: CGFloat(settings.exportScale))
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .help("Render and save the image as a PNG")
        }
    }
}

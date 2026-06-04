import AppKit
import SwiftUI

/// The editor window: code input + live preview + export (CS-005/006/007/008).
struct EditorView: View {
    @EnvironmentObject private var settings: AppSettings

    /// Whether the optional metadata header editor is expanded. Collapsed by
    /// default so the editor stays focused on code; it auto-expands when the
    /// config already carries header content so a restored snapshot's fields are
    /// visible (CS-022).
    @State private var showMetadata = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider()
                metadataBar
                CodeEditorView(
                    text: $settings.config.code,
                    language: settings.config.language,
                    theme: settings.config.theme,
                    fontName: settings.config.fontName,
                    fontSize: settings.config.fontSize,
                    fontLigatures: settings.config.fontLigatures
                )
                .overlay {
                    if settings.config.code.isEmpty {
                        // The overlay is non-interactive except for its "Paste
                        // Code" button (see EmptyStateView): a click anywhere
                        // else falls through to the text view so the caret can
                        // land and the user can start typing — matching the
                        // "paste or type" affordance the copy promises.
                        EmptyStateView(
                            title: "Nothing to show yet",
                            message: "Paste code to turn it into a beautiful image.",
                            actionTitle: "Paste Code",
                            action: pasteFromClipboard
                        )
                    }
                }
            }
            .frame(minWidth: 320)

            ScrollView([.horizontal, .vertical]) {
                // The preview mirrors the active preset's framing, so selecting a
                // fixed-size preset (e.g. OpenGraph 1200×630) updates the canvas
                // immediately (CS-020).
                SnapshotCanvas(config: settings.config, fixedSize: settings.effectiveFixedSize)
                    .padding(Brand.Spacing.lg)
            }
            .frame(minWidth: 440)
            .background(Brand.Palette.stage.color)
        }
        .frame(minWidth: 820, minHeight: 480)
        .toolbar { toolbar }
        .accessibilityIdentifier("editor-root")
    }

    private var header: some View {
        HStack {
            Picker("Language", selection: $settings.config.language) {
                ForEach(settings.orderedLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(maxWidth: Brand.Layout.headerControlMaxWidth)
            .accessibilityLabel("Language")
            .accessibilityIdentifier("language-picker")
            Spacer()
            // A leading SF Symbol gives this otherwise bare popup an
            // at-a-glance affordance: the adjacent Language popup self-identifies
            // via its values ("Swift"/"Python"), but a value like "Custom" does
            // not read as a destination/sizing control on its own. The icon is
            // decorative for VoiceOver — the picker already carries the
            // "Destination preset" label.
            HStack(spacing: Brand.Spacing.xs) {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                DestinationPresetPicker(settings: settings)
                    .labelsHidden()
            }
            .frame(maxWidth: Brand.Layout.headerControlMaxWidth)
        }
        .padding(Brand.Spacing.xs)
    }

    /// A collapsible inline editor for the optional metadata header (CS-022),
    /// reusing the same labeled fields as the Style pane so metadata can be entered
    /// right where the user is editing code. Collapsed by default; a trailing
    /// `Divider` separates it from the code editor only while expanded so the
    /// editor chrome stays minimal when it is closed.
    @ViewBuilder
    private var metadataBar: some View {
        DisclosureGroup(isExpanded: $showMetadata) {
            Form {
                MetadataFields(settings: settings)
            }
            .formStyle(.columns)
            .padding(.top, Brand.Spacing.xs)
        } label: {
            Label("Header", systemImage: "text.alignleft")
                .font(.subheadline)
        }
        .help("Show optional header fields — filename, title, caption, language badge")
        .padding(.horizontal, Brand.Spacing.sm)
        .padding(.vertical, Brand.Spacing.xs)
        .accessibilityIdentifier("metadata-disclosure")
        .onAppear { showMetadata = !settings.config.metadata.isEmpty }
        if showMetadata {
            Divider()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                ExportManager.copyToPasteboard(
                    settings.config, scale: CGFloat(settings.effectiveExportScale),
                    fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile)
            } label: {
                Label("Copy", systemImage: "doc.on.clipboard")
            }
            .help("Render and copy the image to the clipboard")
            .accessibilityLabel("Copy image to clipboard")
            .accessibilityIdentifier("copy-button")

            Button {
                ExportManager.saveToFile(
                    settings.config, scale: CGFloat(settings.effectiveExportScale),
                    format: settings.exportFormat, fixedSize: settings.effectiveFixedSize,
                    profile: settings.colorProfile)
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .help("Render and save the image as a file")
            .accessibilityLabel("Save image to a file")
            .accessibilityIdentifier("save-button")

            Button(action: share) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share the rendered image")
            .accessibilityLabel("Share image")
            .accessibilityIdentifier("share-button")
        }
    }

    /// Fills the editor from the clipboard, detecting the language so the empty
    /// state's "Paste Code" action produces an immediately useful preview.
    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        settings.config.code = text
        settings.config.language = LanguageDetector.detect(text)
    }

    private func share() {
        guard
            let image = ExportManager.renderNSImage(
                settings.config, scale: CGFloat(settings.effectiveExportScale),
                fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile),
            let view = NSApp.keyWindow?.contentView
        else { return }
        ShareManager.share(image, relativeTo: view)
    }
}

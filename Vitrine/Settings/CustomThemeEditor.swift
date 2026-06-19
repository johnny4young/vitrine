import AppKit
import SwiftUI

/// A mutable, `Color`-backed draft of a custom-theme palette, used by
/// `CustomThemeEditor` so the color wells bind to live SwiftUI colors and the
/// preview updates as the user edits (CS-031).
///
/// It is `Identifiable` so it can drive a `.sheet(item:)`, and carries an optional
/// `editingID` so the same editor handles both "new" and "edit an existing theme".
/// The draft is the editable form; `palette()` resolves it back to a validated
/// `ThemePalette` for saving.
final class CustomThemeDraft: Identifiable, ObservableObject {
    let id = UUID()
    /// The id of the theme being edited, or `nil` when creating a new one.
    let editingID: String?
    @Published var name: String
    @Published var background: Color
    @Published var foreground: Color
    @Published var keyword: Color
    @Published var string: Color
    @Published var comment: Color
    @Published var number: Color
    @Published var type: Color
    @Published var function: Color
    @Published var variable: Color
    @Published var attribute: Color

    /// A new draft seeded with a clean, legible dark default palette so the editor
    /// opens on a sensible starting point rather than all-black wells.
    init() {
        self.editingID = nil
        self.name = "My Theme"
        self.background = Color(hex: "#1E1E1E")
        self.foreground = Color(hex: "#D4D4D4")
        self.keyword = Color(hex: "#C586C0")
        self.string = Color(hex: "#CE9178")
        self.comment = Color(hex: "#6A9955")
        self.number = Color(hex: "#B5CEA8")
        self.type = Color(hex: "#4EC9B0")
        self.function = Color(hex: "#DCDCAA")
        self.variable = Color(hex: "#9CDCFE")
        self.attribute = Color(hex: "#569CD6")
    }

    /// A draft seeded from an existing theme's palette for editing.
    init(editingID: String, name: String, palette: ThemePalette) {
        self.editingID = editingID
        self.name = name
        self.background = palette.background.color
        self.foreground = palette.foreground.color
        self.keyword = palette.keyword.color
        self.string = palette.string.color
        self.comment = palette.comment.color
        self.number = palette.number.color
        self.type = palette.type.color
        self.function = palette.function.color
        self.variable = palette.variable.color
        self.attribute = palette.attribute.color
    }

    /// Resolves the draft to a validated `ThemePalette`. Each `Color` is captured in
    /// fixed sRGB and round-tripped through `HexColor`, so the saved palette is the
    /// same deterministic value the file schema stores.
    func palette() -> ThemePalette {
        ThemePalette(
            background: background.hexColor,
            foreground: foreground.hexColor,
            keyword: keyword.hexColor,
            string: string.hexColor,
            comment: comment.hexColor,
            number: number.hexColor,
            type: type.hexColor,
            function: function.hexColor,
            variable: variable.hexColor,
            attribute: attribute.hexColor)
    }
}

/// A sheet for creating or editing a custom theme with a live preview before saving
/// (CS-031 "theme preview appears before saving").
///
/// The color wells edit a `CustomThemeDraft`; the preview re-renders the current
/// code (or a sample snippet) with the draft palette on every change, so the user
/// sees the exact syntax coloring before committing. Saving resolves the draft to a
/// validated `ThemePalette` and hands it to the store.
struct CustomThemeEditor: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var draft: CustomThemeDraft
    let onSave: (String, ThemePalette) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text(draft.editingID == nil ? "New Custom Theme" : "Edit Custom Theme")
                .font(.headline)

            // The form and preview scroll; the title above and the action row below
            // stay pinned so Cancel/Save are always reachable. This mirrors the
            // AboutSettingsView fix (a ScrollView with a minHeight) so the editor
            // grows and scrolls at large Dynamic Type sizes instead of clipping the
            // controls or the action buttons.
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    Form {
                        TextField("Name", text: $draft.name)
                            .accessibilityIdentifier("custom-theme-name-field")

                        Section("Base") {
                            ColorPicker(
                                "Background", selection: $draft.background, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-background")
                            ColorPicker(
                                "Foreground", selection: $draft.foreground, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-foreground")
                        }
                        Section("Syntax") {
                            ColorPicker(
                                "Keywords", selection: $draft.keyword, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-keyword")
                            ColorPicker("Strings", selection: $draft.string, supportsOpacity: false)
                                .accessibilityIdentifier("custom-theme-color-string")
                            ColorPicker(
                                "Comments", selection: $draft.comment, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-comment")
                            ColorPicker("Numbers", selection: $draft.number, supportsOpacity: false)
                                .accessibilityIdentifier("custom-theme-color-number")
                            ColorPicker("Types", selection: $draft.type, supportsOpacity: false)
                                .accessibilityIdentifier("custom-theme-color-type")
                            ColorPicker(
                                "Functions", selection: $draft.function, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-function")
                            ColorPicker(
                                "Variables", selection: $draft.variable, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-variable")
                            ColorPicker(
                                "Attributes", selection: $draft.attribute, supportsOpacity: false
                            )
                            .accessibilityIdentifier("custom-theme-color-attribute")
                        }
                    }
                    .formStyle(.grouped)
                    .frame(minHeight: 280)

                    Text("Preview")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    previewImage
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 160)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft.name, draft.palette())
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("save-custom-theme-button")
            }
        }
        .padding()
        .frame(width: 460)
        .frame(minHeight: 520)
        .accessibilityIdentifier("custom-theme-editor")
    }

    /// The live preview: the current code (or a sample) rendered with the draft
    /// palette, so the syntax coloring is visible before saving.
    @ViewBuilder private var previewImage: some View {
        if let image = renderedPreview {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
                .accessibilityIdentifier("custom-theme-preview")
        } else {
            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                .fill(draft.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                        .strokeBorder(Brand.Palette.border.color)
                )
                .overlay(
                    Text("Preview unavailable")
                        .font(.footnote)
                        // The fill is the user-chosen draft background, so the label
                        // must read against *that* color, not the app's appearance:
                        // `.secondary` resolves to the environment scheme and goes
                        // invisible on a light draft in Dark Mode (or the inverse).
                        // The draft's own foreground is the color picked to sit on
                        // this background, so it stays legible for any draft palette.
                        .foregroundStyle(draft.foreground)
                )
                .accessibilityIdentifier("custom-theme-preview-unavailable")
        }
    }

    private var renderedPreview: NSImage? {
        var config = settings.config
        config.theme = Theme(
            id: "custom.preview", displayName: draft.name, palette: draft.palette())
        if config.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.code = "func greet(_ name: String) {\n    print(\"Hello, \\(name)!\")\n}"
        }
        return ExportManager.renderNSImage(config, scale: 2, profile: settings.colorProfile)
    }
}

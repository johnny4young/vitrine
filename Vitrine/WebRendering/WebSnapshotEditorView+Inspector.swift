import SwiftUI

/// The Web Snapshot composer's inspector: source mode, the URL/HTML input, output
/// options, and the primary capture/render action.
extension WebSnapshotEditorView {
    // MARK: - Inspector

    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xl - 8) {
                modeSection
                inputSection
                optionsSection
                captureSection
            }
            .padding(.top, 18)
            .padding(.horizontal, VitrineTokens.Spacing.xl - 12)
            .padding(.bottom, VitrineTokens.Spacing.lg)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VitrineTokens.Line.border)
                .frame(width: Brand.Stroke.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
        .accessibilityIdentifier("web-snapshot-inspector")
    }

    var modeSection: some View {
        section("Source") {
            TokenSegmentedPicker(
                options: [
                    (WebInputMode.url, Text(verbatim: "URL")),
                    (WebInputMode.html, Text(verbatim: "HTML")),
                ],
                selection: $model.mode,
                fillsWidth: true,
                optionIdentifiers: ["web-snapshot-mode-url", "web-snapshot-mode-html"]
            )
            .accessibilityLabel("Source")
            .accessibilityIdentifier("web-snapshot-mode-picker")
        }
    }

    @ViewBuilder var inputSection: some View {
        switch model.mode {
        case .url:
            section("URL") {
                InspectorTextField(
                    prompt: Text(verbatim: "https://example.com"), text: $model.urlText,
                    onSubmit: attemptCapture, disablesAutocorrection: true
                )
                .accessibilityIdentifier("web-snapshot-url-field")
                if !NetworkCapability.isURLCaptureEnabled {
                    Text(
                        "URL capture runs only in the direct-download build. HTML rendering works here."
                    )
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .html:
            section("HTML") {
                InspectorCodeField(
                    text: $model.htmlText, placeholder: "<h1>Hello</h1>", height: 160
                )
                .accessibilityIdentifier("web-snapshot-html-editor")
            }
        }
    }

    var optionsSection: some View {
        section("Output") {
            WebCaptureControls(settings: settings)
        }
    }

    var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GradientCTAButton {
                Image(systemName: model.mode == .url ? "camera.viewfinder" : "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.mode == .url ? "Capture" : "Render")
            } action: {
                attemptCapture()
            }
            .disabled(!model.canRender || model.isRendering)
            // ⌘Return triggers the primary action, the macOS convention for a window's
            // default button.
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("web-snapshot-capture-button")

            if model.mode == .url {
                Label {
                    Text("Loads the page locally in WebKit — nothing is sent to a server.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Chrome helpers

    func section<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            TokenGroupLabel(title: Text(title))
            content()
        }
    }
}

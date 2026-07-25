import SwiftUI

/// The Web Snapshot composer's inspector: source mode, the URL/HTML input, output
/// options, and the primary capture/render action.
extension WebSnapshotEditorView {
    // MARK: - Inspector

    var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xl - 12) {
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
        .tint(VitrineTokens.Accent.system)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
        .accessibilityIdentifier("web-snapshot-inspector")
    }

    var modeSection: some View {
        InspectorSection(title: Text("Source")) {
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
            InspectorSection(title: Text(verbatim: "URL")) {
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
                signInRow
            }
        case .html:
            InspectorSection(title: Text(verbatim: "HTML")) {
                InspectorCodeField(
                    text: $model.htmlText, placeholder: "<h1>Hello</h1>", height: 160
                )
                .accessibilityIdentifier("web-snapshot-html-editor")
            }
        }
    }

    /// Signing in to the site before capturing it.
    ///
    /// A page behind a login is the one case the offscreen capture cannot solve on its
    /// own: it rasterizes, it never types. This opens a real browser window on the same
    /// data store the capture reads, so a session established here is the session the
    /// capture sends. Shown only once the requirements are met, and otherwise replaced by
    /// the single thing the user has to fix — see `WebSessionAvailability`.
    @ViewBuilder private var signInRow: some View {
        let blocker = WebSessionAvailability.blocker(
            isCaptureEnabled: NetworkCapability.isURLCaptureEnabled,
            usesLoggedInSession: settings.webCapture.usesLoggedInSession,
            urlText: model.urlText,
            allowsLoopback: settings.webCapture.allowsLoopbackCapture)

        switch blocker {
        case .none:
            Button {
                signInToCaptureSite()
            } label: {
                if let site = WebSessionAvailability.siteLabel(
                    for: model.urlText,
                    allowsLoopback: settings.webCapture.allowsLoopbackCapture)
                {
                    Text("Sign in to \(site)…")
                } else {
                    Text("Sign in…")
                }
            }
            .buttonStyle(.link)
            .font(.system(size: VitrineTokens.FontSize.caption))
            .accessibilityHint(
                "Opens a browser window so this capture can include a signed-in page"
            )
            .accessibilityIdentifier("web-snapshot-sign-in-button")
        case .sessionNotEnabled:
            // Actionable, so say where the switch is rather than only that it is off.
            Text(
                "To capture a page behind a login, turn on “Use my logged-in session” in Settings ▸ Input."
            )
            .font(.system(size: VitrineTokens.FontSize.caption))
            .foregroundStyle(VitrineTokens.Text.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("web-snapshot-sign-in-hint")
        case .captureUnavailable, .noValidURL:
            // Both are already explained where they arise: the build note above, and the
            // empty/invalid field the user is still typing into.
            EmptyView()
        }
    }

    var optionsSection: some View {
        InspectorSection(title: Text("Output")) {
            WebCaptureControls(settings: settings, collapsesAdvanced: true)
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
}

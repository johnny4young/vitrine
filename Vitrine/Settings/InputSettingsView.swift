import SwiftUI

/// Input pane: URL handling (CS-010 · Input) and the web URL-capture viewport and
/// wait strategy (CS-044).
struct InputSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsPaneScroll {
            TokenGroup(title: Text("Pasting")) {
                TokenRow(
                    label: Text("Re-indent code on paste"),
                    caption: Text("Undo with ⌘Z, or format anytime with ⌥⌘F")
                ) {
                    Toggle("Re-indent code on paste", isOn: $settings.reindentOnPaste)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("reindent-on-paste-toggle")
                }
                TokenRow(
                    label: Text("Treat copied URLs as a screenshot target"),
                    caption: Text("When off, a copied URL is rendered as text")
                ) {
                    Toggle(
                        "Treat copied URLs as a screenshot target",
                        isOn: $settings.treatURLsAsScreenshot
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            TokenGroup(title: Text("Web capture")) {
                WebCaptureControls(settings: settings)
                WebCaptureConsentRow(settings: settings)
            }
        }
        .accessibilityIdentifier("settings-input-pane")
    }
}

/// The Web-capture transparency + consent row (CS-045): states plainly what URL
/// capture does to the network, reflects the first-use consent state, and lets the
/// user revoke it (re-arming the disclosure) — or shows that capture is unavailable on
/// this build. The network model lives here so it is always consultable in Settings,
/// not only at the first-use sheet.
struct WebCaptureConsentRow: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TokenRow(
            label: Text("Network use"),
            caption: Text(
                "URL capture loads the page you ask for locally in WebKit — no Vitrine server, no analytics. Your code never leaves your Mac."
            )
        ) {
            trailing
        }
    }

    @ViewBuilder private var trailing: some View {
        if !NetworkCapability.isURLCaptureEnabled {
            Text("Direct-download only")
                .font(.system(size: VitrineTokens.FontSize.subhead))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        } else if settings.webCapture.consentGiven {
            Button("Revoke") {
                settings.webCapture.consentGiven = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(VitrineTokens.Accent.system)
            .accessibilityIdentifier("web-capture-revoke-consent-button")
        } else {
            Text("Not used yet")
                .font(.system(size: VitrineTokens.FontSize.subhead))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
    }
}

/// The web URL-capture viewport, capture mode, and wait-strategy controls (CS-044).
///
/// URL capture is a Product Phase 2 feature gated on the network entitlement, so
/// these controls set the policy a future URL capture will use; the footer states
/// that plainly. Choosing the viewport, the visible-vs-full-page mode, and the wait
/// strategy here is what makes a web screenshot predictable across sites. The
/// width/height fields appear only for a custom viewport, and the seconds field only
/// for a timed wait strategy, so the surface stays as small as the chosen options.
struct WebCaptureControls: View {
    @Bindable var settings: AppSettings

    /// When true, the capture-mode / wait-strategy controls fold into an
    /// `InspectorDisclosure` so the Web Snapshot inspector leads with the viewport
    /// selection; Settings passes the default `false` and shows every row inline.
    var collapsesAdvanced = false
    @State private var showAdvanced = false

    var body: some View {
        viewportsRow
        if settings.webCapture.viewports.contains(.custom) {
            widthRow
            heightRow
        }
        if collapsesAdvanced {
            InspectorDisclosure(
                label: Text("Capture options"), identifier: "web-advanced-disclosure",
                isExpanded: $showAdvanced
            ) {
                captureModeRow
                waitRow
                if settings.webCapture.waitKind != .domContentLoaded { extraWaitRow }
                loggedInSessionRow
            }
        } else {
            captureModeRow
            waitRow
            if settings.webCapture.waitKind != .domContentLoaded { extraWaitRow }
            loggedInSessionRow
        }
    }

    /// Opt-in to capturing with your existing cookies/logged-in session (CS-043), for
    /// pages behind a login. Off by default — the private per-render store sends no
    /// cookies — so this is a deliberate, privacy-widening choice the caption spells out.
    private var loggedInSessionRow: some View {
        TokenRow(
            label: Text("Use my logged-in session"),
            caption: Text(
                "Capture pages behind a login by sending your existing cookies. Off by default; your code and captures still stay on your Mac."
            )
        ) {
            Toggle("Use my logged-in session", isOn: $settings.webCapture.usesLoggedInSession)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityIdentifier("web-logged-in-session-toggle")
        }
    }

    private var viewportsRow: some View {
        // Full-width (not a TokenRow) so every viewport chip wraps into view in the narrow
        // inspector instead of overflowing off the right edge; the label sits above the
        // chips, matching the theme/font chip pickers.
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
            Text("Viewports")
                .font(.system(size: VitrineTokens.FontSize.body))
                .foregroundStyle(VitrineTokens.Text.primary)
            FlowLayout(
                spacing: VitrineTokens.Spacing.xxs + 2, lineSpacing: VitrineTokens.Spacing.xxs + 2
            ) {
                ForEach(WebSnapshotConfig.ViewportPreset.Kind.allCases, id: \.self) { kind in
                    viewportChip(kind)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Viewports")
            .accessibilityIdentifier("web-viewport-picker")
            Text(viewportsFooter)
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
    }

    private var widthRow: some View {
        TokenRow(label: Text("Width")) {
            Stepper(
                value: $settings.webCapture.customViewportWidth,
                in: customDimensionRange, step: 10
            ) {
                Text(verbatim: "\(settings.webCapture.customViewportWidth) pt")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }
            .accessibilityLabel("Width")
            .accessibilityIdentifier("web-custom-width-stepper")
        }
    }

    private var heightRow: some View {
        TokenRow(label: Text("Height")) {
            Stepper(
                value: $settings.webCapture.customViewportHeight,
                in: customDimensionRange, step: 10
            ) {
                Text(verbatim: "\(settings.webCapture.customViewportHeight) pt")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }
            .accessibilityLabel("Height")
            .accessibilityIdentifier("web-custom-height-stepper")
        }
    }

    private var captureModeRow: some View {
        TokenRow(label: Text("Capture"), caption: Text(captureFooter)) {
            TokenSegmentedPicker(
                options: [
                    (WebSnapshotConfig.CaptureMode.visibleViewport, Text("Visible")),
                    (.fullPage, Text("Full page")),
                ],
                selection: $settings.webCapture.captureMode
            )
            .accessibilityLabel("Capture")
            .accessibilityIdentifier("web-capture-mode-picker")
        }
    }

    private var waitRow: some View {
        TokenRow(label: Text("Wait until"), caption: Text(waitFooter)) {
            TokenSegmentedPicker(
                options: [
                    (WebSnapshotConfig.WaitStrategy.Kind.domContentLoaded, Text("Loaded")),
                    (.networkQuiet, Text("Idle")),
                    (.fixedDelay, Text("Delay")),
                ],
                selection: $settings.webCapture.waitKind
            )
            .accessibilityLabel("Wait until")
            .accessibilityIdentifier("web-wait-strategy-picker")
        }
    }

    private var extraWaitRow: some View {
        TokenRow(label: Text("Extra wait")) {
            Stepper(value: $settings.webCapture.waitSeconds, in: waitSecondsRange, step: 1) {
                Text(waitSecondsLabel)
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }
            .accessibilityLabel("Extra wait")
            .accessibilityIdentifier("web-wait-seconds-stepper")
        }
    }

    /// The segment label for a viewport kind — the handoff's short names. The
    /// custom segment reads "Custom…" rather than echoing the stored size,
    /// because the size is set by the rows below it.
    private func viewportSegmentLabel(for kind: WebSnapshotConfig.ViewportPreset.Kind) -> Text {
        switch kind {
        case .openGraph: Text("Social")
        case .desktop: Text("Desktop")
        case .fullHD: Text(verbatim: "Full HD")
        case .mobile: Text("Phone")
        case .custom: Text("Custom…")
        }
    }

    /// A selectable chip for one viewport kind in the multi-capture set (CS-044).
    /// Toggling adds/removes the kind in `settings.webCapture.viewports`; the last selected
    /// kind cannot be removed, so a capture always has at least one size.
    private func viewportChip(_ kind: WebSnapshotConfig.ViewportPreset.Kind) -> some View {
        let isOn = settings.webCapture.viewports.contains(kind)
        return Button {
            toggleViewport(kind)
        } label: {
            viewportSegmentLabel(for: kind)
                .font(.system(size: VitrineTokens.FontSize.subhead, weight: .medium))
                // Match the segmented control's segments: keep each chip's label on one
                // line at its natural width, so a narrow trailing column never breaks
                // "Desktop" into "De / skt / op". The chips hug their content and the
                // TokenRow label (maxWidth: .infinity) yields the space they need.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(
                    isOn ? VitrineTokens.Accent.systemContrast : VitrineTokens.Text.secondary
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isOn ? VitrineTokens.Accent.system : Color.clear))
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Color.clear : VitrineTokens.Line.border, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewportSegmentLabel(for: kind))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("web-viewport-chip-\(kind.rawValue)")
    }

    /// Toggles `kind` in the multi-capture viewport set, keeping it ordered and never
    /// empty (the last selected kind stays), and syncing the single `webCapture.viewportKind`
    /// to the primary selection so the back-compat single-viewport path stays valid.
    private func toggleViewport(_ kind: WebSnapshotConfig.ViewportPreset.Kind) {
        var set = settings.webCapture.viewports
        if let index = set.firstIndex(of: kind) {
            guard set.count > 1 else { return }
            set.remove(at: index)
        } else {
            set.append(kind)
        }
        settings.webCapture.viewports = set
        settings.webCapture.viewportKind = set.first ?? .openGraph
    }

    /// The footer under the viewport chips: a multi-selection captures every chosen
    /// size in one pass; a single selection behaves like the original single capture.
    private var viewportsFooter: String {
        settings.webCapture.viewports.count > 1
            ? String(localized: "Captures every selected size in one pass.")
            : String(localized: "Pick one or more sizes to capture.")
    }

    private var waitSecondsLabel: String {
        // One interpolated key whose singular/plural is chosen by the catalog's
        // plural variations (CS-047), rather than a Swift `== 1` branch — so every
        // locale's own plural categories are honored, not just one/other.
        String(localized: "\(settings.webCapture.waitSeconds) seconds")
    }

    private var captureFooter: String {
        switch settings.webCapture.captureMode {
        case .visibleViewport:
            String(
                localized:
                    "Captures exactly the viewport size. URL capture loads the page locally in WebKit on this Mac."
            )
        case .fullPage:
            String(
                localized:
                    "Captures the whole page at the viewport width, down to a bounded maximum height. Lazy-loaded content is given a chance to appear by scrolling the page a limited number of times."
            )
        }
    }

    private var waitFooter: String {
        switch settings.webCapture.waitKind {
        case .domContentLoaded:
            String(localized: "Snapshots as soon as the page finishes loading.")
        case .fixedDelay:
            String(
                localized:
                    "Waits a fixed time after the page loads before snapshotting, so content added by scripts has time to appear."
            )
        case .networkQuiet:
            String(
                localized:
                    "Waits, up to the chosen time, for the page to stop loading content before snapshotting. Best effort: a page that never goes quiet is captured when the time runs out."
            )
        }
    }

    private var customDimensionRange: ClosedRange<Int> {
        WebSnapshotConfig.ViewportPreset.customDimensionRange
    }

    private var waitSecondsRange: ClosedRange<Int> { WebDefaults.waitSecondsRange }
}

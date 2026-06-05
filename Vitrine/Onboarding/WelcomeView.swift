import AppKit
import KeyboardShortcuts
import SwiftUI

/// The first-run quick-start (CS-035).
///
/// A single compact, skippable window that teaches the core loop — *copy code →
/// press the hotkey → paste the image* — lets the user pick a starting style,
/// optionally record a hotkey and enable launch-at-login, and run a **sample
/// capture that needs no clipboard content**. It is shown at most once per defaults
/// suite (`AppSettings.hasSeenWelcome`); a clear "Get started" / "Skip" dismisses
/// it and unlocks nothing — every feature is already reachable from the menu bar.
///
/// The copy here is deliberately aligned with the privacy posture documented in
/// `docs/ARCHITECTURE.md` and the README: rendering is fully local, with no network,
/// screen recording, or Accessibility permission. That promise is shown *before* the
/// first capture so the user learns it up front.
struct WelcomeView: View {
    @ObservedObject var settings: AppSettings

    /// Closes the hosting window. Injected by the window controller so the view has
    /// no dependency on how it is presented (window vs. sheet vs. preview).
    var onDismiss: () -> Void

    /// The launch-at-login state is mirrored locally (like the General settings
    /// pane) so the toggle reflects the system registration without binding through
    /// `AppSettings`. It is offered, never forced (CS-035).
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    /// The sample capture's outcome, surfaced inline so the user sees that the loop
    /// worked without leaving the window. `nil` until the user runs it.
    @State private var sampleStatus: SampleStatus?

    /// The chosen starting style preset's id (CS-035). Defaults to the first
    /// built-in so the picker always shows a concrete choice; changing it applies
    /// that preset to the live config, and that change alone is what writes the
    /// user's style — a returning user's existing style is never overwritten just by
    /// opening the quick-start.
    @State private var selectedStyleID: String = StylePreset.builtIns.first?.id ?? ""

    /// Outcome of the in-window sample capture, for an inline status line.
    private enum SampleStatus: Equatable {
        case copied
        case rendered
        case failed

        /// Localized through the String Catalog (CS-047).
        var message: String {
            switch self {
            case .copied:
                String(
                    localized: "Done — the sample image is on your clipboard. Paste it anywhere.")
            case .rendered:
                String(localized: "Done — the sample image was rendered with your current style.")
            case .failed:
                String(localized: "That sample could not be rendered. Your settings are unchanged.")
            }
        }

        var systemImage: String {
            switch self {
            case .copied, .rendered: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .copied, .rendered: Brand.Palette.accent.color
            case .failed: .orange
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            header
            stepRow
            sampleCard
            privacyBadge
            setupControls
            Spacer(minLength: 0)
            footer
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 560)
        .frame(minHeight: 560)
        .background(stageBackground)
        .accessibilityIdentifier("welcome-view")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: Brand.Spacing.md) {
            BrandMark(size: 40)
            VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                Text("Welcome to Vitrine")
                    .font(.title2.bold())
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                Text("Turn code into beautiful images, right from your menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.Palette.textSecondary.color)
            }
        }
        // Read the identity and tagline as a single VoiceOver announcement; the mark
        // itself is already decorative (hidden) inside `BrandMark`.
        .accessibilityElement(children: .combine)
    }

    /// The three-step core loop, shown as labeled chips with connectors so the user
    /// learns "copy code → press hotkey → paste image" at a glance (CS-035).
    private var stepRow: some View {
        HStack(alignment: .top, spacing: Brand.Spacing.xs) {
            stepChip(
                index: 1, symbol: "doc.on.clipboard", title: "Copy code", caption: "from anywhere")
            stepConnector
            stepChip(index: 2, symbol: "command", title: "Press the hotkey", caption: hotkeyCaption)
            stepConnector
            stepChip(
                index: 3, symbol: "photo.on.rectangle", title: "Paste the image",
                caption: "into your doc")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How it works: copy code, press the hotkey, paste the image.")
    }

    private func stepChip(
        index: Int, symbol: String, title: LocalizedStringKey, caption: LocalizedStringKey
    ) -> some View {
        VStack(spacing: Brand.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Brand.Gradient.signature)
                .frame(height: 26)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Brand.Palette.textPrimary.color)
                .multilineTextAlignment(.center)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Brand.Palette.textSecondary.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Brand.Spacing.sm)
        .padding(.horizontal, Brand.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                .fill(Brand.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                .strokeBorder(Brand.Palette.border.color, lineWidth: Brand.Stroke.hairline)
        )
        .accessibilityElement(children: .combine)
        // Built from localized `Text` pieces so the spoken label is localized too
        // (a `LocalizedStringKey` can't be interpolated into another) (CS-047).
        .accessibilityLabel(
            Text("Step \(index): ") + Text(title) + Text(verbatim: ", ") + Text(caption))
    }

    private var stepConnector: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Brand.Palette.textSecondary.color)
            .padding(.top, Brand.Spacing.md)
            .accessibilityHidden(true)
    }

    /// A live sample: the placeholder snippet, a style picker, and a one-click
    /// capture that needs **no clipboard content** (CS-035 acceptance: "run a sample
    /// capture without needing external clipboard content").
    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Try it now")
                    .font(.headline)
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                Spacer()
                stylePicker
            }

            Text(EditorPreview.sampleCode)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Brand.Palette.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Brand.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Brand.Radius.sm, style: .continuous)
                        .fill(.quaternary)
                )
                .accessibilityLabel("Sample code snippet")
                .accessibilityIdentifier("welcome-sample-snippet")

            HStack(spacing: Brand.Spacing.sm) {
                Button(action: runSampleCapture) {
                    Label("Try a sample capture", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("welcome-sample-capture-button")

                Button("Open the editor") {
                    EditorWindowController.shared.showWithSample()
                }
                .accessibilityIdentifier("welcome-open-editor-button")
            }

            if let sampleStatus {
                Label(sampleStatus.message, systemImage: sampleStatus.systemImage)
                    .font(.callout)
                    .foregroundStyle(sampleStatus.tint)
                    .accessibilityIdentifier("welcome-sample-status")
            }
        }
        .padding(Brand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
                .fill(Brand.Surface.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
                .strokeBorder(Brand.Palette.border.color, lineWidth: Brand.Stroke.hairline)
        )
    }

    /// Picks a starting style preset and applies it to the live config so the sample
    /// (and every later capture) reflects it (CS-035 "a style preset choice").
    private var stylePicker: some View {
        Picker("Style", selection: $selectedStyleID) {
            ForEach(StylePreset.builtIns) { preset in
                Text(preset.name).tag(preset.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Pick a starting look. You can fine-tune everything later in the editor.")
        .accessibilityLabel("Starting style")
        .accessibilityIdentifier("welcome-style-picker")
        .onChange(of: selectedStyleID) { _, id in
            if let preset = StylePreset.builtIns.first(where: { $0.id == id }) {
                settings.applyStylePreset(preset)
            }
        }
    }

    /// The local-only privacy promise, shown before the first capture (CS-035). The
    /// wording matches the privacy posture in `docs/ARCHITECTURE.md` and the README.
    private var privacyBadge: some View {
        Label {
            // Long copy lives in the String Catalog under a stable key (CS-047) so
            // it localizes and does not push the source past the line limit.
            Text("welcome.privacy.badge")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.footnote)
        .foregroundStyle(Brand.Palette.textSecondary.color)
        .padding(Brand.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                .fill(Brand.Gradient.signatureWash(opacity: 0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome-privacy-badge")
    }

    /// Optional setup: a hotkey recorder and launch-at-login. Both are offered, not
    /// forced — the user can dismiss the quick-start without setting either (CS-035).
    private var setupControls: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            HStack {
                KeyboardShortcuts.Recorder("Global hotkey:", name: .quickCapture)
                    .accessibilityIdentifier("welcome-hotkey-recorder")
                Spacer()
            }

            Toggle("Launch Vitrine at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("welcome-launch-at-login-toggle")
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLogin.setEnabled(newValue)
                }

            Text("Optional — you can set these any time in Settings.")
                .font(.caption)
                .foregroundStyle(Brand.Palette.textSecondary.color)
        }
    }

    private var footer: some View {
        HStack(spacing: Brand.Spacing.sm) {
            Button("Skip") { finish() }
                .accessibilityIdentifier("welcome-skip-button")
            Spacer()
            Button("Get Started") { finish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome-get-started-button")
        }
    }

    // MARK: - Backing state

    private var stageBackground: some View {
        Brand.Palette.stage.color
    }

    /// The recorded hotkey rendered as a short caption (e.g. "⌃⌘V"), or localized
    /// guidance to set one when none is bound yet, so step 2 stays accurate per user
    /// (CS-035). Returned as a `LocalizedStringKey`: the glyph string is interpolated
    /// (so it is shown verbatim, not looked up) while the fallback prose is localized
    /// through the String Catalog (CS-047).
    private var hotkeyCaption: LocalizedStringKey {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .quickCapture) {
            return "\(shortcut.description)"
        }
        return "set one below"
    }

    // MARK: - Actions

    /// Runs a sample capture from a built-in snippet, bypassing the clipboard so the
    /// user can see the full loop work immediately (CS-035). Uses the same exporter
    /// path as a real capture (`QuickCapture.renderText`), so the result honors the
    /// user's chosen style and auto-copy preference.
    private func runSampleCapture() {
        let result = QuickCapture.renderText(
            EditorPreview.sampleCode, language: .swift, settings: settings)
        switch result.outcome {
        case .copied: sampleStatus = .copied
        case .rendered: sampleStatus = .rendered
        // `renderText` only ever produces a copied/rendered outcome; treat anything
        // else defensively as a non-success so the inline status never misleads.
        default: sampleStatus = .failed
        }
    }

    /// Records that the quick-start has been seen (so it never reappears for this
    /// defaults suite) and closes the window (CS-035). Both "Skip" and "Get Started"
    /// route here: skipping is a first-class outcome, not a penalty.
    private func finish() {
        settings.hasSeenWelcome = true
        onDismiss()
    }
}

/// Owns and presents the first-run quick-start window (CS-035).
///
/// Mirrors the other on-demand window controllers (`EditorWindowController`,
/// `RecentsGalleryWindowController`): an AppKit window hosting the SwiftUI view,
/// created lazily and reused. `presentIfFirstRun` is the single entry the app
/// lifecycle calls so the gate ("only once per defaults suite") lives in one place.
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?

    private init() {}

    /// Shows the quick-start only when it has not been seen for the active defaults
    /// suite (CS-035). Returns whether it was presented, which the launch path uses
    /// to decide whether to also open another window.
    @discardableResult
    func presentIfFirstRun(settings: AppSettings = .shared) -> Bool {
        guard !settings.hasSeenWelcome else { return false }
        show(settings: settings)
        return true
    }

    /// Shows (creating if needed) and focuses the quick-start window. Public so a
    /// launch hook can force it open for manual and UI testing.
    func show(settings: AppSettings = .shared) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: WelcomeView(
                    settings: settings,
                    onDismiss: { [weak self] in self?.close() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Welcome to Vitrine")
            // No resize/minimize: the quick-start is a fixed, compact first-run
            // surface, not a working window.
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("welcome-window")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the window without releasing the controller, so a later forced
    /// `show()` can re-present it.
    private func close() {
        window?.close()
    }
}

#if DEBUG
    #Preview("Welcome") {
        WelcomeView(settings: .shared, onDismiss: {})
    }
#endif

import AppKit
import KeyboardShortcuts
import SwiftUI

/// The first-run quick-start.
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
    @Bindable var settings: AppSettings

    /// Closes the hosting window. Injected by the window controller so the view has
    /// no dependency on how it is presented (window vs. sheet vs. preview).
    var onDismiss: () -> Void

    /// The launch-at-login state is mirrored locally (like the General settings
    /// pane) so the toggle reflects the system registration without binding through
    /// `AppSettings`. It is offered, never forced.
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    /// The sample capture's outcome, surfaced inline so the user sees that the loop
    /// worked without leaving the window. `nil` until the user runs it.
    @State private var sampleStatus: SampleStatus?

    /// The chosen starting background. Mirrors the live
    /// config so the swatch row reads the user's current preset; picking one
    /// applies it, and that change alone is what writes the user's style — a
    /// returning user's existing style is never overwritten just by opening the
    /// quick-start.
    @State private var selectedBackground: GradientPreset = .aurora

    /// Outcome of the in-window sample capture, for an inline status line.
    private enum SampleStatus: Equatable {
        case copied
        case rendered
        case failed

        /// Localized through the String Catalog.
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
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xl - 12) {
                stepRow
                sampleCard
                privacyLine
                setupControls
                footer
            }
            .padding(.horizontal, 40)
            .padding(.bottom, VitrineTokens.Spacing.xl)
        }
        .frame(width: 700)
        .background(VitrineTokens.Surface.window)
        .tint(VitrineTokens.Accent.system)
        .accessibilityContainerIdentifier("welcome-view")
        .onAppear {
            if case .gradient(let preset) = settings.config.background {
                selectedBackground = preset
            }
        }
    }

    // MARK: - Sections

    /// The hero: app icon + title over a soft accent radial wash.
    private var hero: some View {
        HStack(alignment: .center, spacing: VitrineTokens.Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xxs) {
                Text("Welcome to Vitrine")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                Text("Turn code into beautiful images, right from your menu bar.")
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }
        }
        .padding(.top, 44)
        .padding(.horizontal, 40)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RadialGradient(
                    colors: [VitrineTokens.Accent.base.opacity(0.22), .clear],
                    center: UnitPoint(x: 0.3, y: 0),
                    startRadius: 0, endRadius: 420)
                RadialGradient(
                    colors: [VitrineTokens.Accent.secondary.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.85, y: 0.2),
                    startRadius: 0, endRadius: 380)
            }
            .accessibilityHidden(true)
        )
        // Read the identity and tagline as a single VoiceOver announcement.
        .accessibilityElement(children: .combine)
    }

    /// The three-step core loop as numbered glass tiles, so the user learns
    /// "copy code → press hotkey → paste image" at a glance.
    private var stepRow: some View {
        HStack(alignment: .top, spacing: VitrineTokens.Spacing.sm) {
            stepTile(
                index: 1, symbol: "doc.on.clipboard", title: "Copy code", caption: "from anywhere")
            stepTile(index: 2, symbol: "command", title: "Press the hotkey", caption: hotkeyCaption)
            stepTile(
                index: 3, symbol: "photo.on.rectangle", title: "Paste the image",
                caption: "into your doc")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How it works: copy code, press the hotkey, paste the image.")
    }

    /// One numbered step tile: a mono index in the corner, a gradient icon
    /// badge, a semibold title, and a secondary caption.
    private func stepTile(
        index: Int, symbol: String, title: LocalizedStringKey, caption: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous)
                .fill(VitrineTokens.Gradients.signature)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                )
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
                .foregroundStyle(VitrineTokens.Text.primary)
                .padding(.top, 2)
            Text(caption)
                .font(.system(size: VitrineTokens.FontSize.subhead))
                .foregroundStyle(VitrineTokens.Text.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, VitrineTokens.Spacing.md)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                .fill(VitrineTokens.Chrome.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
        )
        .overlay(alignment: .topTrailing) {
            Text(verbatim: String(format: "%02d", index))
                .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .padding(.top, VitrineTokens.Spacing.sm)
                .padding(.trailing, 14)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        // Built from localized `Text` pieces so the spoken label is localized too
        // (a `LocalizedStringKey` can't be interpolated into another).
        .accessibilityLabel(
            Text("Step \(index): ") + Text(title) + Text(verbatim: ", ") + Text(caption))
    }

    /// The live sample: a swatch row that restyles the rendered card on the
    /// spot, plus a one-click capture that needs **no clipboard content**.
    private var sampleCard: some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.sm) {
            HStack {
                TokenGroupLabel(title: Text("Try it now"))
                Spacer()
                HStack(spacing: 7) {
                    ForEach(GradientPreset.allCases) { preset in
                        GradientSwatch(preset: preset, isSelected: selectedBackground == preset) {
                            selectedBackground = preset
                            settings.config.background = .gradient(preset)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Background")
                .accessibilityIdentifier("welcome-background-swatches")
            }

            sampleCardImage

            HStack(spacing: VitrineTokens.Spacing.sm) {
                Button(action: runSampleCapture) {
                    Label("Try a sample capture", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("welcome-sample-capture-button")

                Button("Open the editor") {
                    EditorWindowController.shared.showWithSample()
                }
                .accessibilityIdentifier("welcome-open-editor-button")

                Spacer(minLength: 0)

                if let sampleStatus {
                    Label(sampleStatus.message, systemImage: sampleStatus.systemImage)
                        .font(.system(size: VitrineTokens.FontSize.subhead))
                        .foregroundStyle(sampleStatus.tint)
                        .accessibilityIdentifier("welcome-sample-status")
                }
            }
        }
        .padding(VitrineTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                .fill(VitrineTokens.Chrome.tile)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
        )
    }

    /// The sample snippet rendered as a real card on the chosen gradient, so
    /// the first thing the user touches already looks like the product.
    @ViewBuilder private var sampleCardImage: some View {
        if let image = sampleImage {
            HStack {
                Spacer(minLength: 0)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    // An explicit height (not a max) so the card keeps its size
                    // during the window's ideal-size pass — a max-only frame
                    // collapses to zero when the hosting window measures.
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.sm, style: .continuous))
                Spacer(minLength: 0)
            }
            .accessibilityLabel("Sample code snippet")
            .accessibilityIdentifier("welcome-sample-snippet")
        } else {
            Text(EditorPreview.sampleCode)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VitrineTokens.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Brand.Radius.sm, style: .continuous)
                        .fill(.quaternary)
                )
                .accessibilityLabel("Sample code snippet")
                .accessibilityIdentifier("welcome-sample-snippet")
        }
    }

    /// The sample render: the bundled snippet, One Dark, the chosen gradient,
    /// compact padding — preview-only, never the user's live document.
    private var sampleImage: NSImage? {
        var config = SnapshotConfig()
        config.code = EditorPreview.sampleCode
        config.language = .swift
        config.theme = .oneDark
        config.background = .gradient(selectedBackground)
        config.padding = 24
        config.fontSize = 12.5
        return ExportManager.renderNSImage(config, scale: 2, profile: .sRGB)
    }

    /// The local-only privacy promise, shown before the first capture. The
    /// wording matches the privacy posture in `docs/ARCHITECTURE.md` and the README.
    private var privacyLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(VitrineTokens.Text.tertiary)
            // Long copy lives in the String Catalog under a stable key so
            // it localizes and does not push the source past the line limit.
            Text("welcome.privacy.badge")
                .font(.system(size: VitrineTokens.FontSize.subhead))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("welcome-privacy-badge")
    }

    /// Optional setup: a hotkey recorder and launch-at-login. Both are offered, not
    /// forced — the user can dismiss the quick-start without setting either.
    private var setupControls: some View {
        HStack(spacing: VitrineTokens.Spacing.md) {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Text("Global hotkey:")
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Text.primary)
                KeyboardShortcuts.Recorder(for: .quickCapture)
                    .accessibilityLabel("Global hotkey")
                    .accessibilityIdentifier("welcome-hotkey-recorder")
            }

            Spacer(minLength: 0)

            Toggle("Launch Vitrine at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: VitrineTokens.FontSize.body))
                .accessibilityIdentifier("welcome-launch-at-login-toggle")
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLogin.setEnabled(newValue)
                }
        }
        .padding(.vertical, VitrineTokens.Spacing.xs)
    }

    private var footer: some View {
        HStack(spacing: VitrineTokens.Spacing.sm) {
            GhostPillButton(title: Text("Skip")) { finish() }
                .accessibilityIdentifier("welcome-skip-button")
            Spacer()
            GradientCTAButton {
                Text("Get Started")
            } action: {
                finish()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("welcome-get-started-button")
        }
    }

    /// The recorded hotkey rendered as a short caption (e.g. "⌃⌘V"), or localized
    /// guidance to set one when none is bound yet, so step 2 stays accurate per user.
    /// Returned as a `LocalizedStringKey`: the glyph string is interpolated
    /// (so it is shown verbatim, not looked up) while the fallback prose is localized
    /// through the String Catalog.
    private var hotkeyCaption: LocalizedStringKey {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .quickCapture) {
            return "\(shortcut.description)"
        }
        return "set one below"
    }

    // MARK: - Actions

    /// Runs a sample capture from a built-in snippet, bypassing the clipboard so the
    /// user can see the full loop work immediately. Uses the same exporter
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
    /// defaults suite) and closes the window. Both "Skip" and "Get Started"
    /// route here: skipping is a first-class outcome, not a penalty.
    private func finish() {
        settings.hasSeenWelcome = true
        onDismiss()
    }
}

/// Owns and presents the first-run quick-start window.
///
/// Mirrors the other on-demand window controllers (`EditorWindowController`,
/// `RecentsGalleryWindowController`): an AppKit window hosting the SwiftUI view,
/// created lazily and reused. `presentIfFirstRun` is the single entry the app
/// lifecycle calls so the per-defaults-suite gate lives in one place.
@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?

    private init() {}

    /// Shows the quick-start only when it has not been seen for the active defaults
    /// suite. Returns whether it was presented, which the launch path uses
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
            // surface, not a working window. The title bar merges into the
            // hero so the card reads as one surface; the
            // hero's 44 pt top padding clears the traffic lights.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("welcome-window")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        if let window, let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            // Keep the fixed quick-start surface fully inside the visible screen after
            // AppKit assigns it to a display. Mixed-display setups and menu-bar/Dock
            // insets can otherwise leave the footer actions just off-screen even
            // though the window exists.
            window.setFrame(
                WindowFrameSolver.clamp(window.frame, into: visibleFrame), display: true)
            window.makeKeyAndOrderFront(nil)
        }
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

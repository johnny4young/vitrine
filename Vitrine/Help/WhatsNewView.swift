import AppKit
import SwiftUI

/// The version-aware "What's New" surface (CS-049).
///
/// It shows the newest bundled release note (`ReleaseNotes.latest`) — a headline
/// and a short list of highlights — entirely offline. Like onboarding, it is
/// version-gated and skippable: it appears at most once per new version, never on
/// a clean first run (onboarding owns that), and dismissing it records the version
/// as seen so it does not return until the next upgrade.
///
/// The content is static text, so it is keyboard- and VoiceOver-accessible by
/// construction and introduces no motion, respecting Reduced Motion.
struct WhatsNewView: View {
    @ObservedObject var settings: AppSettings

    /// The release note to present. Injected so previews and tests can supply a
    /// fixture; in the app it is `ReleaseNotes.latest`.
    let note: ReleaseNote

    /// Closes the hosting window. Injected by the window controller.
    var onDismiss: () -> Void

    var body: some View {
        // Mirror HelpView: scroll the content so that at large Dynamic Type sizes the
        // header and highlights can overflow without clipping the footer ("Continue" /
        // "Open Help") off-screen, keeping the surface readable and dismissable. The
        // footer is pinned below the scrolling content so the primary actions stay
        // reachable at every text size.
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    header
                    highlights
                }
                .padding(Brand.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
                .padding(.horizontal, Brand.Spacing.xl)
                .padding(.bottom, Brand.Spacing.xl)
        }
        .frame(width: 480)
        .frame(minHeight: 420)
        .background(Brand.Palette.stage.color)
        // Become a container element *before* taking the identifier: on a plain
        // (non-element) view the identifier propagates down and overrides the
        // descendants' own identifiers — the footer buttons would report
        // "whats-new-view" instead of e.g. `whats-new-continue-button`, breaking
        // the CS-049 UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whats-new-view")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: Brand.Spacing.md) {
            BrandMark(size: 40)
            VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                Text("What's New")
                    .font(.title2.bold())
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                Text("\(note.headline) · Version \(note.version)")
                    .font(.subheadline)
                    .foregroundStyle(Brand.Palette.textSecondary.color)
            }
        }
        // The mark is decorative; read the title, headline, and version together.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whats-new-header")
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            ForEach(Array(note.highlights.enumerated()), id: \.offset) { _, highlight in
                Label {
                    Text(highlight)
                        .font(.callout)
                        .foregroundStyle(Brand.Palette.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Brand.Gradient.signature)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Brand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
                .fill(Brand.Surface.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
                .strokeBorder(Brand.Palette.border.color, lineWidth: Brand.Stroke.hairline)
        )
        // The list reads as one "what changed" region, then each highlight as a row.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What's new in version \(note.version)")
        .accessibilityIdentifier("whats-new-highlights")
    }

    private var footer: some View {
        HStack(spacing: Brand.Spacing.sm) {
            Button("Open Help") {
                markSeen()
                HelpWindowController.shared.show()
                onDismiss()
            }
            .help("Open Vitrine Help")
            .accessibilityIdentifier("whats-new-help-button")
            Spacer()
            Button("Continue") { finish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Dismiss and continue")
                .accessibilityIdentifier("whats-new-continue-button")
        }
    }

    // MARK: - Actions

    /// Records that the user has seen the notes for this bundled version so the
    /// surface does not reappear until the next upgrade (CS-049). Both "Continue"
    /// and "Open Help" mark it seen — being skippable means dismissing is a
    /// first-class outcome, not a penalty.
    private func markSeen() {
        settings.lastSeenWhatsNewVersion = note.version
    }

    private func finish() {
        markSeen()
        onDismiss()
    }
}

/// Owns and presents the version-gated "What's New" window (CS-049).
///
/// Mirrors `WelcomeWindowController`: the gate ("only when the bundled version is
/// newer than the last seen, and never on a clean first run") lives in one place,
/// `presentIfNewVersion`, which the app lifecycle calls after onboarding so the
/// two first-launch surfaces never both appear.
@MainActor
final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    static let shared = WhatsNewWindowController()

    private var window: NSWindow?

    /// The settings the on-screen window was created against, retained so any
    /// dismissal path can stamp the seen version (see `windowWillClose`).
    private var presentedSettings: AppSettings?

    /// The note the on-screen window is showing, retained so a title-bar close can
    /// record its version as seen even though the buttons are what call `markSeen`.
    private var presentedNote: ReleaseNote?

    private override init() {}

    /// Shows "What's New" only when the newest bundled notes are newer than what
    /// the user last saw (CS-049). On a clean first run it shows nothing and
    /// instead records the current version as seen, so onboarding owns the first
    /// launch and the *next* upgrade is what surfaces notes.
    ///
    /// - Returns: whether the window was presented, which the launch path can use
    ///   to avoid stacking it over another just-opened window.
    @discardableResult
    func presentIfNewVersion(settings: AppSettings = .shared) -> Bool {
        guard let latest = ReleaseNotes.latest else { return false }

        if settings.lastSeenWhatsNewVersion == nil {
            // Clean first run: onboarding owns it. Stamp the current version as seen
            // so What's New starts surfacing only from the next upgrade onward.
            settings.lastSeenWhatsNewVersion = latest.version
            return false
        }

        guard
            ReleaseNotes.shouldPresent(
                latest: latest, lastSeenVersion: settings.lastSeenWhatsNewVersion)
        else { return false }

        show(settings: settings, note: latest)
        return true
    }

    /// Shows (creating if needed) and focuses the window for `note`. Public so a
    /// launch hook can force it open for manual and UI testing, independent of the
    /// gate.
    func show(settings: AppSettings = .shared, note: ReleaseNote? = ReleaseNotes.latest) {
        guard let note else { return }
        presentedSettings = settings
        presentedNote = note
        if window == nil {
            let hosting = NSHostingController(
                rootView: WhatsNewView(
                    settings: settings, note: note,
                    onDismiss: { [weak self] in self?.close() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "What's New in Vitrine")
            // A compact release-notes surface, not a working window — but resizable
            // and miniaturizable (like the sibling Help window) so a user at a large
            // Dynamic Type size can grow it to reach the scrolled content and footer.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("whats-new-window")
            // Stamp the version as seen on any dismissal, including the title-bar
            // close button — closing must be equivalent to "Continue".
            window.delegate = self
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

    /// Records the presented version as seen on *any* dismissal — the title-bar
    /// close button, Cmd-W, or a programmatic `close()` — so closing the window is
    /// equivalent to "Continue" and the same notes never re-present (CS-049). The
    /// "Continue"/"Open Help" buttons also call `markSeen`; stamping here makes the
    /// outcome consistent regardless of how the user dismisses.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        if let note = presentedNote {
            presentedSettings?.lastSeenWhatsNewVersion = note.version
        }
        presentedSettings = nil
        presentedNote = nil
    }
}

#if DEBUG
    #Preview("What's New") {
        WhatsNewView(
            settings: .shared,
            note: ReleaseNotes.latest
                ?? ReleaseNote(version: "0.0.0", headline: "Preview", highlights: ["A highlight."]),
            onDismiss: {})
    }
#endif

import AppKit
import KeyboardShortcuts
import SwiftUI

/// Concise, offline in-app Help (CS-049).
///
/// CS-032 made the Help command *reachable*; this gives it real content. A single
/// compact, scrollable window teaches the core surfaces — the global hotkey, quick
/// capture, the editor, presets, and the privacy posture — entirely from bundled
/// copy, with no web dependency. The wording matches the privacy promise in
/// `docs/ARCHITECTURE.md`, the README, and `docs/HELP.md` (the repo's source of
/// truth for this content).
///
/// The view is static text and a few links, so it is keyboard- and VoiceOver-
/// accessible by construction and introduces no motion to respect Reduced Motion.
struct HelpView: View {
    /// Closes the hosting window. Injected by the window controller so the view has
    /// no dependency on how it is presented.
    var onDismiss: () -> Void

    /// The Help topics, each rendered as a titled card. The copy lives in the String
    /// Catalog under stable keys (CS-047) — mirrored in `docs/HELP.md` — so the
    /// in-app text is localizable and these long passages don't bloat the source.
    private let topics: [HelpTopic] = [
        HelpTopic(
            symbol: "command",
            title: "help.topic.hotkey.title",
            body: "help.topic.hotkey.body",
            identifier: "help-topic-hotkey"),
        HelpTopic(
            symbol: "camera.viewfinder",
            title: "help.topic.quick-capture.title",
            body: "help.topic.quick-capture.body",
            identifier: "help-topic-quick-capture"),
        HelpTopic(
            symbol: "macwindow",
            title: "help.topic.editor.title",
            body: "help.topic.editor.body",
            identifier: "help-topic-editor"),
        HelpTopic(
            symbol: "slider.horizontal.3",
            title: "help.topic.presets.title",
            body: "help.topic.presets.body",
            identifier: "help-topic-presets"),
        HelpTopic(
            symbol: "lock.shield",
            title: "help.topic.privacy.title",
            body: "help.topic.privacy.body",
            identifier: "help-topic-privacy"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.bottom, 4)
                ForEach(topics) { topic in
                    topicCard(topic)
                }
                hotkeyControl
                footer
            }
            .padding(.top, 22)
            .padding(.horizontal, VitrineTokens.Spacing.lg)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520)
        .frame(minHeight: 560)
        .background(VitrineTokens.Surface.window)
        .accessibilityIdentifier("help-view")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: VitrineTokens.Spacing.sm) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vitrine Help")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                Text("Everything you need to turn code into images.")
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }
        }
        // The mark is decorative; read the title and tagline as one announcement.
        .accessibilityElement(children: .combine)
    }

    private func topicCard(_ topic: HelpTopic) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: topic.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                Text(topic.body)
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, VitrineTokens.Spacing.md)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                .fill(VitrineTokens.Surface.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
        )
        // Combine the icon-less title and body into one VoiceOver element per topic
        // so navigation reads each card as a single, coherent passage. The label is
        // built from the localized title and body (CS-047).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(String(localized: topic.title)). \(String(localized: topic.body))")
        )
        .accessibilityIdentifier(topic.identifier)
    }

    /// A live hotkey recorder so Help is also actionable: a user reading "set the
    /// hotkey" can set it without leaving the window (mirrors Settings ▸ General).
    private var hotkeyControl: some View {
        VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
            Text("Set your hotkey")
                .font(.system(size: VitrineTokens.FontSize.headline, weight: .semibold))
                .foregroundStyle(VitrineTokens.Text.primary)
            HStack {
                KeyboardShortcuts.Recorder("Global hotkey:", name: .quickCapture)
                    .accessibilityIdentifier("help-hotkey-recorder")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, VitrineTokens.Spacing.md)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                .fill(Brand.Gradient.signatureWash(opacity: 0.12))
        )
    }

    private var footer: some View {
        HStack(spacing: Brand.Spacing.sm) {
            Link(
                "View documentation on GitHub",
                destination: URL(string: "https://github.com/johnny4young/vitrine")!
            )
            .help("Open the Vitrine documentation on GitHub")
            Spacer()
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Close Help")
                .accessibilityIdentifier("help-done-button")
        }
    }
}

/// One Help topic: an SF Symbol, a title, and a short body, plus a stable
/// accessibility identifier for UI tests (CS-049).
private struct HelpTopic: Identifiable {
    let symbol: String
    /// Localized through the String Catalog (CS-047): `LocalizedStringResource` so
    /// the model carries a catalog reference that `Text(_:)` renders localized,
    /// rather than a baked-in English `String`.
    let title: LocalizedStringResource
    let body: LocalizedStringResource
    let identifier: String

    var id: String { identifier }
}

/// Owns and presents the in-app Help window (CS-049).
///
/// Mirrors the other on-demand window controllers (`WelcomeWindowController`,
/// `EditorWindowController`): an AppKit window hosting the SwiftUI view, created
/// lazily and reused so reopening Help focuses the existing window rather than
/// stacking duplicates.
@MainActor
final class HelpWindowController {
    static let shared = HelpWindowController()

    private var window: NSWindow?

    private init() {}

    /// Shows (creating if needed) and focuses the Help window.
    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: HelpView(onDismiss: { [weak self] in self?.close() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Vitrine Help")
            // Help is a fixed-width reference surface; allow resize so a user at a
            // large Dynamic Type size can grow it, but keep it non-document-like.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("help-window")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the window without releasing the controller, so a later `show()` can
    /// re-present it.
    private func close() {
        window?.close()
    }
}

#if DEBUG
    #Preview("Help") {
        HelpView(onDismiss: {})
    }
#endif

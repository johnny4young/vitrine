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

    /// The Help topics, each rendered as a titled card. Authored here (and mirrored
    /// in `docs/HELP.md`) so the in-app copy and the repo doc stay in step.
    private let topics: [HelpTopic] = [
        HelpTopic(
            symbol: "command",
            title: "The global hotkey",
            body:
                "Press the global hotkey from any app to capture whatever code is on your "
                + "clipboard as an image. Set or change the hotkey below, or in Settings ▸ General.",
            identifier: "help-topic-hotkey"),
        HelpTopic(
            symbol: "camera.viewfinder",
            title: "Quick capture",
            body:
                "Copy code anywhere, press the hotkey, and Vitrine renders it with your current "
                + "style. The image is placed on your clipboard automatically — paste it straight "
                + "into a doc, chat, or pull request.",
            identifier: "help-topic-quick-capture"),
        HelpTopic(
            symbol: "macwindow",
            title: "The editor",
            body:
                "Open the editor to paste or type code, pick a language and theme, and fine-tune "
                + "padding, corner radius, window chrome, and line numbers. Copy, save, or share "
                + "the result from the toolbar or the File menu.",
            identifier: "help-topic-editor"),
        HelpTopic(
            symbol: "slider.horizontal.3",
            title: "Presets",
            body:
                "Destination presets size the image for where it is going (a README, a social "
                + "card, a slide). Style presets save a look you like so you can reapply it in one "
                + "click. Manage both in Settings ▸ Style.",
            identifier: "help-topic-presets"),
        HelpTopic(
            symbol: "lock.shield",
            title: "Privacy",
            body:
                "Vitrine is private by design: your code never leaves your Mac. There is no "
                + "account and no network access, and rendering needs no screen-recording or "
                + "Accessibility permission.",
            identifier: "help-topic-privacy"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                header
                ForEach(topics) { topic in
                    topicCard(topic)
                }
                hotkeyControl
                footer
            }
            .padding(Brand.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520)
        .frame(minHeight: 560)
        .background(Brand.Palette.stage.color)
        .accessibilityIdentifier("help-view")
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: Brand.Spacing.md) {
            BrandMark(size: 40)
            VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                Text("Vitrine Help")
                    .font(.title2.bold())
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                Text("Everything you need to turn code into images.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.Palette.textSecondary.color)
            }
        }
        // The mark is decorative; read the title and tagline as one announcement.
        .accessibilityElement(children: .combine)
    }

    private func topicCard(_ topic: HelpTopic) -> some View {
        HStack(alignment: .top, spacing: Brand.Spacing.md) {
            Image(systemName: topic.symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Brand.Gradient.signature)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                Text(topic.title)
                    .font(.headline)
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                Text(topic.body)
                    .font(.callout)
                    .foregroundStyle(Brand.Palette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
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
        // Combine the icon-less title and body into one VoiceOver element per topic
        // so navigation reads each card as a single, coherent passage.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.title). \(topic.body)")
        .accessibilityIdentifier(topic.identifier)
    }

    /// A live hotkey recorder so Help is also actionable: a user reading "set the
    /// hotkey" can set it without leaving the window (mirrors Settings ▸ General).
    private var hotkeyControl: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Set your hotkey")
                .font(.headline)
                .foregroundStyle(Brand.Palette.textPrimary.color)
            HStack {
                KeyboardShortcuts.Recorder("Global hotkey:", name: .quickCapture)
                    .accessibilityIdentifier("help-hotkey-recorder")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Brand.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
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
    let title: String
    let body: String
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
            window.title = "Vitrine Help"
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

import AppKit
import KeyboardShortcuts
import SwiftUI

/// The menu-bar panel (CS-009), redesigned per design/handoff as a
/// `MenuBarExtra(.window)` surface: header with the live hotkey, the gradient
/// "New Capture from Clipboard" CTA, recent captures as thumbnail rows, the
/// theme chip strip, and the explicit command rows with their shortcuts.
///
/// Titles, SF Symbols, and shortcuts come from `VitrineCommand` so the panel
/// and the application main menu (CS-032) never drift.
struct MenuBarContent: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RecentsStore.self) private var recents
    @Environment(CaptureFeedbackPresenter.self) private var feedback

    /// Closes the panel after an action, mirroring how a native menu dismisses
    /// on selection.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            captureCTA
            presetCaptureMenu
            lastCaptureStatus
            recentsSection
            themeSection
            menuRows
        }
        .padding(14)
        .frame(width: 340)
        // Controls follow the user's macOS accent; `Color.accentColor` is the app's
        // brand asset in this repo, so force the AppKit system token.
        .tint(VitrineTokens.Accent.system)
        .accessibilityContainerIdentifier("menubar-panel")
    }

    /// A one-off destination choice for the clipboard. This does not replace the
    /// user's default output preset; it only frames this render, so experimenting
    /// from the menu bar cannot silently change future captures.
    private var presetCaptureMenu: some View {
        Menu {
            ForEach(ExportPreset.all) { preset in
                Button {
                    QuickCapture.perform(settings: settings, destinationPreset: preset)
                    dismiss()
                } label: {
                    Text(verbatim: preset.displayName)
                }
                .accessibilityIdentifier("menu-capture-preset-\(preset.id)")
            }
        } label: {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Image(systemName: "rectangle.3.group")
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text("Render Clipboard As…")
                    .font(.system(size: VitrineTokens.FontSize.subhead, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(VitrineTokens.Text.secondary)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityHint("Choose a destination size without changing the default preset")
        .accessibilityIdentifier("menu-capture-preset-picker")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(verbatim: "Vitrine")
                .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                .foregroundStyle(VitrineTokens.Text.primary)
            Spacer(minLength: 0)
            if let shortcut = KeyboardShortcuts.getShortcut(for: .quickCapture) {
                KbdChip(
                    glyphs: shortcut.description,
                    purpose: String(localized: "Capture hotkey"))
            }
        }
    }

    // MARK: - Capture CTA

    /// The full-width gradient capture action — the panel's primary command.
    @ViewBuilder private var captureCTA: some View {
        let command = VitrineCommand.newCapture
        let button = Button {
            QuickCapture.perform(settings: settings)
            dismiss()
        } label: {
            HStack(spacing: VitrineTokens.Spacing.xs) {
                Image(systemName: command.systemImageName)
                    .font(.system(size: 12, weight: .semibold))
                Text(command.title)
            }
            .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VitrineTokens.Gradients.signature)
            )
            .brandShadow(VitrineTokens.Chrome.ctaShadow)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier(command.accessibilityIdentifier)

        if let shortcut = command.swiftUIShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }

    /// The last capture outcome plus any inline recovery actions (CS-038).
    /// Hidden until a capture has run, so a clean launch shows no stale status.
    @ViewBuilder private var lastCaptureStatus: some View {
        if let last = feedback.lastFeedback {
            VStack(alignment: .leading, spacing: 4) {
                Label("Last capture: \(last.message)", systemImage: last.systemImageName)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .accessibilityIdentifier("menu-last-capture-status")
                ForEach(last.actions, id: \.self) { action in
                    Button(action.title) {
                        feedback.run(action, settings: settings)
                        dismiss()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .accessibilityIdentifier("menu-recovery-\(action.accessibilityToken)")
                }
            }
        }
    }

    // MARK: - Recents

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                TokenGroupLabel(title: Text("Recents"))
                Spacer(minLength: 0)
                Button {
                    RecentsGalleryWindowController.shared.show()
                    dismiss()
                } label: {
                    Text("View history →")
                        .font(.system(size: VitrineTokens.FontSize.caption))
                        .foregroundStyle(VitrineTokens.Accent.system)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu-recents-gallery")
            }

            if recents.captures.isEmpty {
                // Teach the core loop here — this panel is the first surface many users
                // open, before any capture exists (audit UX). The hotkey chip above shows
                // exactly which keys "the capture hotkey" means.
                VStack(alignment: .leading, spacing: 2) {
                    Text("No recent captures")
                        .foregroundStyle(VitrineTokens.Text.secondary)
                    Text("Copy some code and press the capture hotkey.")
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                }
                .font(.system(size: VitrineTokens.FontSize.caption))
                .padding(.vertical, 4)
            } else {
                ForEach(Array(recents.captures.prefix(3))) { capture in
                    RecentCaptureRow(
                        capture: capture,
                        reopen: {
                            reopen(capture)
                            dismiss()
                        },
                        copyImage: { copyAgain(capture) },
                        copySource: { copySource(capture) })
                }
            }
        }
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                TokenGroupLabel(title: Text("Theme"))
                Spacer(minLength: VitrineTokens.Spacing.xs)
                Button {
                    settings.applySurpriseStyle()
                } label: {
                    Label("Surprise Me", systemImage: "dice")
                        .font(.system(size: VitrineTokens.FontSize.caption, weight: .semibold))
                        .foregroundStyle(VitrineTokens.Accent.system)
                }
                .buttonStyle(.plain)
                .help("Apply the next curated style without changing your code")
                .accessibilityHint("Apply the next curated style without changing your code")
                .accessibilityIdentifier("menu-surprise-style-button")
            }
            ChipScroll(topPadding: 2, bottomPadding: 4) {
                ForEach(ThemeChipColors.orderedBuiltIns) { theme in
                    themeChip(for: theme)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Theme")
        }
    }

    /// One named theme chip (`.tchip`): accent-filled when active.
    private func themeChip(for theme: Theme) -> some View {
        let isSelected = settings.config.theme.id == theme.id
        return Button {
            settings.selectTheme(theme)
        } label: {
            Text(verbatim: theme.displayName)
                .font(.system(size: VitrineTokens.FontSize.caption, weight: .medium))
                .foregroundStyle(
                    isSelected ? VitrineTokens.Accent.systemContrast : VitrineTokens.Text.secondary
                )
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? VitrineTokens.Accent.system : .clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? .clear : VitrineTokens.Line.border,
                            lineWidth: Brand.Stroke.hairline
                        )
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: theme.displayName))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Command rows

    /// The explicit menu rows — label + shortcut, nothing hidden behind icons.
    private var menuRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(VitrineTokens.Line.separator)
                .padding(.bottom, VitrineTokens.Spacing.xs)
            commandRow(.openEditor) {
                EditorWindowController.shared.show()
            }
            commandRow(.newWebSnapshot) {
                WebSnapshotPresenter.show()
            }
            commandRow(.newSocialCard) {
                SocialCardWindowController.shared.show()
            }
            commandRow(.settings) {
                SettingsWindowManager.shared.show()
            }
            commandRow(.help) {
                HelpWindowController.shared.show()
            }
            commandRow(.about) {
                AboutPanel.present()
            }
            quitRow
        }
    }

    /// One hover-highlighted command row driven by a `VitrineCommand`: shared
    /// title, SF Symbol, keyboard shortcut, and accessibility identifier (CS-032).
    @ViewBuilder
    private func commandRow(_ command: VitrineCommand, action: @escaping () -> Void) -> some View {
        let row = MenuPanelRow(
            title: command.title,
            systemImage: command.systemImageName,
            shortcutGlyphs: command.shortcutGlyphs
        ) {
            action()
            dismiss()
        }
        .accessibilityIdentifier(command.accessibilityIdentifier)

        if let shortcut = command.swiftUIShortcut {
            row.keyboardShortcut(shortcut)
        } else {
            row
        }
    }

    private var quitRow: some View {
        MenuPanelRow(
            title: String(localized: "Quit Vitrine"),
            systemImage: "power",
            shortcutGlyphs: "⌘Q"
        ) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        .accessibilityIdentifier("command-quit")
    }

    // MARK: - Actions

    /// Loads a recent capture into the primary editor window and shows it. Builds the
    /// document over the app's default style so the recent's code/language/theme appear
    /// even if the editor is already open (CS-053: a plain `show()` no longer clobbers
    /// an open window's per-window document).
    private func reopen(_ capture: Capture) {
        EditorWindowController.shared.loadIntoPrimary(capture.applying(to: settings.config))
    }

    /// Re-renders a recent capture with the user's current output settings and
    /// copies the image — the row's hover action, so a past capture is one
    /// click from the clipboard again.
    private func copyAgain(_ capture: Capture) {
        let config = capture.applying(to: settings.config)
        ExportManager.copyToPasteboard(
            config, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.export.colorProfile,
            richText: settings.export.richClipboard, plainText: settings.export.textSidecar)
    }

    private func copySource(_ capture: Capture) {
        ExportFeedback.presentSourceCopy(
            ExportManager.copySourceToPasteboard(capture.code))
    }
}

// MARK: - Panel pieces

/// The small keyboard-glyph tag in the panel (`.kbd`): mono caption in a thin
/// bordered tag.
private struct KbdChip: View {
    let glyphs: String
    /// What the shortcut does. When set, VoiceOver announces it as the element's label
    /// and the glyphs as its value (e.g. "Capture hotkey: ⇧⌘S") instead of folding both
    /// into one concatenated, hard-to-localize label. Without it the glyphs are the
    /// label and there is no separate value.
    var purpose: String?

    var body: some View {
        let tag = Text(verbatim: glyphs)
            .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
            .foregroundStyle(VitrineTokens.Text.tertiary)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
            )
            .accessibilityElement()
        if let purpose {
            tag.accessibilityLabel(Text(verbatim: purpose))
                .accessibilityValue(Text(verbatim: glyphs))
        } else {
            tag.accessibilityLabel(Text(verbatim: glyphs))
        }
    }
}

/// One recent capture as a thumbnail row (`.rrow`): a stylized mini card on
/// the brand gradient, the capture's first line and metadata, and compact image/source
/// copy actions. Clicking the row reopens the capture.
private struct RecentCaptureRow: View {
    let capture: Capture
    let reopen: () -> Void
    let copyImage: () -> Void
    let copySource: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: reopen) {
                rowContent
                    .padding(.trailing, 64)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(capture.menuTitle), \(metadataLine)"))

            HStack(spacing: 4) {
                copyButton(
                    title: "Copy Image", systemImage: "doc.on.doc",
                    identifier: "menu-recent-copy-image", action: copyImage)
                copyButton(
                    title: "Copy Source", systemImage: "doc.text",
                    identifier: "menu-recent-copy-source", action: copySource)
            }
            .padding(.trailing, 6)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-recent-row")
    }

    private func copyButton(
        title: LocalizedStringKey, systemImage: String, identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: capture.menuTitle)
                    .font(.system(size: VitrineTokens.FontSize.subhead, weight: .medium))
                    .foregroundStyle(VitrineTokens.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: metadataLine)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous)
                .fill(isHovered ? VitrineTokens.Chrome.tile : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: VitrineTokens.Radius.md, style: .continuous))
    }

    /// Language · relative time · theme — the capture's visible context line.
    private var metadataLine: String {
        let time = Self.relativeFormatter.localizedString(
            for: capture.date, relativeTo: Date())
        return "\(capture.language.displayName) · \(time) · \(capture.theme.displayName)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// The 52×38 stylized thumbnail: a mini code card in the capture's theme
    /// color over the signature gradient.
    private var thumbnail: some View {
        let chip = ThemeChipColors.colors(for: capture.theme)
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(VitrineTokens.Gradients.signature)
            .frame(width: 52, height: 38)
            .overlay(
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 2) {
                        ForEach(Array(chip.dots.enumerated()), id: \.offset) { _, dot in
                            Circle().fill(dot).frame(width: 2.8, height: 2.8)
                        }
                    }
                    Capsule().fill(.white.opacity(0.4)).frame(width: 30, height: 2)
                    Capsule().fill(.white.opacity(0.25)).frame(width: 20, height: 2)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(chip.bg)
                        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
                )
                .padding(5)
            )
            .accessibilityHidden(true)
    }
}

/// One explicit command row (`.mrow`): icon + label + shortcut, washed with
/// the accent on hover like a native menu item.
private struct MenuPanelRow: View {
    let title: String
    let systemImage: String
    var shortcutGlyphs: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        isHovered
                            ? VitrineTokens.Accent.systemContrast.opacity(0.85)
                            : VitrineTokens.Text.secondary
                    )
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(
                        isHovered ? VitrineTokens.Accent.systemContrast : VitrineTokens.Text.primary
                    )
                Spacer(minLength: 0)
                if let shortcutGlyphs {
                    Text(verbatim: shortcutGlyphs)
                        .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                        .foregroundStyle(
                            isHovered
                                ? VitrineTokens.Accent.systemContrast.opacity(0.85)
                                : VitrineTokens.Text.tertiary
                        )
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isHovered
                                        ? VitrineTokens.Accent.systemContrast.opacity(0.3)
                                        : VitrineTokens.Line.border,
                                    lineWidth: Brand.Stroke.hairline
                                )
                        )
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, VitrineTokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovered ? VitrineTokens.Accent.system : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

extension VitrineCommand {
    /// This command's shortcut as typed glyphs (e.g. `"⌘E"`), or `nil` when it
    /// has none — the panel shows shortcuts as visible `kbd` tags (design/handoff).
    var shortcutGlyphs: String? {
        guard let key = keyEquivalent, !key.isEmpty else { return nil }
        var glyphs = ""
        if modifiers.contains(.control) { glyphs += "⌃" }
        if modifiers.contains(.option) { glyphs += "⌥" }
        if modifiers.contains(.shift) { glyphs += "⇧" }
        if modifiers.contains(.command) { glyphs += "⌘" }
        return glyphs + key.uppercased()
    }
}

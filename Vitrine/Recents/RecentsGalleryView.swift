import AppKit
import SwiftUI

/// The visual recents gallery (CS-029): a window that shows past captures as
/// preview cards instead of only a truncated line of code in a menu.
///
/// People recognize a screenshot far faster by its look — theme, language, and
/// the shape of the code — than by reading its first line, so each card pairs the
/// locally rendered thumbnail with its language, theme, and capture date. Picking
/// a card loads that capture back into the editor, exactly like the text Recents
/// submenu does, so the gallery is a richer entry point to the same history rather
/// than a separate store.
///
/// ## Privacy
///
/// Every thumbnail shown here is rendered on-device by the app's own export
/// pipeline and cached in a private app-container directory (see
/// `RecentsThumbnailCache`). Nothing in this view is uploaded or shared — it is a
/// local recognition aid only.
struct RecentsGalleryView: View {
    @EnvironmentObject private var recents: RecentsStore
    @EnvironmentObject private var settings: AppSettings

    /// Drives the confirmation before clearing recents. Clearing is irreversible —
    /// it empties the capture list and deletes the on-disk thumbnail cache — so the
    /// toolbar button asks first rather than wiping history on a single click,
    /// matching every other destructive action in the app (see `EditorView`).
    @State private var isConfirmingClear = false

    /// Invoked after a capture is chosen, so the host can bring the editor
    /// forward. Injectable for previews/tests; defaults to opening the editor
    /// window.
    var onOpen: () -> Void = { EditorWindowController.shared.show() }

    /// A responsive grid: cards keep a comfortable minimum width and the row
    /// reflows as the window is resized.
    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: Brand.Spacing.md)
    ]

    var body: some View {
        Group {
            if recents.captures.isEmpty {
                emptyState
            } else {
                gallery
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Brand.Palette.stage.color)
        // The redesign's controls tint with the brand accent, not the user's
        // system accent.
        .tint(VitrineTokens.Accent.base)
        // Become a container element *before* taking the identifier: on a plain
        // (non-element) view the identifier propagates down and overrides the
        // descendants' own identifiers (same gotcha as WelcomeView/WhatsNewView).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recents-gallery")
    }

    // MARK: - Gallery

    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Brand.Spacing.md) {
                ForEach(recents.captures) { capture in
                    RecentsCard(
                        capture: capture,
                        thumbnail: recents.thumbnail(for: capture)
                    ) {
                        open(capture)
                    }
                }
            }
            .padding(Brand.Spacing.lg)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label("Clear Recents", systemImage: "trash")
                }
                .help("Remove every recent capture and its cached preview")
                .accessibilityIdentifier("recents-clear-button")
            }
        }
        // Clearing recents cannot be undone — it empties the list and deletes the
        // cached previews — so confirm first. The destructive (red) action mirrors
        // the replace/discard prompts elsewhere in the app (CS-028).
        .confirmationDialog(
            "Clear Recents?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Recents", role: .destructive) { recents.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every recent capture and its cached preview. This can't be undone.")
        }
        .accessibilityIdentifier("recents-clear-confirmation")
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "No recent captures",
            message:
                "Captures you make appear here as previews. Copy some code and press the capture hotkey to get started.",
            actionTitle: "Open Editor",
            action: open
        )
    }

    // MARK: - Actions

    /// Loads `capture` back into the shared settings (the same fields the text
    /// Recents submenu restores) and asks the host to surface the editor.
    private func open(_ capture: Capture) {
        settings.config.code = capture.code
        settings.config.language = capture.language
        settings.config.theme = capture.theme
        open()
    }

    private func open() {
        onOpen()
    }
}

// MARK: - Card

/// A single recents preview card: the cached thumbnail (or a branded placeholder
/// when none is cached yet) above a row of metadata — language, theme, and a
/// relative capture date.
private struct RecentsCard: View {
    let capture: Capture
    let thumbnail: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                preview
                metadata
            }
            .padding(Brand.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.Surface.raised, in: shape)
            .overlay(
                shape.strokeBorder(Brand.Palette.border.color, lineWidth: Brand.Stroke.hairline)
            )
            .brandShadow(Brand.Shadow.card)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recents-card")
        .accessibilityLabel(accessibilityLabel)
        .help("Open this capture in the editor")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Brand.Radius.lg, style: .continuous)
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // No cached preview (e.g. a capture restored from a build that
                // predates CS-029): fall back to the brand mark so the card still
                // reads as a recents entry rather than a broken image.
                Brand.Gradient.signatureWash()
                BrandMark(size: 32)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(RecentsThumbnail.size.width / RecentsThumbnail.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous))
        .accessibilityHidden(true)
    }

    private var metadata: some View {
        HStack(spacing: Brand.Spacing.xs) {
            Text(capture.language.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Brand.Palette.textPrimary.color)
                .lineLimit(1)
            // A locale-neutral separator dot, shown verbatim (CS-047).
            Text(verbatim: "·")
                .foregroundStyle(Brand.Palette.textSecondary.color)
            Text(capture.theme.displayName)
                .font(.subheadline)
                .foregroundStyle(Brand.Palette.textSecondary.color)
                .lineLimit(1)
            Spacer(minLength: Brand.Spacing.xs)
            Text(Self.dateFormatter.localizedString(for: capture.date, relativeTo: Date()))
                .font(.caption)
                .foregroundStyle(Brand.Palette.textSecondary.color)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }

    /// One concise VoiceOver announcement combining the metadata the card shows
    /// visually, so the card reads usefully without the user inspecting each label.
    private var accessibilityLabel: String {
        let when = Self.dateFormatter.localizedString(for: capture.date, relativeTo: Date())
        return "\(capture.language.displayName), \(capture.theme.displayName), \(when)"
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

// MARK: - Window

/// Owns the recents gallery window (hosted SwiftUI), mirroring
/// `EditorWindowController` so the gallery can be opened from the menu without a
/// SwiftUI `openWindow` environment.
///
/// A single reused, non-released window keeps the gallery cheap to reopen and lets
/// the menu route to it with one call. The hosted view observes the shared
/// `RecentsStore`, so the grid updates live as captures are added or cleared while
/// the window is open.
final class RecentsGalleryWindowController {
    static let shared = RecentsGalleryWindowController()

    private var window: NSWindow?

    private init() {}

    /// Shows (creating if needed) and focuses the recents gallery window.
    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: RecentsGalleryView()
                    .environmentObject(RecentsStore.shared)
                    .environmentObject(AppSettings.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Recents"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 560))
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier("recents-window")
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if DEBUG
    #Preview("Gallery") {
        RecentsGalleryView(onOpen: {})
            .environmentObject(RecentsStore.shared)
            .environmentObject(AppSettings.shared)
            .frame(width: 720, height: 520)
    }
#endif

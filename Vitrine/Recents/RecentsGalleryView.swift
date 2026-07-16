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
    @Environment(RecentsStore.self) private var recents
    @Environment(AppSettings.self) private var settings

    /// Drives the confirmation before clearing recents. Clearing is irreversible —
    /// it empties the capture list and deletes the on-disk thumbnail cache — so the
    /// toolbar button asks first rather than wiping history on a single click,
    /// matching every other destructive action in the app (see `EditorView`).
    @State private var isConfirmingClear = false

    /// Local, ephemeral gallery filtering. Search never changes or persists the
    /// underlying history; closing the window naturally resets it.
    @State private var searchQuery = ""

    /// The capture awaiting individual deletion confirmation. Keeping the model,
    /// rather than only a Boolean, guarantees the confirmation removes the exact
    /// card whose menu initiated it even if the grid updates meanwhile.
    @State private var pendingDeletion: Capture?

    /// Invoked when the empty state asks to open the editor. Injectable for previews/tests;
    /// defaults to opening the editor window.
    var onOpen: () -> Void = { EditorWindowController.shared.show() }

    /// Invoked after a capture is chosen, so previews/tests can exercise the gallery without
    /// touching the global editor window controller. Production loads the capture into the
    /// primary editor window.
    var onOpenCapture: (SnapshotConfig) -> Void = {
        EditorWindowController.shared.loadIntoPrimary($0)
    }

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
        .tint(VitrineTokens.Accent.system)
        .accessibilityContainerIdentifier("recents-gallery")
    }

    // MARK: - Gallery

    private var gallery: some View {
        ScrollView {
            if filteredCaptures.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .accessibilityIdentifier("recents-no-search-results")
            } else {
                LazyVGrid(columns: columns, spacing: Brand.Spacing.md) {
                    ForEach(filteredCaptures) { capture in
                        RecentsCard(
                            capture: capture,
                            thumbnail: recents.thumbnail(for: capture),
                            action: { open(capture) },
                            renderAs: { preset in render(capture, as: preset) },
                            delete: { pendingDeletion = capture })
                    }
                }
                .padding(Brand.Spacing.lg)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                TextField("Search Recents", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .accessibilityIdentifier("recents-search-field")
            }
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
        .confirmationDialog(
            "Delete Capture?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Capture", role: .destructive) {
                if let id = pendingDeletion?.id { recents.remove(id: id) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the capture and its cached preview. This can't be undone.")
        }
        .accessibilityIdentifier("recents-delete-confirmation")
    }

    /// A prefiltered value keeps `ForEach` stable and makes the search contract easy
    /// to read: every visible card retains its persisted capture id.
    private var filteredCaptures: [Capture] {
        recents.captures.filter { $0.matchesSearch(searchQuery) }
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

    /// Loads `capture` into the primary editor window as a per-window document — the same
    /// path the menu-bar Recents row uses (`EditorWindowController.loadIntoPrimary`,
    /// CS-053). The earlier version mutated the shared `AppSettings` and only `show()`d the
    /// window, so reopening from the gallery silently overwrote the global default style
    /// *and* left the editor on its previous content; this matches the menu's semantics so
    /// the two recents surfaces behave identically.
    private func open(_ capture: Capture) {
        onOpenCapture(capture.applying(to: settings.config))
    }

    /// Re-renders a past capture for one destination without changing the app's saved
    /// style or default output preset. The destination owns both the presentation
    /// guidance and exact geometry, matching the menu-bar one-off preset flow.
    private func render(_ capture: Capture, as preset: ExportPreset) {
        var config = capture.applying(to: settings.config)
        preset.apply(to: &config)
        let copied = ExportManager.copyToPasteboard(
            config,
            scale: CGFloat(preset.scale),
            fixedSize: preset.sizing.fixedSize,
            profile: settings.export.colorProfile,
            richText: settings.export.richClipboard,
            plainText: settings.export.textSidecar)
        ExportFeedback.presentCopy(copied)
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
    let renderAs: (ExportPreset) -> Void
    let delete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

            presetMenu
                .padding(Brand.Spacing.sm + Brand.Spacing.xs)
        }
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

    private var presetMenu: some View {
        Menu {
            ForEach(ExportPreset.all) { preset in
                Button {
                    renderAs(preset)
                } label: {
                    Text(verbatim: preset.displayName)
                }
                .accessibilityIdentifier("recents-preset-\(preset.id)")
            }
            Divider()
            Button("Delete Capture", role: .destructive, action: delete)
                .accessibilityIdentifier("recents-delete-capture")
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.Palette.textPrimary.color)
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Brand.Palette.border.color))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Re-render or remove this recent capture")
        .accessibilityLabel("Capture actions")
        .accessibilityIdentifier("recents-preset-picker")
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
                    .environment(RecentsStore.shared)
                    .environment(AppSettings.shared))
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
            .environment(RecentsStore.shared)
            .environment(AppSettings.shared)
            .frame(width: 720, height: 520)
    }
#endif

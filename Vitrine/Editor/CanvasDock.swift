import SwiftUI
import VitrineDomain
import VitrineRendering

/// Inspector sections that canvas mode opens on their own, in a popover.
enum InspectorPane: String, CaseIterable, Identifiable {
    case theme, frame, typography, background, canvas

    var id: String { rawValue }

    /// The dock's buttons. Language and destination stay in the toolbar and the status
    /// capsule, which canvas mode keeps; an image swaps theme and type for its frame.
    static func dockPanes(usesImageContent: Bool) -> [InspectorPane] {
        usesImageContent
            ? [.frame, .background, .canvas] : [.theme, .typography, .background, .canvas]
    }

    var dockTitle: String {
        switch self {
        case .theme: String(localized: "Theme")
        case .frame: String(localized: "Frame")
        case .typography: String(localized: "Typography")
        case .background: String(localized: "Background")
        case .canvas: String(localized: "Padding")
        }
    }

    func dockValue(in style: SnapshotConfig) -> String {
        switch self {
        case .theme: style.theme.displayName
        case .frame: Self.frameName(style.imageFrame)
        case .typography:
            InspectorReadout.typography(fontName: style.fontName, fontSize: style.fontSize)
        case .background:
            InspectorReadout.background(style.background)
                ?? Self.backgroundKindName(BackgroundKind(style.background))
        case .canvas: "\(Int(style.padding.rounded()))"
        }
    }

    private static func frameName(_ frame: ImageFrame) -> String {
        switch frame {
        case .none: String(localized: "None")
        case .macOSWindow: String(localized: "Window")
        case .browser: String(localized: "Browser")
        case .macBook: String(localized: "MacBook")
        case .iPhone: String(localized: "iPhone")
        }
    }

    private static func backgroundKindName(_ kind: BackgroundKind) -> String {
        switch kind {
        case .gradient: String(localized: "Gradient")
        case .customGradient: String(localized: "Custom")
        case .solid: String(localized: "Solid")
        case .image: String(localized: "Image")
        case .transparent: String(localized: "Transparent")
        }
    }
}

/// Canvas mode's dock: the current value of the controls that change most images, each
/// opening the inspector's own section in a popover.
struct CanvasDock: View {
    let settings: AppSettings
    let themes: CustomThemeStore
    let presets: PresetStore
    let entitlements: Entitlements
    let legibility: LegibilityModel
    let presetThumbnails: PresetThumbnailModel
    var stageRegions: StageRegionModel? = nil
    let presentFramePaywall: () -> Void

    @State private var openPane: InspectorPane?
    @State private var lastClose: DockPopoverClose?

    var body: some View {
        let style = settings.style
        HStack(spacing: VitrineTokens.Spacing.xxs) {
            ForEach(InspectorPane.dockPanes(usesImageContent: style.usesImageContent)) { pane in
                CanvasDockButton(
                    title: pane.dockTitle, value: pane.dockValue(in: style),
                    identifier: "canvas-dock-\(pane.rawValue)"
                ) {
                    openPane = DockPopoverClose.pane(
                        afterPressing: pane, open: openPane, lastClose: lastClose,
                        now: ProcessInfo.processInfo.systemUptime)
                }
                .background {
                    DockPopoverAnchor(isPresented: openPane == pane) {
                        lastClose = DockPopoverClose(
                            pane: pane, uptime: ProcessInfo.processInfo.systemUptime)
                        if openPane == pane { openPane = nil }
                    } content: { undoManager in
                        EditorInspectorView(
                            settings: settings, themes: themes, presets: presets,
                            entitlements: entitlements, legibility: legibility,
                            presetThumbnails: presetThumbnails, pane: pane,
                            presentFramePaywall: {
                                openPane = nil
                                presentFramePaywall()
                            },
                            windowUndoManager: undoManager)
                    }
                }
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                // It lies over the buttons, and its shape took their clicks.
                .allowsHitTesting(false)
        }
        // Four capped values and the longest Spanish titles stay under 840 pt, inside the
        // stage of the narrowest (940 pt) window.
        .fixedSize()
        .padding(.bottom, VitrineTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas dock")
        .accessibilityIdentifier("canvas-dock")
        // The swapped panes' popover closes with its button; it must not reopen on return.
        .onChange(of: style.usesImageContent) { openPane = nil }
        // A stage region opens its pane like the button would, so a second click closes it.
        .onChange(of: stageRegions?.reveal) { _, reveal in
            guard case .pane(let pane) = reveal?.target else { return }
            openPane = DockPopoverClose.pane(
                afterPressing: pane, open: openPane, lastClose: lastClose,
                now: ProcessInfo.processInfo.systemUptime)
        }
        #if DEBUG
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                if let flag = arguments.firstIndex(of: "--open-canvas-pane"),
                    arguments.indices.contains(flag + 1)
                {
                    openPane = InspectorPane(rawValue: arguments[flag + 1])
                }
            }
        #endif
    }
}

/// When a dock popover last closed. A click on its own button closes it on mouse down,
/// before the button's action runs, so that action must not reopen it.
struct DockPopoverClose: Equatable {
    let pane: InspectorPane
    let uptime: TimeInterval

    static func pane(
        afterPressing pane: InspectorPane, open: InspectorPane?, lastClose: DockPopoverClose?,
        now: TimeInterval
    ) -> InspectorPane? {
        if open == pane { return nil }
        if let lastClose, lastClose.pane == pane, now - lastClose.uptime < 0.5 { return nil }
        return pane
    }
}

/// An AppKit popover, because SwiftUI's is transient and closed whenever its color well,
/// open panel or paywall took focus. Semitransient closes only for clicks in the editor
/// window, Escape, or an explicit close.
private struct DockPopoverAnchor<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    let onClose: () -> Void
    @ViewBuilder let content: (UndoManager?) -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Never the hit view, so a click reaches the button in front of it.
    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView { AnchorView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onClose = onClose
        coordinator.isPresented = isPresented
        guard isPresented else { return coordinator.close() }
        guard coordinator.popover == nil else { return }
        // On the next turn, once the anchor is laid out in its window.
        Task { [weak view, content] in
            guard let view, let window = view.window, coordinator.isPresented,
                coordinator.popover == nil
            else { return }
            let hosting = NSHostingController(
                rootView: content(window.undoManager).onExitCommand { coordinator.close() })
            hosting.sizingOptions = .preferredContentSize
            let popover = NSPopover()
            popover.behavior = .semitransient
            popover.contentViewController = hosting
            popover.delegate = coordinator
            coordinator.popover = popover
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
            // Keyboard focus follows, so Tab reaches the section and Escape closes it.
            hosting.view.window?.makeKey()
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.onClose = nil
        coordinator.isPresented = false
        coordinator.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var popover: NSPopover?
        var onClose: (() -> Void)?
        var isPresented = false

        func close() { popover?.close() }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            onClose?()
        }
    }
}

private struct CanvasDockButton: View {
    let title: String
    let value: String
    let identifier: String
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: title)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .fixedSize()
                Text(verbatim: value)
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .monospacedDigit()
                    .foregroundStyle(VitrineTokens.Text.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120)
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovered ? VitrineTokens.Chrome.toolHoverFill : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isFocused ? VitrineTokens.Line.focusRing : .clear,
                        lineWidth: Brand.Stroke.focus)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .help(Text(verbatim: value))
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityIdentifier(identifier)
    }
}

/// Enters and leaves canvas mode from the stage's corner, so the stage keeps one route
/// that does not need the keyboard.
struct CanvasModeButton: View {
    let isCanvasMode: Bool
    let toggle: () -> Void

    var body: some View {
        let title =
            isCanvasMode
            ? String(localized: "Exit Canvas Mode") : String(localized: "Enter Canvas Mode")
        GlassIconButton(
            systemImage: isCanvasMode
                ? "arrow.down.right.and.arrow.up.left"
                : VitrineCommand.toggleCanvasMode.systemImageName,
            action: toggle
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(Text(verbatim: "\(title) (⇧⌘F)"))
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier("canvas-mode-button")
        .markToolbarAvoids()
        .padding(VitrineTokens.Spacing.sm)
    }
}

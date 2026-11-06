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

    @State private var openPane: InspectorPane?

    var body: some View {
        let style = settings.style
        HStack(spacing: VitrineTokens.Spacing.xxs) {
            ForEach(InspectorPane.dockPanes(usesImageContent: style.usesImageContent)) { pane in
                CanvasDockButton(
                    title: pane.dockTitle, value: pane.dockValue(in: style),
                    identifier: "canvas-dock-\(pane.rawValue)"
                ) { openPane = pane }
                .popover(isPresented: isOpen(pane), arrowEdge: .top) {
                    EditorInspectorView(
                        settings: settings, themes: themes, presets: presets,
                        entitlements: entitlements, legibility: legibility,
                        presetThumbnails: presetThumbnails, pane: pane)
                }
            }
        }
        .padding(5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
        }
        .fixedSize()
        .padding(.bottom, VitrineTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Canvas dock")
        .accessibilityIdentifier("canvas-dock")
        // The swapped panes' popover closes with its button; it must not reopen on return.
        .onChange(of: style.usesImageContent) { openPane = nil }
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

    private func isOpen(_ pane: InspectorPane) -> Binding<Bool> {
        Binding(
            get: { openPane == pane },
            set: { if !$0, openPane == pane { openPane = nil } })
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
                    .frame(maxWidth: 150)
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
        .padding(VitrineTokens.Spacing.sm)
    }
}

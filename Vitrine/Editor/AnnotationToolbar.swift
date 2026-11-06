import SwiftUI
import VitrineDomain
import VitrineRendering

enum AnnotationToolbarDensity: Equatable {
    case full
    case condensed
    case compact
}

/// The legend label of the selected counter, as the toolbar edits it.
struct AnnotationLegendEdit {
    let id: UUID
    let text: Binding<String>
    let isMasked: Bool
}

/// Types the legend label. An edit stays open until the field gives up focus, so typing is
/// one undo step.
private struct CounterLegendField: View {
    let legend: AnnotationLegendEdit
    let onEditEnded: () -> Void
    let onSubmitted: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(
                "Counter legend text", text: legend.text,
                prompt: Text("Legend").foregroundStyle(VitrineTokens.Text.tertiary)
            )
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit(submit)
            .onExitCommand(perform: submit)
            .accessibilityIdentifier("annotation-legend-field")
            if legend.isMasked {
                Image(systemName: "eye.slash")
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .help("Hidden in the export")
                    .accessibilityLabel("Hidden in the export")
                    .accessibilityIdentifier("annotation-legend-masked")
            }
        }
        .font(.system(size: VitrineTokens.FontSize.caption))
        .foregroundStyle(VitrineTokens.Text.primary)
        .padding(.horizontal, 8)
        .frame(width: 150, height: 25)
        .background(Capsule().fill(VitrineTokens.Surface.stage.opacity(0.6)))
        .overlay(
            Capsule().strokeBorder(
                isFocused ? VitrineTokens.Line.focusRing : VitrineTokens.Line.border,
                lineWidth: isFocused ? Brand.Stroke.focus : Brand.Stroke.hairline)
        )
        .onChange(of: isFocused) { _, focused in
            if !focused { onEditEnded() }
        }
        .onDisappear(perform: onEditEnded)
    }

    private func submit() {
        isFocused = false
        onSubmitted()
    }
}

/// The annotation tool palette in the editor's title bar, modeled on
/// CleanShot: a row of tools (the active one highlighted), then the active tool's
/// options — a color swatch that opens a palette, and a size slider. Picking a tool
/// puts the preview into draw mode; `Select` returns to move/resize.
struct AnnotationToolbar: View {
    @Binding var activeTool: AnnotationTool
    @Binding var color: Color
    @Binding var thickness: Double
    /// The emoji the sticker tool will place next; the sticker swatch
    /// edits it. Defaulted so existing call sites without the sticker option compile.
    var stickerGlyph: Binding<String>?
    /// Whether the current context (active tool, or the selected mark) exposes color
    /// / thickness — so the options only appear when they do something.
    let showsColor: Bool
    let showsThickness: Bool
    /// Undo/redo wiring. `shortcutsActive` gates the Cmd-Z / Cmd-Shift-Z
    /// shortcuts on the annotation context, so they never steal the code editor's own
    /// undo while typing code.
    let canUndo: Bool
    let canRedo: Bool
    let shortcutsActive: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    var hasSelection: Bool = false
    var onDuplicate: () -> Void = {}
    var canBringToFront: Bool = false
    var canSendToBack: Bool = false
    var onBringToFront: () -> Void = {}
    var onSendToBack: () -> Void = {}
    var density: AnnotationToolbarDensity = .full
    /// Closes a selected mark's color or size edit as one undo step.
    var onStyleEditEnded: () -> Void = {}
    var legend: AnnotationLegendEdit?
    /// Return or Escape in the legend field hands the keyboard back to the selected mark.
    var onLegendSubmitted: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                iconButton(
                    "arrow.uturn.backward", help: "Undo", identifier: "annotation-undo",
                    enabled: canUndo && shortcutsActive,
                    shortcut: KeyboardShortcut("z", modifiers: .command), action: onUndo)
                iconButton(
                    "arrow.uturn.forward", help: "Redo", identifier: "annotation-redo",
                    enabled: canRedo && shortcutsActive,
                    shortcut: KeyboardShortcut("z", modifiers: [.command, .shift]), action: onRedo)
                if density == .full {
                    selectionActionButtons
                } else {
                    selectionActionsMenu
                }
            }
            .padding(3)
            .background(Capsule().fill(VitrineTokens.Surface.stage.opacity(0.6)))
            .overlay(
                Capsule().strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline))

            if density == .compact {
                toolPicker
            } else {
                HStack(spacing: 2) {
                    ForEach(AnnotationTool.toolbarOrder) { tool in
                        AnnotationToolButton(tool: tool, activeTool: $activeTool)
                    }
                }
                .padding(3)
                .background(
                    Capsule().fill(VitrineTokens.Surface.stage.opacity(0.6))
                )
                .overlay(
                    Capsule().strokeBorder(
                        VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline))
            }

            if activeTool == .sticker, let stickerGlyph {
                StickerSwatchButton(glyph: stickerGlyph)
            }
            if showsColor {
                ColorSwatchButton(color: $color, onEditEnded: onStyleEditEnded)
            }
            if showsThickness {
                AnnotationSizeSlider(
                    thickness: $thickness, identifier: "annotation-thickness-slider",
                    onEditEnded: onStyleEditEnded)
            }
            if let legend {
                CounterLegendField(
                    legend: legend, onEditEnded: onStyleEditEnded, onSubmitted: onLegendSubmitted
                )
                .id(legend.id)
            }
        }
        // The toolbar lives in the title bar, which macOS treats as a window-drag
        // region — and dragging suppresses hover, so tooltips stop after the first
        // interaction. Backing it with a non-draggable view restores normal mouse
        // tracking (tooltips keep working); the surrounding title bar stays draggable
        // so the window can still be moved.
        .background(NonDraggableArea())
        .motionSensitiveAnimation(.easeInOut(duration: 0.15), value: showsColor)
        .motionSensitiveAnimation(.easeInOut(duration: 0.15), value: showsThickness)
    }

    /// Shortcuts for these live in the Edit menu (`AnnotationMarkAction`).
    @ViewBuilder private var selectionActionButtons: some View {
        iconButton(
            "plus.square.on.square", help: "Duplicate",
            identifier: "annotation-duplicate", enabled: hasSelection, action: onDuplicate)
        iconButton(
            "square.3.layers.3d.top.filled", help: "Bring to Front",
            identifier: "annotation-bring-front", enabled: canBringToFront,
            action: onBringToFront)
        iconButton(
            "square.3.layers.3d.bottom.filled", help: "Send to Back",
            identifier: "annotation-send-back", enabled: canSendToBack,
            action: onSendToBack)
    }

    private var selectionActionsMenu: some View {
        Menu {
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(!hasSelection)
            .accessibilityIdentifier("annotation-duplicate")

            Button(action: onBringToFront) {
                Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
            }
            .disabled(!canBringToFront)
            .accessibilityIdentifier("annotation-bring-front")

            Button(action: onSendToBack) {
                Label("Send to Back", systemImage: "square.3.layers.3d.bottom.filled")
            }
            .disabled(!canSendToBack)
            .accessibilityIdentifier("annotation-send-back")
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 26, height: 25)
                .foregroundStyle(
                    hasSelection ? VitrineTokens.Text.secondary : VitrineTokens.Text.tertiary
                )
                .contentShape(Rectangle())
        }
        .customLabelMenu(cornerRadius: 7)
        .fixedSize()
        .help("Selected mark actions")
        .accessibilityLabel("Selected mark actions")
        .accessibilityIdentifier("annotation-selection-actions-menu")
    }

    private var toolPicker: some View {
        Menu {
            ForEach(AnnotationTool.toolbarOrder) { tool in
                Button {
                    activeTool = tool
                } label: {
                    Label(tool.label, systemImage: tool.systemImage)
                }
                .accessibilityIdentifier("annotation-tool-\(tool.rawValue)")
            }
        } label: {
            Image(systemName: activeTool.systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(VitrineTokens.Accent.systemContrast)
                .frame(width: 30, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(VitrineTokens.Accent.system)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(3)
                .background(Capsule().fill(VitrineTokens.Surface.stage.opacity(0.6)))
                .overlay(
                    Capsule().strokeBorder(
                        VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline))
        }
        .customLabelMenu(cornerRadius: 14)
        .fixedSize()
        .help(Text("Annotation tool: \(Text(activeTool.label))"))
        .accessibilityLabel("Annotation tool")
        .accessibilityValue(activeTool.label)
        .accessibilityIdentifier("annotation-tool-picker")
    }

    private func iconButton(
        _ systemImage: String, help: LocalizedStringKey, identifier: String, enabled: Bool,
        shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 26, height: 25)
                .foregroundStyle(
                    enabled
                        ? VitrineTokens.Text.secondary : VitrineTokens.Text.tertiary.opacity(0.4)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(identifier)
    }
}

/// One tool in the row: accent fill when selected, a tint under the pointer.
private struct AnnotationToolButton: View {
    let tool: AnnotationTool
    @Binding var activeTool: AnnotationTool

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let isActive = activeTool == tool
        let button = Button {
            activeTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .padding(.bottom, 3)
                .frame(width: 28, height: 25)
                .foregroundStyle(
                    isActive
                        ? VitrineTokens.Accent.systemContrast
                        : (isHovered ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary)
                )
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isActive
                                ? VitrineTokens.Accent.system
                                : (isHovered ? VitrineTokens.Chrome.toolHoverFill : Color.clear))
                )
                .overlay(alignment: .bottomTrailing) {
                    if let shortcut = tool.shortcutCharacter {
                        Text(verbatim: "⌘\(shortcut)")
                            .font(.system(size: 7.5, weight: .heavy))
                            .foregroundStyle(
                                isActive
                                    ? VitrineTokens.Accent.systemContrast
                                    : (isHovered
                                        ? VitrineTokens.Text.secondary
                                        : VitrineTokens.Text.tertiary)
                            )
                            .padding(.trailing, 1)
                            .accessibilityHidden(true)
                    }
                }
                // Outside the tool, because the ring and the selected fill share a color.
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .inset(by: -1.5)
                        .stroke(
                            isFocused ? VitrineTokens.Line.focusRing : .clear,
                            lineWidth: Brand.Stroke.focus)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .motionSensitiveAnimation(.easeOut(duration: 0.15), value: isActive)
                .motionSensitiveAnimation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(AnnotationToolPressStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel(tool.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityIdentifier("annotation-tool-\(tool.rawValue)")

        // ⌘-digit selects the tool (⌘1…⌘9, ⌘0). A Command-modified shortcut fires
        // reliably on macOS and never hijacks the code editor's typing (a modifier-less
        // key would). Tools past the digit row have no shortcut and a plain tooltip.
        if let shortcut = tool.shortcutCharacter {
            button
                .help(Text("\(Text(tool.helpText)) (⌘\(String(shortcut)))"))
        } else {
            button.help(tool.helpText)
        }
    }
}

/// Press scales the tool; under Reduce Motion a dim takes its place, so a press still shows.
private struct AnnotationToolPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .modifier(
                DecorativeScaleEffect(
                    isActive: configuration.isPressed, scale: 0.94, reduceMotion: reduceMotion,
                    duration: 0.08))
    }
}

/// The current sticker glyph, opening the curated sticker palette as a popover
/// — the sticker-tool analogue of `ColorSwatchButton`.
private struct StickerSwatchButton: View {
    @Binding var glyph: String
    @State private var showsPalette = false

    var body: some View {
        Button {
            showsPalette.toggle()
        } label: {
            Text(verbatim: glyph)
                .font(.system(size: 15))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Sticker")
        .accessibilityLabel("Sticker picker")
        .accessibilityIdentifier("annotation-sticker-swatch")
        .popover(isPresented: $showsPalette, arrowEdge: .bottom) {
            // Two columns of five keeps the popover compact and every choice one click.
            let columns = [GridItem(.fixed(30)), GridItem(.fixed(30))]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(AnnotationTool.stickerChoices, id: \.self) { choice in
                    Button {
                        glyph = choice
                        showsPalette = false
                    } label: {
                        Text(verbatim: choice)
                            .font(.system(size: 17))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        choice == glyph
                                            ? VitrineTokens.Accent.system.opacity(0.25)
                                            : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: choice))
                }
            }
            .padding(10)
        }
    }
}

/// The stroke and badge size slider, shared by the title bar and the selected mark's toolbar.
struct AnnotationSizeSlider: View {
    @Binding var thickness: Double
    let identifier: String
    let onEditEnded: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "lineweight")
                .font(.system(size: 11))
                .foregroundStyle(VitrineTokens.Text.tertiary)
            Slider(value: $thickness, in: Annotation.thicknessRange) { editing in
                if !editing { onEditEnded() }
            }
            .frame(width: 84)
            .accessibilityLabel("Annotation size")
            .accessibilityIdentifier(identifier)
        }
        .help("Stroke and badge size")
    }
}

/// A color swatch that opens a vertical palette popover, with a custom-color
/// well at the bottom.
struct ColorSwatchButton: View {
    @Binding var color: Color
    var identifier = "annotation-color-swatch"
    let onEditEnded: () -> Void
    @State private var showsPalette = false

    private static let palette: [Color] = [
        Color(hex: "#1C1C1E"), Color(hex: "#FF453A"), Color(hex: "#FF9F0A"),
        Color(hex: "#FFD60A"), Color(hex: "#32D74B"), Color(hex: "#64D2FF"),
        Color(hex: "#0A84FF"), Color(hex: "#BF5AF2"), Color(hex: "#FF375F"),
        Color(hex: "#FFFFFF"),
    ]

    var body: some View {
        Button {
            showsPalette.toggle()
        } label: {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(VitrineTokens.Chrome.colorDotEdge, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .help("Color")
        .accessibilityLabel("Annotation color")
        .accessibilityIdentifier(identifier)
        .popover(isPresented: $showsPalette, arrowEdge: .bottom) {
            VStack(spacing: 7) {
                ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, swatch in
                    Button {
                        color = swatch
                        onEditEnded()
                        showsPalette = false
                    } label: {
                        Circle()
                            .fill(swatch)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(
                                    swatch.isApproximately(color)
                                        ? VitrineTokens.Accent.system
                                        : VitrineTokens.Chrome.paletteDotEdge,
                                    lineWidth: swatch.isApproximately(color) ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(width: 22)
                ColorPicker("Custom color", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityIdentifier("annotation-custom-color")
            }
            .padding(10)
            .onDisappear(perform: onEditEnded)
        }
    }
}

extension Color {
    /// Whether two colors resolve to the same fixed sRGB value (for marking the
    /// active palette swatch). Compares the persisted `RGBAColor` representation so
    /// sub-`1e-4` color-space drift never hides the selection.
    fileprivate func isApproximately(_ other: Color) -> Bool {
        RGBAColor(self) == RGBAColor(other)
    }
}

/// A non-draggable backing for title-bar content. macOS lets you drag a
/// window by its title-bar content, and that drag tracking suppresses hover — so
/// `.help()` tooltips stop appearing after the first interaction. An `NSView` that
/// reports `mouseDownCanMoveWindow == false` keeps its region from moving the window,
/// which restores normal mouse tracking for the controls placed in front of it.
private struct NonDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NonDraggableBackingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NonDraggableBackingView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

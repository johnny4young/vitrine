import SwiftUI

/// The annotation tool palette in the editor's title bar (CS-085), modeled on
/// CleanShot: a row of tools (the active one highlighted), then the active tool's
/// options — a color swatch that opens a palette, and a size slider. Picking a tool
/// puts the preview into draw mode; `Select` returns to move/resize.
struct AnnotationToolbar: View {
    @Binding var activeTool: AnnotationTool
    @Binding var color: Color
    @Binding var thickness: Double
    /// The emoji the sticker tool will place next (feature #13); the sticker swatch
    /// edits it. Defaulted so existing call sites without the sticker option compile.
    var stickerGlyph: Binding<String>?
    /// Whether the current context (active tool, or the selected mark) exposes color
    /// / thickness — so the options only appear when they do something.
    let showsColor: Bool
    let showsThickness: Bool
    /// Undo/redo wiring (CS-086). `shortcutsActive` gates the Cmd-Z / Cmd-Shift-Z
    /// shortcuts on the annotation context, so they never steal the code editor's own
    /// undo while typing code.
    let canUndo: Bool
    let canRedo: Bool
    let shortcutsActive: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                historyButton(
                    "arrow.uturn.backward", help: "Undo", identifier: "annotation-undo",
                    enabled: canUndo && shortcutsActive,
                    shortcut: KeyboardShortcut("z", modifiers: .command), action: onUndo)
                historyButton(
                    "arrow.uturn.forward", help: "Redo", identifier: "annotation-redo",
                    enabled: canRedo && shortcutsActive,
                    shortcut: KeyboardShortcut("z", modifiers: [.command, .shift]), action: onRedo)
            }
            .padding(3)
            .background(Capsule().fill(VitrineTokens.Surface.stage.opacity(0.6)))
            .overlay(
                Capsule().strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline))

            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    toolButton(tool)
                }
            }
            .padding(3)
            .background(
                Capsule().fill(VitrineTokens.Surface.stage.opacity(0.6))
            )
            .overlay(
                Capsule().strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline))

            if activeTool == .sticker, let stickerGlyph {
                StickerSwatchButton(glyph: stickerGlyph)
            }
            if showsColor {
                ColorSwatchButton(color: $color)
            }
            if showsThickness {
                HStack(spacing: 5) {
                    Image(systemName: "lineweight")
                        .font(.system(size: 11))
                        .foregroundStyle(VitrineTokens.Text.tertiary)
                    Slider(value: $thickness, in: Annotation.thicknessRange)
                        .frame(width: 84)
                        .accessibilityLabel("Annotation size")
                        .accessibilityIdentifier("annotation-thickness-slider")
                }
                .help("Stroke and badge size")
            }
        }
        // The toolbar lives in the title bar, which macOS treats as a window-drag
        // region — and dragging suppresses hover, so tooltips stop after the first
        // interaction. Backing it with a non-draggable view restores normal mouse
        // tracking (tooltips keep working); the surrounding title bar stays draggable
        // so the window can still be moved (CS-087).
        .background(NonDraggableArea())
        .animation(.easeInOut(duration: 0.15), value: showsColor)
        .animation(.easeInOut(duration: 0.15), value: showsThickness)
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button {
            activeTool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 28, height: 25)
                .foregroundStyle(
                    activeTool == tool
                        ? VitrineTokens.Accent.systemContrast : VitrineTokens.Text.secondary
                )
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(activeTool == tool ? VitrineTokens.Accent.system : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        // ⌘-digit selects the tool (⌘1…⌘8). A Command-modified shortcut fires reliably on
        // macOS and never hijacks the code editor's typing (a modifier-less key would).
        .keyboardShortcut(tool.keyEquivalent, modifiers: .command)
        .help(Text(tool.label) + Text(verbatim: " (⌘\(tool.keyEquivalent.character))"))
        .accessibilityLabel(tool.label)
        .accessibilityIdentifier("annotation-tool-\(tool.rawValue)")
    }

    private func historyButton(
        _ systemImage: String, help: LocalizedStringKey, identifier: String, enabled: Bool,
        shortcut: KeyboardShortcut, action: @escaping () -> Void
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

/// The current sticker glyph, opening the curated sticker palette as a popover
/// (feature #13) — the sticker-tool analogue of `ColorSwatchButton`.
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

/// A color swatch that opens a vertical palette popover (CS-085), with a custom-color
/// well at the bottom.
private struct ColorSwatchButton: View {
    @Binding var color: Color
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
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .help("Color")
        .accessibilityLabel("Annotation color")
        .accessibilityIdentifier("annotation-color-swatch")
        .popover(isPresented: $showsPalette, arrowEdge: .bottom) {
            VStack(spacing: 7) {
                ForEach(Array(Self.palette.enumerated()), id: \.offset) { _, swatch in
                    Button {
                        color = swatch
                        showsPalette = false
                    } label: {
                        Circle()
                            .fill(swatch)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(
                                    swatch.isApproximately(color)
                                        ? VitrineTokens.Accent.system : .white.opacity(0.25),
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

/// A non-draggable backing for title-bar content (CS-087). macOS lets you drag a
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

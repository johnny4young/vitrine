import SwiftUI
import VitrineRendering

// The shared chrome components of the current designed surfaces.
// Every visual value here resolves through `VitrineTokens`; the shapes and
// measurements mirror the design-system component classes one to one, so the
// Settings window, the editor inspector, and the menu-bar panel all read as the
// same design system.

/// The uppercase, letter-spaced group label above a tile.
struct TokenGroupLabel: View {
    let title: Text

    var body: some View {
        title
            .font(.system(size: VitrineTokens.FontSize.caption, weight: .semibold))
            .foregroundStyle(VitrineTokens.Text.tertiary)
            .textCase(.uppercase)
            .tracking(VitrineTokens.FontSize.caption * 0.07)
    }
}

/// A grouped-form section: optional uppercase label + a rounded tile of rows
/// Uses the shared tile fill, hairline border, and 14-point radius.
struct TokenGroup<Content: View>: View {
    var title: Text? = nil
    /// Optional explanatory line under the section label — for clarifying a
    /// section's scope (e.g. what "Theme" affects versus the rest of "Style").
    var caption: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || caption != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        TokenGroupLabel(title: title)
                    }
                    if let caption {
                        caption
                            .font(.system(size: VitrineTokens.FontSize.caption))
                            .foregroundStyle(VitrineTokens.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, VitrineTokens.Spacing.md)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                    .fill(VitrineTokens.Chrome.tile)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VitrineTokens.Radius.lg, style: .continuous)
                    .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
            )
        }
    }
}

/// One label + optional caption + trailing control row inside a `TokenGroup`
/// Uses 9-point vertical padding and a 12-point gap.
struct TokenRow<Content: View>: View {
    var label: Text? = nil
    var caption: Text? = nil
    /// Puts the caption behind an info button, for a column too narrow to read it inline.
    var captionInPopover = false
    @ViewBuilder var content: Content

    @State private var showsCaption = false

    var body: some View {
        // Center the trailing control against the *label line* (always one line,
        // stable) and let the caption flow full-width beneath it — the macOS
        // System Settings layout. This keeps the control's vertical position
        // fixed when the caption reflows (e.g. toggling a segmented option whose
        // description grows or shrinks), instead of re-centering the control
        // against a label+caption block whose height changes.
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: VitrineTokens.Spacing.sm) {
                if let label {
                    label
                        .font(.system(size: VitrineTokens.FontSize.body))
                        .foregroundStyle(VitrineTokens.Text.primary)
                }
                if captionInPopover, let caption {
                    Button {
                        showsCaption = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: VitrineTokens.FontSize.subhead))
                            .foregroundStyle(VitrineTokens.Text.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More information")
                    .accessibilityValue(label ?? Text(verbatim: ""))
                    .accessibilityHint(caption)
                    .popover(isPresented: $showsCaption) {
                        caption
                            .font(.system(size: VitrineTokens.FontSize.subhead))
                            .frame(width: 260, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(VitrineTokens.Spacing.sm)
                    }
                }
                Spacer(minLength: VitrineTokens.Spacing.sm)
                // When a caption exists, attach it to the control as its VoiceOver hint
                // so the explanation is announced together with the control;
                // no caption means no hint, rather than an empty one. The visible caption
                // stays accessible below — for a single control that is a harmless second
                // read, but for a composite control (several buttons in an HStack) the
                // hint may not reach the focused child, so keeping the caption as its own
                // element is what stops the explanation from being lost.
                if let caption {
                    content.accessibilityHint(caption)
                } else {
                    content
                }
            }
            if let caption, !captionInPopover {
                caption
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
    }
}

/// The pill segmented control: a capsule track of small
/// capsule buttons; the selected one lifts onto a card-colored pill.
struct TokenSegmentedPicker<Value: Hashable>: View {
    /// The selectable values, in display order, each with its visible label.
    let options: [(value: Value, label: Text)]
    @Binding var selection: Value
    /// When `true`, segments stretch to share the available width equally
    /// (the sticky style sub-tabs); otherwise the control hugs its content.
    var fillsWidth: Bool = false
    /// Optional stable identifiers, one per option in order, so UI tests can
    /// address individual segments independently of their localized titles.
    var optionIdentifiers: [String]? = nil
    @FocusState private var isFocused: Bool
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        track
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(VitrineTokens.Chrome.segmentTrack)
            )
            // One key-view stop that follows the system keyboard-navigation setting, so a
            // mouse click never takes focus from the editor, like a native segmented control.
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(.leftArrow) {
                move(by: layoutDirection == .leftToRight ? -1 : 1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                move(by: layoutDirection == .leftToRight ? 1 : -1)
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue(selectedLabel)
    }

    /// The segments, laid out so they can never overflow the control's column.
    ///
    /// A hugging control's segments are `fixedSize`, so they refuse to compress: an
    /// `HStack` that runs out of width does not shrink them, it overflows, and the window
    /// clips the last segment mid-word — a five-option picker in the editor's inspector did
    /// exactly that. Flowing them wraps to a second line instead, which is why the track is
    /// a rounded rectangle rather than a capsule: a capsule around two lines reads as a
    /// lozenge. At a width that fits, the flow lays out on one line and the shape is
    /// indistinguishable from the capsule it replaces.
    ///
    /// A filling control keeps the `HStack`: its segments share the width equally and
    /// shrink with it, so they have nothing to overflow.
    @ViewBuilder private var track: some View {
        if fillsWidth {
            HStack(spacing: 2) { segments }
        } else {
            FlowLayout(spacing: 2, lineSpacing: 2) { segments }
        }
    }

    @ViewBuilder private var segments: some View {
        ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
            segment(option.value, label: option.label)
                .accessibilityIdentifier(identifier(at: index))
        }
    }

    /// The selected option's label, surfaced as the control's accessibility value so
    /// VoiceOver announces "<label>: <selection>" like a native segmented control.
    private var selectedLabel: Text {
        options.first { $0.value == selection }?.label ?? Text(verbatim: "")
    }

    private func identifier(at index: Int) -> String {
        guard let optionIdentifiers, index < optionIdentifiers.count else { return "" }
        return optionIdentifiers[index]
    }

    private func segment(_ value: Value, label: Text) -> some View {
        let isSelected = value == selection
        return Button {
            select(value)
        } label: {
            label
                .font(.system(size: VitrineTokens.FontSize.caption, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(
                    isSelected ? VitrineTokens.Accent.systemContrast : VitrineTokens.Text.secondary
                )
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .background {
                    if isSelected {
                        // The selected segment lifts onto a system-accent pill so the
                        // control follows the user's macOS accent like the rest of the
                        // chrome (selection/links/chips), instead of a neutral white card.
                        Capsule(style: .continuous)
                            .fill(VitrineTokens.Accent.system)
                            .brandShadow(VitrineTokens.Chrome.segmentShadow)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .overlay {
            if isFocused && isSelected {
                Capsule().strokeBorder(VitrineTokens.Line.focusRing, lineWidth: Brand.Stroke.focus)
                    .padding(-2)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func select(_ value: Value) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { selection = value }
    }

    private func move(by offset: Int) {
        guard let index = options.firstIndex(where: { $0.value == selection }) else { return }
        let next = index + offset
        guard options.indices.contains(next) else { return }
        select(options[next].value)
    }
}

/// The bordered inline text field of the current designed forms (`.dfield`): fixed
/// 160 pt, right-aligned, hairline border that turns into the accent focus
/// ring while editing.
struct TokenTextField: View {
    let prompt: Text
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: prompt.foregroundStyle(VitrineTokens.Text.tertiary))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .multilineTextAlignment(.trailing)
            .font(.system(size: VitrineTokens.FontSize.subhead))
            .foregroundStyle(VitrineTokens.Text.primary)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .frame(width: 160)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VitrineTokens.Chrome.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused ? VitrineTokens.Line.focusRing : VitrineTokens.Line.border,
                        lineWidth: isFocused ? Brand.Stroke.focus : Brand.Stroke.hairline
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .inset(by: -1.5)
                    .stroke(
                        isFocused ? VitrineTokens.Line.focusGlow : .clear,
                        lineWidth: 3
                    )
            )
    }
}

/// How far a chip strip can scroll and where it is, in the scroll view's own offsets.
nonisolated struct ChipScrollExtent: Equatable {
    /// The width of the edge fades, reserved after the last chip so it clears them.
    static let fadeWidth: CGFloat = 26
    /// The strip's normal breathing room at each end.
    static let edgeInset: CGFloat = 2

    var offset: CGFloat = 0
    var visibleWidth: CGFloat = 0
    var chipsWidth: CGFloat = 0

    /// The reserved trailing inset is excluded: counting it would report overflow for a
    /// strip that fits exactly. The 0.5 pt slack absorbs fractional layout rounding.
    var overflows: Bool { chipsWidth + Self.edgeInset > visibleWidth + 0.5 }

    private var startOffset: CGFloat { -Self.edgeInset }
    private var endOffset: CGFloat {
        max(startOffset, chipsWidth + Self.fadeWidth - visibleWidth)
    }

    var edges: ChipScrollEdges {
        ChipScrollEdges(
            overflows: overflows,
            hidesLeading: overflows && offset > startOffset + 1,
            hidesTrailing: overflows && offset < endOffset - 1)
    }

    /// One page on, keeping the chips under the fades in view; at the end, back to the start.
    /// In `ScrollPosition.scrollTo(x:)` terms, which count from the chips, not the margin.
    var nextScrollX: CGFloat {
        guard edges.hidesTrailing else { return 0 }
        return min(endOffset, offset + visibleWidth - 2 * Self.fadeWidth) + Self.edgeInset
    }
}

/// What a chip strip's cue shows. Kept apart from the offset so scrolling redraws the
/// strip only when an edge changes.
nonisolated struct ChipScrollEdges: Equatable {
    var overflows = false
    var hidesLeading = false
    var hidesTrailing = false
}

/// A chip strip's scroll state, shared with its chips by identity. The live extent is not
/// observed, so scrolling redraws nothing until an edge changes.
@Observable
final class ChipScrollModel {
    var position = ScrollPosition(idType: String.self)
    var edges = ChipScrollEdges()
    @ObservationIgnored var extent = ChipScrollExtent()

    func track(_ new: ChipScrollExtent) {
        extent = new
        if edges != new.edges { edges = new.edges }
    }

    func scroll(animated: Bool, _ change: (inout ScrollPosition) -> Void) {
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) { change(&position) }
    }
}

extension EnvironmentValues {
    @Entry var chipScrollModel: ChipScrollModel?
}

extension View {
    /// Marks a chip of a `ChipScroll` so selecting it brings it clear of the edge fades.
    func chipScrollItem(id: String, isSelected: Bool) -> some View {
        modifier(ChipScrollItem(id: id, isSelected: isSelected))
    }
}

private struct ChipScrollItem: ViewModifier {
    let id: String
    let isSelected: Bool

    @Environment(\.chipScrollModel) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isClearOfFades = false

    func body(content: Content) -> some View {
        let fadeWidth = ChipScrollExtent.fadeWidth
        return
            content
            .id(id)
            .onGeometryChange(for: Bool.self) { proxy in
                guard let visible = proxy.bounds(of: .scrollView) else { return false }
                let clear = visible.insetBy(dx: fadeWidth, dy: 0)
                return clear.minX <= 0 && proxy.size.width <= clear.maxX
            } action: {
                isClearOfFades = $0
            }
            .onAppear { reveal(animated: false) }
            .onChange(of: isSelected) { reveal(animated: !reduceMotion) }
            // Overflow is first known after layout, the earliest a scroll can reach a chip.
            .onChange(of: model?.edges.overflows ?? false) { reveal(animated: false) }
    }

    private func reveal(animated: Bool) {
        guard isSelected else { return }
        Task {
            // A scroll requested during the layout pass that reported this is dropped.
            await Task.yield()
            guard !isClearOfFades else { return }
            model?.scroll(animated: animated) { $0.scrollTo(id: id, anchor: .center) }
        }
    }
}

/// A horizontally scrolling chip strip (`.hscroll`): 7 pt gaps and a hidden scroller.
///
/// While chips overflow, each edge hiding chips fades and a button pages through them, so
/// the strip also scrolls without a trackpad. Nothing is drawn when the chips fit. Reduce
/// Transparency swaps the fades for a hard clip; the button stays opaque either way.
struct ChipScroll<Content: View>: View {
    /// Prefixes the button's identifier, `<name>-chip-scroll-button`.
    let name: String
    var topPadding: CGFloat = 12
    var bottomPadding: CGFloat = 12
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var model = ChipScrollModel()

    private var edges: ChipScrollEdges { model.edges }

    var body: some View {
        @Bindable var model = model
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                content
            }
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
        // Margins, not padding: `contentSize` then stays the chips alone, so varying the
        // trailing one can't feed back into the overflow it depends on.
        .contentMargins(.leading, ChipScrollExtent.edgeInset, for: .scrollContent)
        .contentMargins(
            .trailing, edges.overflows ? ChipScrollExtent.fadeWidth : ChipScrollExtent.edgeInset,
            for: .scrollContent
        )
        .scrollPosition($model.position)
        .onScrollGeometryChange(for: ChipScrollExtent.self) { geometry in
            ChipScrollExtent(
                offset: geometry.contentOffset.x,
                // Not `containerSize`, which shrinks with the margins this feeds.
                visibleWidth: geometry.visibleRect.width,
                chipsWidth: geometry.contentSize.width)
        } action: { _, new in
            model.track(new)
        }
        .mask(fade)
        .overlay(alignment: .trailing) {
            if edges.overflows { pageButton }
        }
        .environment(\.chipScrollModel, model)
    }

    /// One button whose direction flips at the end, so it never vanishes under keyboard
    /// focus the way a pair of edge buttons would.
    private var pageButton: some View {
        let label = edges.hidesTrailing ? Text("Show more") : Text("Back to start")
        return Button {
            let target = model.extent.nextScrollX
            model.scroll(animated: !reduceMotion) { $0.scrollTo(x: target) }
        } label: {
            Image(systemName: edges.hidesTrailing ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(VitrineTokens.Text.secondary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(VitrineTokens.Surface.card))
                .overlay(
                    Circle().strokeBorder(
                        VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(name)-chip-scroll-button")
    }

    /// Opaque across the strip, fading out over `fadeWidth` at each edge hiding chips.
    private var fade: some View {
        HStack(spacing: 0) {
            edgeMask(fades: edges.hidesLeading, from: .leading, to: .trailing)
            Color.black
            edgeMask(fades: edges.hidesTrailing, from: .trailing, to: .leading)
        }
    }

    @ViewBuilder
    private func edgeMask(fades: Bool, from start: UnitPoint, to end: UnitPoint) -> some View {
        if fades && !reduceTransparency {
            LinearGradient(colors: [.clear, .black], startPoint: start, endPoint: end)
                .frame(width: ChipScrollExtent.fadeWidth)
        } else {
            Color.black.frame(width: ChipScrollExtent.fadeWidth)
        }
    }
}

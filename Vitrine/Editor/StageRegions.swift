import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// A part of the rendered capture that opens the inspector section styling it.
enum StageRegion: String, CaseIterable, Identifiable {
    case background, shadow, chrome, header, content

    var id: String { rawValue }

    /// The section a click opens, in the inspector or as canvas mode's dock popover.
    func target(usesImageContent: Bool) -> InspectorReveal.Target {
        switch self {
        case .background: .pane(.background)
        case .shadow: .pane(.canvas)
        case .chrome: .pane(usesImageContent ? .frame : .canvas)
        case .header: .header
        case .content: .pane(usesImageContent ? .frame : .typography)
        }
    }

    /// The dock has no header pane, so canvas mode leaves the header alone.
    func isRoutable(usesImageContent: Bool, isCanvasMode: Bool) -> Bool {
        !isCanvasMode || target(usesImageContent: usesImageContent) != .header
    }

    func actionName(usesImageContent: Bool) -> String {
        switch self {
        case .background: String(localized: "Edit Background")
        case .shadow: String(localized: "Edit Shadow")
        case .chrome: String(localized: "Edit Window Chrome")
        case .header: String(localized: "Edit Header")
        case .content:
            usesImageContent
                ? String(localized: "Edit Frame") : String(localized: "Edit Typography")
        }
    }

    /// The regions a capture styled by `config` draws, in hit-test order.
    static func drawn(by config: SnapshotConfig) -> [StageRegion] {
        let code = !config.usesImageContent
        return [
            code && config.showChrome ? .chrome : nil,
            code && !config.metadata.isEmpty ? .header : nil,
            .content,
            config.showShadow ? .shadow : nil,
            .background,
        ].compactMap { $0 }
    }
}

/// A stage click's request to open a section; the generation repeats a request for the same one.
struct InspectorReveal: Equatable {
    enum Target: Equatable {
        case pane(InspectorPane)
        case header
    }

    let target: Target
    let generation: Int
}

/// The hot regions in the canvas's own coordinates, built from the parts the renderer laid out.
struct StageRegionLayout: Equatable {
    private(set) var rects: [StageRegion: CGRect] = [:]

    init() {}

    /// The card splits into bands at the midpoints between its parts, so every point of it
    /// belongs to one. The shadow is the card's offset footprint, half its blur wide.
    init(
        canvas: CGRect, card: CGRect?, chrome: CGRect? = nil, header: CGRect? = nil,
        code: CGRect? = nil, shadow: Brand.ShadowStyle? = nil
    ) {
        rects[.background] = canvas
        guard let card else { return }
        let parts: [(StageRegion, CGRect)] = [
            chrome.map { (.chrome, $0) }, header.map { (.header, $0) },
            code.map { (.content, $0) },
        ].compactMap { $0 }
        var top = card.minY
        for (index, (region, rect)) in parts.enumerated() {
            let bottom =
                index + 1 < parts.count ? (rect.maxY + parts[index + 1].1.minY) / 2 : card.maxY
            rects[region] = CGRect(x: card.minX, y: top, width: card.width, height: bottom - top)
            top = bottom
        }
        if parts.isEmpty { rects[.content] = card }
        if let shadow, shadow.radius > 0 {
            let spread = shadow.radius / 2
            rects[.shadow] = card.offsetBy(dx: shadow.x, dy: shadow.y)
                .insetBy(dx: -spread, dy: -spread).intersection(canvas)
        }
    }

    func rect(for region: StageRegion) -> CGRect? { rects[region] }

    /// The card's bands first, then its shadow, then the background around them.
    func region(at point: CGPoint) -> StageRegion? {
        let order: [StageRegion] = [.chrome, .header, .content, .shadow, .background]
        return order.first { rects[$0]?.contains(point) == true }
    }
}

/// Hover and click state for the stage regions, kept out of the editor's body.
@Observable
final class StageRegionModel {
    /// Read only by gestures, so a layout pass invalidates nothing.
    @ObservationIgnored var layout = StageRegionLayout()
    var hovered: StageRegion?
    /// The last region clicked, which Reduce Motion still outlines.
    private(set) var clicked: StageRegion?
    private(set) var reveal: InspectorReveal?

    func hover(_ region: StageRegion?) {
        guard region != hovered else { return }
        hovered = region
        if region != clicked { clicked = nil }
    }

    func route(_ region: StageRegion, usesImageContent: Bool) {
        clicked = region
        reveal = InspectorReveal(
            target: region.target(usesImageContent: usesImageContent),
            generation: (reveal?.generation ?? 0) + 1)
    }
}

/// Routes clicks, hovers and accessibility actions on the canvas to the inspector. The
/// canvas sits below the annotation overlay, so marks, handles and an active selection or
/// draw tool take their clicks first.
struct StageRegionRouting: ViewModifier {
    let model: StageRegionModel
    let config: SnapshotConfig
    let canvasSize: CGSize
    let isCanvasMode: Bool
    /// The select tool with no mark selected or being edited.
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let usesImage = config.usesImageContent
        content
            .overlayPreferenceValue(CanvasPartAnchorsKey.self) { anchors in
                GeometryReader { proxy in
                    let layout = StageRegionLayout(
                        canvas: CGRect(origin: .zero, size: canvasSize),
                        card: anchors[.card].map { proxy[$0] },
                        chrome: anchors[.chrome].map { proxy[$0] },
                        header: anchors[.header].map { proxy[$0] },
                        code: anchors[.code].map { proxy[$0] },
                        shadow: config.showShadow ? shadowStyle : nil)
                    ZStack {
                        Color.clear.onChange(of: layout, initial: true) { model.layout = layout }
                        StageRegionOutline(
                            model: model, layout: layout, isEnabled: isEnabled,
                            scale: proxy.size.width > 0
                                ? proxy.frame(in: .global).width / proxy.size.width : 1)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onContinuousHover { phase in
                guard isEnabled, case .active(let point) = phase else { return model.hover(nil) }
                model.hover(routableRegion(at: point))
            }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    guard isEnabled, let region = routableRegion(at: value.location) else {
                        return
                    }
                    model.route(region, usesImageContent: usesImage)
                },
                including: isEnabled ? .all : .subviews
            )
            .background {
                GeometryReader { proxy in
                    SelectableTextClicks(size: proxy.size) { point in
                        guard isEnabled, routableRegion(at: point) == .content else { return }
                        model.route(.content, usesImageContent: usesImage)
                    }
                }
                .accessibilityHidden(true)
            }
            .onChange(of: isEnabled) { if !isEnabled { model.hover(nil) } }
            .accessibilityActions {
                ForEach(StageRegion.drawn(by: config)) { region in
                    if region.isRoutable(usesImageContent: usesImage, isCanvasMode: isCanvasMode) {
                        Button(region.actionName(usesImageContent: usesImage)) {
                            model.route(region, usesImageContent: usesImage)
                        }
                    }
                }
            }
    }

    private var shadowStyle: Brand.ShadowStyle {
        Brand.ShadowStyle(
            color: Brand.Shadow.elevated.color, radius: config.effectiveShadowRadius,
            x: Brand.Shadow.elevated.x, y: Brand.Shadow.elevated.y)
    }

    private func routableRegion(at point: CGPoint) -> StageRegion? {
        guard let region = model.layout.region(at: point),
            region.isRoutable(
                usesImageContent: config.usesImageContent, isCanvasMode: isCanvasMode)
        else { return nil }
        return region
    }
}

/// A dashed outline on the hovered region, kept a constant width on screen. Under Reduce
/// Motion it appears only after a click.
private struct StageRegionOutline: View {
    let model: StageRegionModel
    let layout: StageRegionLayout
    let isEnabled: Bool
    let scale: CGFloat

    @ReducesMotion private var reduceMotion

    var body: some View {
        if isEnabled, let region = model.hovered, !reduceMotion || model.clicked == region,
            let rect = layout.rect(for: region)
        {
            let unit = 1 / max(scale, 0.01)
            RoundedRectangle(cornerRadius: 4 * unit, style: .continuous)
                .strokeBorder(
                    VitrineTokens.Line.focusRing,
                    style: StrokeStyle(lineWidth: 1.5 * unit, dash: [4 * unit, 3 * unit])
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

/// Selectable code text is an AppKit field that tracks the mouse itself, so SwiftUI never sees
/// a click on it. This view reports one that ended where it began, in the canvas's coordinates.
private struct SelectableTextClicks: NSViewRepresentable {
    let size: CGSize
    let onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> WatcherView { WatcherView() }

    func updateNSView(_ view: WatcherView, context: Context) {
        view.size = size
        view.onClick = onClick
    }

    static func dismantleNSView(_ view: WatcherView, coordinator: ()) { view.stopMonitoring() }

    final class WatcherView: NSView {
        var size: CGSize = .zero
        var onClick: ((CGPoint) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] in
                self?.mouseDownSeen($0)
                return $0
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func mouseDownSeen(_ event: NSEvent) {
            guard event.window === window, event.clickCount == 1,
                let content = window?.contentView, let frame = content.superview,
                content.hitTest(frame.convert(event.locationInWindow, from: nil)) is NSTextField
            else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { return }
            let local = CGPoint(
                x: point.x / bounds.width * size.width,
                y: (isFlipped ? point.y : bounds.height - point.y) / bounds.height * size.height)
            let down = event.locationInWindow
            // Default mode runs only once the field's tracking loop has taken the mouse-up.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let up = NSApp.currentEvent, up.type == .leftMouseUp,
                        up.window === self.window,
                        hypot(up.locationInWindow.x - down.x, up.locationInWindow.y - down.y) < 4
                    else { return }
                    self.onClick?(local)
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
}

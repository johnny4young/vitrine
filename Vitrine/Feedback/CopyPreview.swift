import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import VitrineRendering

/// A floating preview of the image just copied, like the macOS screenshot thumbnail:
/// drag it into another app, click it to reopen where it came from, or dismiss it.
///
/// It holds only the copied PNG, already redacted, never the source text, and writes a
/// file only when a drop asks for one.
enum CopyPreview {
    struct Item {
        let png: Data
        let reopen: () -> Void
    }

    /// A concealed copy asked clipboard managers to keep it out of sight, so it never
    /// floats on screen either.
    static func isShown(for behavior: OutputBehavior) -> Bool {
        behavior.showsCopyPreview && !behavior.concealClipboard
    }

    /// Long enough to start a drag; VoiceOver users get time to reach the panel.
    static func lifetime(voiceOverRunning: Bool) -> Duration {
        voiceOverRunning ? .seconds(20) : .seconds(6)
    }

    static let maximumSize = CGSize(width: 220, height: 150)

    /// The aspect-fit size of `imageSize` inside ``maximumSize``.
    static func displaySize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return maximumSize }
        let scale = min(
            maximumSize.width / imageSize.width, maximumSize.height / imageSize.height, 1)
        return CGSize(
            width: max((imageSize.width * scale).rounded(), 24),
            height: max((imageSize.height * scale).rounded(), 24))
    }

    /// The bottom-trailing corner of `visible`, far from the HUD and the menu bar above.
    static let inset = Brand.Spacing.md

    /// The panel's size for a preview of `displaySize`, set up front because the hosting
    /// view can report a zero fitting size before its first layout pass.
    static func panelSize(for displaySize: CGSize) -> CGSize {
        CGSize(width: displaySize.width + inset * 2, height: displaySize.height + inset * 2)
    }

    static func frame(for size: CGSize, in visible: CGRect) -> CGRect {
        let margin = Brand.Spacing.md
        return CGRect(
            x: visible.maxX - size.width - margin, y: visible.minY + margin,
            width: size.width, height: size.height)
    }

    /// Timestamped like a macOS screenshot; a drop never overwrites an existing file.
    static func fileName(at date: Date) -> String {
        let day = date.formatted(dayStyle)
        let time = date.formatted(timeStyle)
        return String(
            localized: "Vitrine \(day) at \(time).png",
            comment: "File name of a copied image dropped from the copy preview: date, time")
    }

    private static let dayStyle = Date.VerbatimFormatStyle(
        format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
        timeZone: .current, calendar: Calendar(identifier: .gregorian))
    private static let timeStyle = Date.VerbatimFormatStyle(
        format:
            "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
        timeZone: .current, calendar: Calendar(identifier: .gregorian))

    /// Decodes a small image for display, so a large copy is never held at full size.
    static func thumbnail(of png: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// The pasteboard item a drag carries: the copied PNG for apps that take image data,
/// and a file promise that Finder and others fulfill only on drop.
nonisolated final class CopiedImagePromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let png: Data
    let fileName: String
    private static let writeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(png: Data, fileName: String) {
        self.png = png
        self.fileName = fileName
        super.init()
        fileType = UTType.png.identifier
        delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.png]
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .png ? png : super.pasteboardPropertyList(forType: type)
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String
    ) -> String {
        fileName
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.writeQueue
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            try png.write(to: url, options: .withoutOverwriting)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

/// Click, drag and hover over the preview image, tracked even while another app is active.
final class CopyPreviewDragView: NSView, NSDraggingSource {
    var png = Data()
    var image: CGImage?
    var onClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onDragBegan: () -> Void = {}
    var onDragEnded: (_ delivered: Bool) -> Void = { _ in }
    private var mouseDown: NSEvent?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func mouseDown(with event: NSEvent) { mouseDown = event }

    override func mouseUp(with event: NSEvent) {
        if mouseDown != nil { onClick() }
        mouseDown = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDown else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        guard hypot(dx, dy) > 3 else { return }
        mouseDown = nil
        let item = NSDraggingItem(
            pasteboardWriter: CopiedImagePromise(
                png: png, fileName: CopyPreview.fileName(at: .now)))
        item.setDraggingFrame(
            bounds, contents: image.map { NSImage(cgImage: $0, size: bounds.size) })
        onDragBegan()
        beginDraggingSession(with: [item], event: start, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        onDragEnded(operation != [])
    }
}

private struct CopyPreviewDragSource: NSViewRepresentable {
    let png: Data
    let image: CGImage
    let events: CopyPreviewController.Events

    func makeNSView(context: Context) -> CopyPreviewDragView { CopyPreviewDragView() }

    func updateNSView(_ view: CopyPreviewDragView, context: Context) {
        view.png = png
        view.image = image
        view.onClick = events.open
        view.onHover = events.hover
        view.onDragBegan = { events.drag(true) }
        view.onDragEnded = { delivered in
            events.drag(false)
            if delivered { events.dismiss() }
        }
    }
}

struct CopyPreviewView: View {
    let png: Data
    let image: CGImage
    let size: CGSize
    let animate: Bool
    let events: CopyPreviewController.Events

    @State private var shown = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.Radius.md)
        Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(Brand.Palette.border.color, lineWidth: Brand.Stroke.hairline)
            )
            .overlay(CopyPreviewDragSource(png: png, image: image, events: events))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Copied image")
            .accessibilityAddTraits([.isImage, .isButton])
            .accessibilityAction(.default, events.open)
            .accessibilityAction(named: "Dismiss", events.dismiss)
            .accessibilityAction(.escape, events.dismiss)
            .accessibilityIdentifier("copy-preview-image")
            .overlay(alignment: .topLeading) {
                Button(action: events.dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.Palette.textPrimary.color)
                        .frame(width: 20, height: 20)
                        .background(Brand.Surface.glass, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: -Brand.Spacing.xs, y: -Brand.Spacing.xs)
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("copy-preview-dismiss")
            }
            .brandShadow(Brand.Shadow.card)
            .padding(CopyPreview.inset)
            // Decorative entrance only; under Reduce Motion the preview simply appears.
            .opacity(animate && !shown ? 0 : 1)
            .offset(x: animate && !shown ? Brand.Spacing.lg : 0)
            .onAppear {
                guard animate else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { shown = true }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("copy-preview")
    }
}

/// Owns the one preview panel. A new copy replaces the shown preview instead of stacking,
/// and callbacks from a replaced preview, such as a drag ending late, are ignored.
final class CopyPreviewController {
    static let shared: CopyPreviewController = {
        let controller = CopyPreviewController()
        controller.dismissOnPolicyChange(of: AppEnvironment.shared.appSettings.outputBehavior)
        return controller
    }()

    struct Events {
        let open: () -> Void
        let dismiss: () -> Void
        let hover: (Bool) -> Void
        let drag: (Bool) -> Void
    }

    /// Debug UI tests keep the preview until they dismiss it.
    var holdsUntilDismissed = false
    private(set) var item: CopyPreview.Item?
    private(set) var panel: NSPanel?
    private(set) var generation = 0
    private var isHovered = false
    private var isDragging = false
    private var dismissTask: Task<Void, Never>?
    private let postAnnouncement: @MainActor (String) -> Void
    private let makePanel: @MainActor () -> NSPanel

    init(
        postAnnouncement: @escaping @MainActor (String) -> Void = CopyPreviewController.post,
        makePanel: @escaping @MainActor () -> NSPanel = CopyPreviewController.makePanel
    ) {
        self.postAnnouncement = postAnnouncement
        self.makePanel = makePanel
    }

    func present(_ item: CopyPreview.Item) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPixelSize = max(CopyPreview.maximumSize.width, CopyPreview.maximumSize.height)
        guard let image = CopyPreview.thumbnail(of: item.png, maxPixelSize: maxPixelSize * scale)
        else { return dismiss() }
        generation += 1
        self.item = item
        isHovered = false
        isDragging = false
        let displaySize = CopyPreview.displaySize(
            for: CGSize(width: image.width, height: image.height))
        let root = CopyPreviewView(
            png: item.png, image: image, size: displaySize,
            animate: CaptureHUD.shouldAnimate(reduceMotion: CaptureHUD.reduceMotionEnabled),
            events: events(for: generation))
        let hosting = NSHostingController(rootView: root)
        // The panel's one-shot size stays authoritative, as for the capture HUD.
        hosting.sizingOptions = []
        let panel = reusablePanel()
        panel.contentViewController = hosting
        let size = CopyPreview.panelSize(for: displaySize)
        if let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrame(CopyPreview.frame(for: size, in: visible), display: false)
        } else {
            panel.setContentSize(size)
        }
        panel.orderFrontRegardless()
        postAnnouncement(String(localized: "Copied image preview"))
        scheduleDismiss()
    }

    /// Hides the preview and releases its image.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        item = nil
        panel?.orderOut(nil)
        panel?.contentViewController = nil
    }

    func events(for generation: Int) -> Events {
        let current = { [weak self] in self?.generation == generation }
        return Events(
            open: { [weak self] in
                guard current(), let reopen = self?.item?.reopen else { return }
                self?.dismiss()
                reopen()
            },
            dismiss: { [weak self] in if current() { self?.dismiss() } },
            hover: { [weak self] in
                guard current() else { return }
                self?.isHovered = $0
                self?.scheduleDismiss()
            },
            drag: { [weak self] dragging in
                guard current(), let self else { return }
                isDragging = dragging
                // Tracking areas miss the pointer's return during a drag.
                if !dragging, let panel {
                    isHovered = panel.frame.contains(NSEvent.mouseLocation)
                }
                scheduleDismiss()
            })
    }

    /// A change to either setting withdraws the preview, whichever way it went.
    func dismissOnPolicyChange(of behavior: OutputBehavior) {
        withObservationTracking {
            _ = (behavior.showsCopyPreview, behavior.concealClipboard)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.dismiss()
                self?.dismissOnPolicyChange(of: behavior)
            }
        }
    }

    /// The countdown waits while the pointer rests on the preview or drags it.
    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard item != nil, !isHovered, !isDragging, !holdsUntilDismissed else { return }
        let lifetime = CopyPreview.lifetime(
            voiceOverRunning: NSWorkspace.shared.isVoiceOverEnabled)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func reusablePanel() -> NSPanel {
        if let panel { return panel }
        let panel = makePanel()
        self.panel = panel
        return panel
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Kept out of screen sharing; newer system capture APIs may still record it.
        panel.sharingType = .none
        panel.setAccessibilityIdentifier("copy-preview-window")
        return panel
    }

    private static func post(_ message: String) {
        var text = AttributedString(message)
        // Queued behind the HUD's own confirmation instead of cutting it off.
        text.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(text).post()
    }
}

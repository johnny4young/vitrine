import AppKit
import SwiftUI

/// A floating, always-on-top reference window for the current snapshot (feature #33):
/// pin the rendered image and it stays over every app while you code against the
/// error/design it shows — the CleanShot/Shottr "pin screenshot" workflow, minus a
/// screen-recording permission because the pinned image is Vitrine's own render.
///
/// One pin at a time (a reference, not a collection): pinning again replaces the
/// image and re-shows the panel. The panel is titled/closable/resizable, so the user
/// dismisses or resizes it like any window; closing it is the same as unpinning.
@MainActor
final class PinnedSnapshotController {
    static let shared = PinnedSnapshotController()

    private var panel: NSPanel?

    /// Whether the pin panel is currently on screen (drives the toolbar button state).
    var isPinned: Bool { panel?.isVisible ?? false }

    /// Shows `image` in the floating panel, replacing any prior pin. The panel keeps
    /// the image's aspect and starts bounded (long side ≤ 440 pt) in the bottom-right
    /// of the visible screen, out of the way of the editor.
    func pin(_ image: NSImage) {
        let panel = reusablePanel()
        let hosting = NSHostingView(rootView: PinnedSnapshotView(image: image))
        panel.contentView = hosting

        let size = boundedSize(for: image.size, longSide: 440)
        panel.setContentSize(size)
        position(panel, size: size)
        panel.orderFrontRegardless()
    }

    /// Closes the pin, if any.
    func unpin() {
        panel?.orderOut(nil)
    }

    private func reusablePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = String(localized: "Pinned snapshot")
        // `.floating` keeps it above normal windows without competing with menus or
        // the HUD (which uses `.statusBar`); it survives Space switches so the
        // reference follows you to the code.
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Closing just hides it (the controller owns the instance for reuse).
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityIdentifier("pinned-snapshot-window")
        self.panel = panel
        return panel
    }

    /// `size` scaled down (never up) so its long side fits `longSide`.
    private func boundedSize(for size: NSSize, longSide: CGFloat) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 320, height: 200) }
        let scale = min(1, longSide / max(size.width, size.height))
        return NSSize(
            width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Bottom-right of the visible screen, inset from the edges.
    private func position(_ panel: NSPanel, size: NSSize) {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            panel.center()
            return
        }
        let inset: CGFloat = 24
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - size.width - inset,
                y: visible.minY + inset))
    }
}

/// The pinned panel's content: the render, aspect-fit on a neutral backdrop so a
/// transparent export still reads.
private struct PinnedSnapshotView: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

import AppKit

/// Shared placement for app windows, so no window opens larger than the screen it lands
/// on or stays stranded on a display that went away.
enum WindowPlacement {
    /// Restores the autosaved frame (recovering it if it is now off-screen), or fits the
    /// default size to the visible screen and centers it.
    static func placeNew(_ window: NSWindow, autosaveName: NSWindow.FrameAutosaveName? = nil) {
        if let autosaveName {
            window.setFrameAutosaveName(autosaveName)
            if window.setFrameUsingName(autosaveName) {
                recoverIfOffScreen(window)
                return
            }
        }
        if let visible = visibleFrame(for: window) {
            window.setFrame(WindowFrameSolver.clamp(window.frame, into: visible), display: false)
        }
        window.center()
    }

    /// Keeps an already-shown window inside its screen's visible frame. The Debug-only
    /// environment keys narrow that frame for UI tests of compact layouts.
    static func clampToVisibleScreen(
        _ window: NSWindow, debugMaxWidthKey: String? = nil, debugMaxHeightKey: String? = nil
    ) {
        guard var available = visibleFrame(for: window) else { return }
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            available = constrained(
                available,
                maxWidth: debugMaxWidthKey.flatMap { environment[$0] }.flatMap(Double.init),
                maxHeight: debugMaxHeightKey.flatMap { environment[$0] }.flatMap(Double.init))
        #endif
        window.setFrame(WindowFrameSolver.clamp(window.frame, into: available), display: true)
    }

    /// Moves `window` back onto a visible screen when its frame is unreachable.
    @discardableResult
    static func recoverIfOffScreen(_ window: NSWindow) -> Bool {
        let recovered = WindowFrameSolver.onScreenFrame(
            for: window.frame, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        guard recovered != window.frame else { return false }
        window.setFrame(recovered, display: true)
        return true
    }

    /// A frame for a new window: clamped into `visible`, then centered in it.
    static func centeredFrame(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let clamped = WindowFrameSolver.clamp(frame, into: visible)
        return CGRect(
            x: visible.midX - clamped.width / 2,
            y: visible.midY - clamped.height / 2,
            width: clamped.width,
            height: clamped.height)
    }

    /// `visible` narrowed around its center to the requested maximum size.
    static func constrained(_ visible: CGRect, maxWidth: Double?, maxHeight: Double?) -> CGRect {
        var frame = visible
        if let maxWidth, maxWidth > 0 {
            let width = min(CGFloat(maxWidth), visible.width)
            frame.origin.x = visible.midX - width / 2
            frame.size.width = width
        }
        if let maxHeight, maxHeight > 0 {
            let height = min(CGFloat(maxHeight), visible.height)
            frame.origin.y = visible.midY - height / 2
            frame.size.height = height
        }
        return frame
    }

    private static func visibleFrame(for window: NSWindow) -> CGRect? {
        (window.screen ?? NSScreen.main)?.visibleFrame
    }
}

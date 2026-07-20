import AppKit

/// An `NSWindow` that vertically centers the traffic lights with a tall unified glass
/// toolbar merged into the title bar.
///
/// macOS pins the close / minimize / zoom buttons to the top of a standard 28-pt title
/// bar. The editor, the Web Snapshot composer, and the Social Card composer all extend a
/// taller glass toolbar into the title bar (`fullSizeContentView` + a transparent, hidden
/// title bar), so left alone the traffic lights float too high above the toolbar's title
/// and controls. Re-centering them on every layout keeps them aligned with the toolbar at
/// any window size, the way unified-toolbar apps (Xcode, CleanShot) do. Shared so all
/// three windows align identically.
class TitleBarAlignedWindow: NSWindow {
    /// The vertical center of the traffic lights, in points below the window's top edge —
    /// tuned to sit on the toolbar's control center. One knob so the alignment is trivial
    /// to nudge.
    var trafficLightCenterY: CGFloat = 24

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        alignTrafficLights()
    }

    private func alignTrafficLights() {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { standardWindowButton($0) }
        for button in buttons {
            guard let container = button.superview else { continue }
            // The title-bar container is non-flipped (origin at the bottom-left), so a
            // larger `origin.y` is higher. Place the button so its center lands
            // `trafficLightCenterY` below the container's top edge.
            let targetY = container.bounds.height - trafficLightCenterY - button.bounds.height / 2
            if abs(button.frame.origin.y - targetY) > 0.5 {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: targetY))
            }
        }
    }
}

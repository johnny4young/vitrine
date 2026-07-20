import AppKit
import SwiftUI

/// A short-lived, in-app heads-up display anchored near the menu bar that
/// confirms a quick capture without a Notification Center banner.
///
/// The HUD is the preferred surface for *routine* success so the app does not
/// post a system notification for every ordinary capture; Notification Center is
/// kept as a fallback only (see `CaptureFeedbackPresenter`). It is a borderless,
/// non-activating panel so it never steals focus from the app the user is working
/// in, and it draws itself with the brand glass material rather than the system
/// notification chrome.
///
/// `CaptureHUDController` owns the window and timers; the static members of
/// `CaptureHUD` are the *pure* policy (animation gating and display duration) so
/// the Reduced Motion behavior and timing can be unit-tested without a window.
enum CaptureHUD {
    /// Whether decorative HUD animation should run, given the system Reduce Motion
    /// setting ( "Reduced Motion disables decorative animation
    /// while keeping status feedback.").
    ///
    /// When Reduce Motion is on, the HUD still appears and still shows its status
    /// only the slide/scale/fade *animation* is suppressed; the content snaps in
    /// instead.
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The current system Reduce Motion preference.
    ///
    /// Reads AppKit's accessibility display setting, which mirrors System Settings
    /// ▸ Accessibility ▸ Display ▸ Reduce motion. Centralized here so the presenter
    /// and any caller read one source of truth.
    @MainActor static var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// How long the HUD stays on screen before auto-dismissing.
    ///
    /// Routine confirmations are brief so they read as a glance, not an alert;
    /// feedback that offers recovery actions lingers so the user has time to click
    /// one before it disappears.
    static func displayDuration(hasActions: Bool) -> Duration {
        hasActions ? .seconds(6) : .milliseconds(1600)
    }
}

/// The SwiftUI content of the capture HUD: an icon, the message, and any inline
/// recovery actions. Kept separate from the window so it can be previewed
/// and so the presenter only deals with hosting.
struct CaptureHUDView: View {
    let feedback: Notifier.CaptureFeedback
    /// Whether decorative entrance animation is allowed (off under Reduce Motion).
    let animate: Bool
    /// Invoked when the user clicks a recovery action; the presenter dismisses the
    /// HUD and runs the corresponding handler.
    let onAction: (Notifier.RecoveryAction) -> Void

    @State private var shown = false

    var body: some View {
        HStack(alignment: .center, spacing: Brand.Spacing.sm) {
            Image(systemName: feedback.systemImageName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                Text(feedback.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.Palette.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)

                if !feedback.actions.isEmpty {
                    HStack(spacing: Brand.Spacing.xs) {
                        ForEach(feedback.actions, id: \.self) { action in
                            Button(action.title) { onAction(action) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityIdentifier(
                                    "capture-hud-action-\(action.accessibilityToken)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Brand.Spacing.md)
        .padding(.vertical, Brand.Spacing.sm)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Brand.Surface.glass, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.lg)
                .strokeBorder(Brand.Palette.border.color, lineWidth: Brand.Stroke.hairline)
        )
        .brandShadow(Brand.Shadow.card)
        // Decorative entrance only — gated on Reduce Motion. When suppressed the
        // content is simply shown at full opacity/scale with no transition, so the
        // status is still delivered.
        .opacity(animate ? (shown ? 1 : 0) : 1)
        .scaleEffect(animate ? (shown ? 1 : 0.96) : 1, anchor: .top)
        .onAppear {
            guard animate else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feedback.message)
        .accessibilityIdentifier("capture-hud")
    }

    private var iconColor: Color {
        switch feedback.category {
        case .success: Brand.Palette.accent.color
        case .info: Brand.Palette.accentSecondary.color
        case .failure: Color(nsColor: .systemOrange)
        }
    }
}

/// Owns the floating HUD window and its auto-dismiss timer.
///
/// A single reusable, borderless, non-activating panel is positioned under the
/// menu bar on the active screen and hosts `CaptureHUDView`. Presenting again
/// before the previous HUD has faded simply replaces its content and resets the
/// timer, so a burst of captures never stacks windows.
@MainActor
final class CaptureHUDController {
    static let shared = CaptureHUDController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Shows `feedback` in the HUD, optionally animating its entrance, and routes
    /// any recovery-action tap to `onAction` before dismissing.
    func present(
        _ feedback: Notifier.CaptureFeedback,
        animate: Bool? = nil,
        onAction: @escaping (Notifier.RecoveryAction) -> Void = { _ in }
    ) {
        let shouldAnimate =
            animate
            ?? CaptureHUD.shouldAnimate(
                reduceMotion: CaptureHUD.reduceMotionEnabled)

        let root = CaptureHUDView(feedback: feedback, animate: shouldAnimate) {
            [weak self] action in
            onAction(action)
            self?.dismiss()
        }
        let hosting = NSHostingController(rootView: root)
        hosting.view.layout()

        let panel = reusablePanel()
        panel.contentViewController = hosting
        position(panel, fitting: hosting.view.fittingSize)
        panel.orderFrontRegardless()

        scheduleDismiss(after: CaptureHUD.displayDuration(hasActions: !feedback.actions.isEmpty))
    }

    /// Hides the HUD immediately and cancels any pending auto-dismiss.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    /// Lazily builds (and reuses) the floating panel. It is non-activating and
    /// borderless so showing it never pulls focus away from the user's frontmost
    /// app — the whole point of a no-UI quick capture.
    private func reusablePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // the SwiftUI content draws its own brand shadow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setAccessibilityIdentifier("capture-hud-window")
        self.panel = panel
        return panel
    }

    /// Anchors the panel just under the menu bar at the trailing edge of the
    /// active screen — i.e. near the menu-bar item it confirms.
    private func position(_ panel: NSPanel, fitting size: NSSize) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        panel.setContentSize(NSSize(width: width, height: height))

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let margin = Brand.Spacing.md
        let originX = visible.maxX - width - margin
        let originY = visible.maxY - height - margin
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func scheduleDismiss(after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

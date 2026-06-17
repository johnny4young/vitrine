import AppKit
import SwiftUI

/// Captures the hosting `NSWindow` of a SwiftUI view, so AppKit-level actions (e.g.
/// close-after-copy, CS-084) can target *this* window rather than guessing at
/// `NSApp.keyWindow`. Resolves once the view joins the window, and again if it moves.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Poll the next few run loops until the view has joined its window, then stop.
        // (A one-shot resolve can miss it if the view isn't in the window yet; a
        // per-`updateNSView` resolve churns on every editor re-render and can slow
        // launch enough to flake the multi-window UI test — this captures once,
        // reliably, without the churn.)
        capture(from: view, attempt: 0)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func capture(from view: NSView, attempt: Int) {
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            if let window = view.window {
                onResolve(window)
            } else if attempt < 30 {
                capture(from: view, attempt: attempt + 1)
            }
        }
    }
}

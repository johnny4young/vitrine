import AppKit
import SwiftUI

/// Stable identity for editor actions that must address their hosting window without
/// making the SwiftUI tree own that window. The window owns the hosting tree, so a
/// strong reference in the opposite direction would retain every closed editor.
final class WeakWindowReference {
    weak var value: NSWindow?
}

/// Captures the hosting `NSWindow` of a SwiftUI view, so AppKit-level actions (e.g.
/// close-after-copy) can target *this* window rather than guessing at
/// `NSApp.keyWindow`. Resolves once the view joins the window, and again if it moves.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResolve: onResolve)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Poll the next few run loops until the view has joined its window, then stop.
        // (A one-shot resolve can miss it if the view isn't in the window yet; a
        // per-`updateNSView` resolve churns on every editor re-render and can slow
        // launch enough to flake the multi-window UI test — this captures once,
        // reliably, without the churn.)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private let onResolve: (NSWindow?) -> Void
        private var generation = 0

        init(onResolve: @escaping (NSWindow?) -> Void) {
            self.onResolve = onResolve
        }

        func attach(to view: NSView) {
            generation += 1
            capture(from: view, attempt: 0, generation: generation)
        }

        /// Clears the weak window slot and invalidates any queued resolution. The slot
        /// is a stable reference object rather than SwiftUI value-state, so this is safe
        /// while SwiftUI invalidates its graph.
        func detach() {
            generation += 1
            onResolve(nil)
        }

        private func capture(from view: NSView, attempt: Int, generation: Int) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, self.generation == generation else { return }
                if let window = view.window {
                    self.onResolve(window)
                } else if attempt < 30 {
                    self.capture(from: view, attempt: attempt + 1, generation: generation)
                }
            }
        }
    }
}

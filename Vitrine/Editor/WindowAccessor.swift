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
/// `NSApp.keyWindow`. Resolves when the view joins a window, and again if it moves.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        WindowReportingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {}

    static func dismantleNSView(_ nsView: WindowReportingView, coordinator: ()) {
        nsView.onResolve(nil)
        nsView.onResolve = { _ in }
    }

    /// Reports its window from AppKit's own move notification, so no polling is needed.
    final class WindowReportingView: NSView {
        var onResolve: (NSWindow?) -> Void

        init(onResolve: @escaping (NSWindow?) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve(window)
        }
    }
}

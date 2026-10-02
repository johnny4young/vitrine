/// Closes the menu-bar panel from inside its SwiftUI content.
///
/// The panel used to be a SwiftUI `MenuBarExtra(.window)` scene, so its rows closed it
/// through `@Environment(\.dismiss)`. It is now an AppKit `NSPopover` owned by
/// `StatusItemController` (see that type for why the SwiftUI scene had to go), and
/// `\.dismiss` only dismisses presentations SwiftUI itself made. Injecting the close
/// action keeps the content's call sites written the same way — `dismiss()` — while the
/// popover, not SwiftUI, decides what closing means.
///
/// The default action does nothing, so a preview or a test can build the panel without
/// a popover behind it.
struct MenuBarDismissAction {
    private let perform: () -> Void

    init(_ perform: @escaping () -> Void = {}) {
        self.perform = perform
    }

    /// Called as `dismiss()`, mirroring SwiftUI's own `DismissAction`.
    func callAsFunction() {
        perform()
    }

    /// Closes the panel, then runs `operation` on a later turn. A modal alert opened by
    /// the operation would otherwise run under the panel's Escape monitor.
    @discardableResult
    func thenRun(_ operation: @escaping () -> Void) -> Task<Void, Never> {
        perform()
        return Task {
            await Task.yield()
            operation()
        }
    }
}

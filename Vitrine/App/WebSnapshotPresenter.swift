import Foundation

/// A decoupling seam between the app's command surface and the Web Snapshot window
/// (CS-042/CS-043).
///
/// The window and its renderers live in `WebRendering/`, which the headless CLI
/// target excludes (it ships no WebKit). The File-menu command, the `--open-web-snapshot`
/// launch hook, and the quick-capture URL route, however, live in `App/` — which the
/// CLI *does* compile. Routing them straight to `WebSnapshotWindowController` would
/// drag WebKit into the CLI.
///
/// Instead they call this presenter, which holds a closure the app installs at launch
/// (`WebSnapshotWindowController.registerPresenter()` from the app-only `VitrineApp`).
/// In the CLI the closure is never installed and `show` is a no-op, so the command
/// surface compiles and links without WebKit.
@MainActor
enum WebSnapshotPresenter {
    /// The real window opener, installed once at launch by the app. `nil` in headless
    /// contexts (the CLI), where there is no window surface, so `show` does nothing.
    /// The argument prefills the URL field (used by the quick-capture URL route).
    static var open: ((_ prefillURL: String?) -> Void)?

    /// Opens the Web Snapshot window, optionally prefilled with a URL. A no-op until
    /// the app installs the opener, and permanently a no-op in the CLI.
    static func show(prefillURL: String? = nil) {
        open?(prefillURL)
    }
}

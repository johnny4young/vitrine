import Foundation

/// A decoupling seam between the settings surface and Vitrine's stored web sessions.
///
/// The store itself is `WKWebsiteDataStore`, so it lives in `WebRendering/` — which the
/// headless CLI excludes, shipping no WebKit. The Input settings pane, however, lives in
/// `Settings/`, which the CLI *does* compile (it persists the same URL-capture
/// preferences). Calling `WebSessionStore` from there would drag WebKit into the CLI.
///
/// So the pane calls this presenter, and the app installs the real implementations at
/// launch (`WebSessionStore.registerPresenter()`). In the CLI nothing is installed: there
/// are no sessions to list and nothing to clear, which is the honest answer for a tool
/// that never loads a page. Mirrors `WebSnapshotPresenter`.
@MainActor
enum WebSessionPresenter {
    /// Reads the hosts Vitrine holds a session for. `nil` until the app installs it.
    static var readSignedInHosts: (() async -> [String])?

    /// Clears every stored session, returning the hosts removed. `nil` until the app
    /// installs it.
    static var clearSessions: (() async -> [String])?

    /// The sites Vitrine currently holds a session for, or none in a headless context.
    static func signedInHosts() async -> [String] {
        await readSignedInHosts?() ?? []
    }

    /// Removes every stored session, returning the hosts that were cleared.
    @discardableResult
    static func clear() async -> [String] {
        await clearSessions?() ?? []
    }
}

import AppKit
import Combine
import OSLog
import SwiftUI

/// One editor window's per-window state (CS-053): a stable identity, an independent
/// settings instance seeded from the app-wide defaults, and the live config the
/// window's `EditorView` edits.
///
/// Each session owns a *volatile* `AppSettings` so a window edits its own document and
/// style without disturbing the global default; "Make Default" is the explicit action
/// that promotes a session's look back into the shared settings. The session also
/// produces the ``EditorWindowState`` archived for state restoration and adopts a
/// restored draft on relaunch.
@MainActor
final class EditorSession: ObservableObject {
    /// This window's identity (and therefore its frame-autosave / restoration name).
    let identity: EditorWindowIdentity

    /// The window's independent settings, seeded from the app-wide defaults but backed
    /// by a throwaway store, so its edits never clobber the global default (CS-053).
    let settings: AppSettings

    /// Creates a session for `identity` with its own volatile settings.
    ///
    /// The **primary** window adopts the app's live working document — the
    /// `AppSettings.shared` config, including any code a quick capture, App Intent, or
    /// `--demo` just loaded — so "Open Editor" always surfaces the current document,
    /// exactly as the single-window app did. **Additional** windows (CS-053) seed only
    /// the default *style* and open with an empty editor, so "New Editor Window" is a
    /// fresh canvas in the user's default look. A test can inject `settings` directly.
    init(identity: EditorWindowIdentity, settings: AppSettings? = nil) {
        self.identity = identity
        if let settings {
            self.settings = settings
        } else {
            let session = AppSettings.makeEditorSession()
            if identity == .primary {
                // Mirror the live working document into the primary window's session so
                // the editor shows the current code/style, not just the persisted style.
                session.config = AppSettings.shared.config
            }
            self.settings = session
        }
    }

    /// A restoration snapshot of the window's current draft document/style (CS-053).
    var windowState: EditorWindowState { EditorWindowState(config: settings.config) }

    /// Adopts a restored draft as this window's live config, used when a relaunch
    /// rebuilds the window from its archived state (CS-053).
    func restore(_ state: EditorWindowState) {
        settings.config = state.config()
    }

    /// Promotes this window's current look to the app-wide default (CS-053 "make
    /// default is explicit"): future captures and new windows start from it.
    ///
    /// Because the acting window already displays that style, the promotion changes
    /// nothing on screen — so it confirms with a brief in-app HUD ("Set as the
    /// default style") to give the explicit action explicit, visible feedback,
    /// consistent with the rest of the app's microinteractions. The same shared HUD
    /// (CS-038) backs routine capture confirmations, so this never posts a
    /// Notification Center banner. Both the editor toolbar's star and the File-menu
    /// "Make This Window the Default" route through here, so a single call site
    /// covers both.
    func makeDefault() {
        AppSettings.shared.makeDefault(from: settings)
        CaptureHUDController.shared.present(
            Notifier.confirmation(String(localized: "Set as the default style")))
    }

    /// Tears down the volatile backing store when the window closes so a per-window
    /// suite never accumulates on disk (CS-053).
    func discard() {
        settings.discardVolatileStore()
    }
}

/// Owns the app's editor windows (hosted SwiftUI), opened from the menu, the global
/// hotkey, or App Intents without a SwiftUI `openWindow` environment.
///
/// ## Multi-window editing and restoration (CS-053)
///
/// Vitrine behaves like a native multi-window Mac app: the user can open more than one
/// editor at a time, each with its own ``EditorSession`` (and therefore its own
/// `SnapshotConfig`), and every window remembers its size and position across launches.
/// The controller:
///
/// - Assigns each window a stable ``EditorWindowIdentity`` (lowest free index first),
///   whose `frameAutosaveName` drives AppKit's built-in frame persistence — so a
///   window reopens where the user left it.
/// - Marks each window restorable with a `restorationClass`, and encodes the window's
///   draft config into its restorable state, so secure state restoration can rebuild
///   the exact document a window held (`applicationSupportsSecureRestorableState`
///   stays true).
/// - Pulls any restored frame back onto a currently-visible screen via
///   ``WindowFrameSolver`` when displays change, so a window saved on an
///   now-unplugged monitor never opens off-screen.
///
/// `EditorWindowController` is a `NSObject` so it can serve as each window's delegate
/// (to clean up on close) and observe screen-arrangement changes.
@MainActor
final class EditorWindowController: NSObject {
    static let shared = EditorWindowController()

    /// The live editor windows, keyed by their window-index. Reused, non-released
    /// windows keep reopening cheap and let the controller route the menu to the key
    /// window's session.
    private var windows: [Int: NSWindow] = [:]

    /// The session backing each live window, keyed by the same index, so the key
    /// window's document/style can be resolved for the menu commands and "Make Default".
    private var sessions: [Int: EditorSession] = [:]

    /// Per-window subscriptions that mark a window's restorable state dirty whenever its
    /// session's config changes, so the archived draft AppKit encodes on quit reflects
    /// the latest edits rather than the window's initial state (CS-053). Keyed by window
    /// index and torn down with the window.
    private var stateInvalidators: [Int: AnyCancellable] = [:]

    /// The opening content size for a brand-new editor window. Wide enough for the
    /// preset strip plus the code / preview / inspector columns of the redesigned
    /// editor (CS-037); the SwiftUI root enforces its own minimum below this. A window
    /// restored from a saved frame overrides this.
    private static let defaultContentSize = NSSize(width: 1180, height: 680)

    private override init() {
        super.init()
        // Recover any window that ends up off-screen after the display arrangement
        // changes (a monitor unplugged or rearranged), so a restored frame is never
        // stranded where it cannot be reached (CS-053).
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenArrangementChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: - Opening windows

    /// Shows the primary editor window, creating it if needed, and focuses it. This is
    /// the entry the menu's "Open Editor", the global hotkey, and App Intents use, so
    /// they reuse the single primary window rather than stacking duplicates.
    func show() {
        showWindow(for: .primary)
    }

    /// Opens an *additional* editor window with its own independent session (CS-053
    /// "users can open multiple editor windows"). The new window takes the lowest free
    /// index, so a closed window's slot — and its remembered frame — is reused first.
    func openNewWindow() {
        let index = EditorWindowIdentity.nextAvailableIndex(notIn: Set(windows.keys))
        showWindow(for: EditorWindowIdentity(index: index))
    }

    /// Shows the editor preloaded with the onboarding sample snippet when the primary
    /// window has no code yet, so a first-run user can explore the flow without external
    /// clipboard content (CS-035).
    func showWithSample() {
        let session = session(for: .primary)
        if EditorPreview.isEffectivelyEmpty(session.settings.config.code) {
            session.settings.config.code = EditorPreview.sampleCode
        }
        show()
    }

    /// Loads `config` into the **primary** editor window and shows it, used by the
    /// "hand this off to the editor" paths — quick capture deferring several code
    /// blocks (CS-027) and the Open-Code-in-Editor App Intent (CS-034). Unlike a plain
    /// `show()` (which only focuses the existing window so it never clobbers an
    /// in-progress document), this is an explicit load: it replaces the primary
    /// window's document with `config`, creating the window if needed.
    func loadIntoPrimary(_ config: SnapshotConfig) {
        session(for: .primary).settings.config = config
        show()
    }

    /// The session for `identity`'s window, creating it (and caching it) if absent, so
    /// a window and its session are always made together.
    @discardableResult
    private func session(for identity: EditorWindowIdentity) -> EditorSession {
        if let existing = sessions[identity.index] { return existing }
        let session = EditorSession(identity: identity)
        sessions[identity.index] = session
        return session
    }

    /// Shows (creating if needed) and focuses the window for `identity`.
    private func showWindow(for identity: EditorWindowIdentity) {
        let window = windows[identity.index] ?? makeWindow(for: identity)
        windows[identity.index] = window
        recoverIfOffScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Builds the AppKit window hosting an `EditorView` bound to `identity`'s session,
    /// wired for frame autosave and secure state restoration (CS-053).
    private func makeWindow(for identity: EditorWindowIdentity) -> NSWindow {
        let session = session(for: identity)
        let hosting = NSHostingController(
            rootView: EditorView()
                .environmentObject(session.settings)
                .environmentObject(session))
        let window = NSWindow(contentViewController: hosting)
        window.title = identity.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.defaultContentSize)
        window.isReleasedWhenClosed = false

        // Vitrine is not a tabbed-document app: each editor is its own independent
        // window with its own session (CS-053). Disallow tabs so that, on a Mac whose
        // "Prefer tabs when opening documents" is set to Always, "New Editor Window"
        // always opens a separate window rather than folding into the key window's tab
        // group — keeping the multi-window behavior (and its UI smoke test) reliable.
        window.tabbingMode = .disallowed

        // The primary window keeps the legacy accessibility identifier so existing UI
        // tests and the editor-command validation keep matching it; additional windows
        // get an index-suffixed identifier so a specific one can be addressed.
        window.setAccessibilityIdentifier(Self.accessibilityIdentifier(for: identity))

        // Frame persistence + secure state restoration (CS-053). The autosave name
        // restores size/position across launches; the restoration class + encoded
        // draft let secure restoration rebuild the document this window held.
        window.setFrameAutosaveName(identity.frameAutosaveName)
        window.identifier = identity.restorationIdentifier
        window.isRestorable = true
        window.restorationClass = EditorWindowRestoration.self
        window.delegate = self

        // Mark the window's restorable state dirty on every config change so the draft
        // AppKit archives on quit is the user's latest edit, not the initial document.
        stateInvalidators[identity.index] = session.settings.objectWillChange
            .sink { [weak window] _ in window?.invalidateRestorableState() }

        // A freshly-minted (never-before-saved) window has no autosaved frame to
        // restore. Cap the default size to the screen it opens on — the 1180-point
        // default is wider than a small display (e.g. 1024x768), and a window that
        // overhangs the screen edge leaves its trailing toolbar actions unreachable
        // (CS-053) — then center it. The SwiftUI root's own minimum still applies, so
        // the cap never squeezes the editor below its supported layout. One with a
        // saved frame keeps the restored position and only needs the off-screen
        // recovery pass in `showWindow(for:)`.
        if !window.setFrameUsingName(identity.frameAutosaveName) {
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                window.setFrame(
                    WindowFrameSolver.clamp(window.frame, into: visible), display: false)
            }
            window.center()
        }
        return window
    }

    /// The accessibility identifier for a window: the stable `editor-window` for the
    /// primary, and an index-suffixed form for the rest.
    static func accessibilityIdentifier(for identity: EditorWindowIdentity) -> String {
        identity.index == 1 ? "editor-window" : "editor-window-\(identity.index)"
    }

    // MARK: - Key-window session (menu command target)

    /// The session of the key (or, failing that, the main) editor window, so a Copy /
    /// Save / Share / Make Default initiated from the menu acts on the visible editor
    /// (CS-053). `nil` when no editor window is key, which is how the editor commands
    /// stay disabled outside an editor.
    var keyWindowSession: EditorSession? {
        let target = NSApp.keyWindow ?? NSApp.mainWindow
        guard let target else { return nil }
        for (index, window) in windows where window === target {
            return sessions[index]
        }
        return nil
    }

    // MARK: - Off-screen recovery (CS-053)

    /// When the display arrangement changes, nudge any now-off-screen editor window
    /// back onto a visible screen so a window saved on an unplugged monitor is never
    /// stranded.
    @objc private func screenArrangementChanged() {
        for window in windows.values { recoverIfOffScreen(window) }
    }

    /// Moves `window` back onto a visible screen if its current frame would leave it
    /// unreachable, preserving its size. Uses the pure ``WindowFrameSolver`` against the
    /// live screens' visible frames; a window already on screen is left untouched.
    private func recoverIfOffScreen(_ window: NSWindow) {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let recovered = WindowFrameSolver.onScreenFrame(
            for: window.frame, visibleFrames: visibleFrames)
        if recovered != window.frame {
            Log.app.notice("Recovered an off-screen editor window onto a visible display")
            window.setFrame(recovered, display: true)
        }
    }

    /// A UI-test hook (CS-053): shove the primary editor window far off the visible
    /// screens and then run the recovery pass, so an automated test can verify the
    /// window is pulled back on-screen without physically rearranging displays. Only
    /// reachable through the `--force-offscreen-editor` launch argument.
    func moveKeyEditorOffScreenForTesting() {
        guard let window = windows[EditorWindowIdentity.primary.index] else { return }
        // A point well beyond any plausible display, then recover from it.
        window.setFrameOrigin(NSPoint(x: 12000, y: 9000))
        recoverIfOffScreen(window)
    }
}

// MARK: - NSWindowDelegate (lifecycle cleanup)

extension EditorWindowController: NSWindowDelegate {
    /// Drops the closed window and tears down its volatile session store, so closing
    /// one window never disturbs the others' state and a per-window suite does not
    /// linger on disk (CS-053). The primary window's session is kept so reopening it
    /// preserves the user's in-progress document within the same launch; additional
    /// windows are released entirely.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let index = windows.first(where: { $0.value === window })?.key
        else { return }
        windows[index] = nil
        stateInvalidators[index] = nil
        if index != EditorWindowIdentity.primary.index {
            sessions[index]?.discard()
            sessions[index] = nil
        }
    }

    /// Archives the window's current draft config into its restorable state, so secure
    /// restoration can rebuild the document on the next launch (CS-053). AppKit calls
    /// this delegate hook from the window's `encodeRestorableState(with:)`. The matching
    /// decode happens in `EditorWindowRestoration` when the window is recreated.
    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        guard let index = windows.first(where: { $0.value === window })?.key,
            let session = sessions[index],
            let data = session.windowState.encoded()
        else { return }
        state.encode(data as NSData, forKey: Self.restorationStateKey)
    }
}

// MARK: - State restoration (CS-053)

/// Restores editor windows during secure state restoration (CS-053).
///
/// When AppKit replays a previous session it asks this class to recreate a window for a
/// saved restoration identifier. The window is rebuilt through `EditorWindowController`
/// (so it gets the same session wiring, frame autosave, and delegate), and its archived
/// draft — encoded in `window(_:willEncodeRestorableState:)` — is decoded back into the
/// window's session so the exact document is restored.
///
/// The protocol entry point is main-actor-isolated (AppKit annotates it
/// `NS_SWIFT_UI_ACTOR`), so the rebuild and the completion handler run on the main actor
/// without any explicit hop.
final class EditorWindowRestoration: NSObject, NSWindowRestoration {
    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder,
        completionHandler: @escaping (NSWindow?, Error?) -> Void
    ) {
        let window = EditorWindowController.shared.restoreWindow(
            identifier: identifier, state: state)
        completionHandler(window, nil)
    }
}

extension EditorWindowController {
    /// The `NSCoder` key under which a window's draft config JSON is archived.
    fileprivate static let restorationStateKey = "vitrine.editor.windowState"

    /// Recreates the window for a saved restoration `identifier` and re-applies its
    /// archived draft, returning the window for AppKit to finish restoring. An
    /// unrecognized identifier (a stale or non-editor record) yields `nil` so AppKit
    /// discards it cleanly.
    func restoreWindow(identifier: NSUserInterfaceItemIdentifier, state: NSCoder) -> NSWindow? {
        guard let index = Self.windowIndex(from: identifier) else { return nil }
        let identity = EditorWindowIdentity(index: index)
        let window = windows[index] ?? makeWindow(for: identity)
        windows[index] = window

        // Re-apply the archived draft so the window restores the exact document it
        // held; a missing or corrupt blob leaves the seeded default in place (CS-050).
        if let data = state.decodeObject(of: NSData.self, forKey: Self.restorationStateKey)
            as Data?,
            let restored = EditorWindowState.decoded(from: data)
        {
            session(for: identity).restore(restored)
        }
        recoverIfOffScreen(window)
        return window
    }

    /// The window index encoded in a restoration identifier, or `nil` when it is not an
    /// editor window identifier. The primary window restores from the bare `editor`
    /// name; additional windows from the `editor-N` suffix.
    private static func windowIndex(from identifier: NSUserInterfaceItemIdentifier) -> Int? {
        let raw = identifier.rawValue
        if raw == EditorWindowIdentity.autosaveBase { return EditorWindowIdentity.primary.index }
        let prefix = "\(EditorWindowIdentity.autosaveBase)-"
        guard raw.hasPrefix(prefix), let index = Int(raw.dropFirst(prefix.count)), index >= 1
        else { return nil }
        return index
    }
}

import SwiftUI

/// Vitrine — a menu-bar app that turns code into images.
///
/// The app lives entirely in the menu bar (`LSUIElement`, see Info.plist). The
/// `MenuBarExtra` presents the current designed panel (`.window` style, per
/// shared design system); the editor and preferences are AppKit-hosted windows
/// opened on demand (see `EditorWindowController` / `SettingsWindowManager`).
@main
struct VitrineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Install the Web Snapshot window opener so the app's command surface — the
        // File-menu command, the launch hook, and the quick-capture URL route, none of
        // which link WebKit — can present it through `WebSnapshotPresenter`. App-only:
        // the CLI excludes this file and the window, so it never links WebKit.
        // `App.init()` is already main-actor-isolated under the module's default
        // isolation, so this needs no actor hop.
        WebSnapshotWindowController.registerPresenter()
    }

    var body: some Scene {
        // The status-bar glyph is the real Vitrine logo (viewfinder + code
        // chevrons), shipped as a monochrome template image set so macOS tints it
        // for light/dark bars and selection — not the generic `camera.viewfinder`
        // SF Symbol. See `assets/brand/vitrine-menubar-*` in the design system.
        MenuBarExtra("Vitrine", image: "vitrine-menubar") {
            MenuBarContent()
                .environment(AppSettings.shared)
                .environment(RecentsStore.shared)
                .environment(CaptureFeedbackPresenter.shared)
        }
        .menuBarExtraStyle(.window)
    }
}

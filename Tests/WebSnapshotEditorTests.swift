import AppKit
import Foundation
import Testing

@testable import Vitrine

// CS-042/CS-043 — the Web Snapshot surface (app integration). The renderers and
// validation are covered by HTMLRendererTests / URLRendererTests; these pin the seams
// the window adds: the model's input logic, the consent flag's persistence, the
// presenter bridge, and the File-menu command wiring.

@Suite("Web snapshot model")
@MainActor
struct WebSnapshotModelTests {
    @Test func normalizedURLAcceptsHTTPAndHTTPSAndTrims() {
        #expect(WebSnapshotModel.normalizedURL("https://example.com") != nil)
        #expect(WebSnapshotModel.normalizedURL("http://example.com") != nil)
        #expect(WebSnapshotModel.normalizedURL("  https://example.com/path  \n") != nil)
    }

    @Test func normalizedURLRejectsNonWebSchemesAndEmpty() {
        // Mirrors the renderer's scheme gate so the UI refuses an obviously bad URL
        // before a render attempt (CS-043).
        #expect(WebSnapshotModel.normalizedURL("") == nil)
        #expect(WebSnapshotModel.normalizedURL("file:///etc/passwd") == nil)
        #expect(WebSnapshotModel.normalizedURL("javascript:alert(1)") == nil)
        #expect(WebSnapshotModel.normalizedURL("ftp://example.com") == nil)
        #expect(WebSnapshotModel.normalizedURL("not a url") == nil)
    }

    @Test func errorMessagesAreNonEmptyAndDistinctForTheGate() {
        // The entitlement gate has its own clear message, distinct from a render
        // failure, so a build without URL capture explains itself.
        let disabled = WebSnapshotModel.message(for: .urlCaptureDisabled)
        let failed = WebSnapshotModel.message(for: .renderFailed)
        #expect(!disabled.isEmpty)
        #expect(!failed.isEmpty)
        #expect(disabled != failed)
    }

    @Test func canRenderReflectsTheActiveModeInput() {
        let model = WebSnapshotModel()
        model.mode = .url
        #expect(!model.canRender)
        model.urlText = "https://example.com"
        #expect(model.canRender)

        model.mode = .html
        #expect(!model.canRender)  // htmlText still empty
        model.htmlText = "<b>x</b>"
        #expect(model.canRender)
    }

    @Test func loadingHostExtractsTheURLHostOnlyInURLMode() {
        let model = WebSnapshotModel()
        model.mode = .url
        model.urlText = "https://example.com/path"
        #expect(model.loadingHost == "example.com")
        model.mode = .html
        #expect(model.loadingHost == nil)
    }
}

@Suite("URL-capture consent persistence")
@MainActor
struct URLCaptureConsentTests {
    @Test func consentIsOffByDefaultAndRoundTrips() {
        let suite = "VitrineConsent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        // Off on a fresh suite, so the first capture always discloses first (CS-045).
        #expect(!settings.urlCaptureConsentGiven)

        settings.urlCaptureConsentGiven = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.urlCaptureConsentGiven)
    }

    @Test func resetRevokesConsent() {
        let suite = "VitrineConsentReset-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.urlCaptureConsentGiven = true
        settings.resetToDefaults()
        #expect(!settings.urlCaptureConsentGiven)
    }
}

@Suite("Web snapshot presenter bridge")
@MainActor
struct WebSnapshotPresenterTests {
    @Test func showRoutesThePrefillURLToTheInstalledOpener() {
        let original = WebSnapshotPresenter.open
        defer { WebSnapshotPresenter.open = original }

        var received: String??
        WebSnapshotPresenter.open = { received = $0 }
        WebSnapshotPresenter.show(prefillURL: "https://example.com")
        #expect(received == "https://example.com")
    }

    @Test func showIsANoOpWithoutAnInstalledOpener() {
        let original = WebSnapshotPresenter.open
        defer { WebSnapshotPresenter.open = original }
        // In a headless context (the CLI) no opener is installed; show must not crash.
        WebSnapshotPresenter.open = nil
        WebSnapshotPresenter.show()
        WebSnapshotPresenter.show(prefillURL: "https://example.com")
    }
}

@Suite("Web snapshot command and menu")
@MainActor
struct WebSnapshotCommandTests {
    @Test func newWebSnapshotIsAppScoped() {
        #expect(!VitrineCommand.newWebSnapshot.isEditorScoped)
        #expect(!VitrineCommand.newWebSnapshot.requiresCode)
    }

    @Test func newWebSnapshotHasNoKeyboardShortcut() {
        #expect(VitrineCommand.newWebSnapshot.keyEquivalent == nil)
        #expect(VitrineCommand.newWebSnapshot.modifiers == [])
    }

    @Test func newWebSnapshotTitleOpensItsWindowWithoutEllipsis() {
        #expect(!VitrineCommand.newWebSnapshot.title.hasSuffix("…"))
        #expect(!VitrineCommand.newWebSnapshot.title.isEmpty)
    }

    @Test func fileMenuExposesNewWebSnapshotTargetingTheAppResponder() {
        let file = AppMenu.make().items.compactMap(\.submenu).first { $0.title == "File" }
        let item = file?.items.first {
            $0.accessibilityIdentifier() == VitrineCommand.newWebSnapshot.accessibilityIdentifier
        }
        #expect(item != nil, "New Web Snapshot must be in the File menu")
        #expect(item?.target is AppCommandResponder)
        #expect(item?.action == #selector(AppCommandResponder.openWebSnapshotEditor(_:)))
        #expect(item?.keyEquivalent == "")
    }

    @Test func theWebSnapshotWindowIsNotEditorScopedByIdentifier() {
        // Must not start with "editor-window", or a key Web Snapshot window would
        // wrongly enable the editor's Copy/Save/Share commands.
        #expect(!WebSnapshotWindowController.windowIdentifier.hasPrefix("editor-window"))
    }
}

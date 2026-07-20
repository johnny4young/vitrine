import AppKit
import Foundation
import Testing

@testable import Vitrine

// — the Web Snapshot surface (app integration). The renderers and
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
        // before a render attempt.
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
        let loopback = WebSnapshotModel.message(for: .loopbackCaptureDisabled)
        let failed = WebSnapshotModel.message(for: .renderFailed)
        #expect(!disabled.isEmpty)
        #expect(!failed.isEmpty)
        #expect(!loopback.isEmpty)
        #expect(disabled != failed)
        #expect(loopback != failed)
        #expect(loopback.localizedCaseInsensitiveContains("localhost"))
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

    @Test func prefillURLClearsStaleRenderedResults() throws {
        let model = WebSnapshotModel()
        let asset = try Self.tinyRenderedAsset()
        model.mode = .html
        model.htmlText = "<strong>old</strong>"
        model.renderedAsset = asset
        model.results = [
            CapturedViewport(kind: .desktop, preset: .desktop, asset: asset)
        ]
        model.boardAsset = asset
        model.boardThumbnailAsset = asset
        model.errorMessage = "Previous failure"

        model.prepareForPrefillURL("https://example.com/new")

        #expect(model.mode == .url)
        #expect(model.urlText == "https://example.com/new")
        #expect(model.renderedAsset == nil)
        #expect(model.results.isEmpty)
        #expect(model.boardAsset == nil)
        #expect(model.boardThumbnailAsset == nil)
        #expect(model.errorMessage == nil)
    }

    private static func tinyRenderedAsset() throws -> RenderedAsset {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        return RenderedAsset(cgImage: image, profile: .sRGB)
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
        // Off on a fresh suite, so the first capture always discloses first.
        #expect(!settings.webCapture.consentGiven)

        settings.webCapture.consentGiven = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.webCapture.consentGiven)
    }

    @Test func resetRevokesConsent() {
        let suite = "VitrineConsentReset-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.webCapture.consentGiven = true
        settings.resetToDefaults()
        #expect(!settings.webCapture.consentGiven)
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

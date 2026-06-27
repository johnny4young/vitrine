import Foundation
import Testing

@testable import Vitrine

/// CS-040 — the renderer abstraction for phased inputs.
///
/// These suites prove the three properties the ticket asks for:
///
/// 1. **Routing** — a `RenderCoordinator` picks the first renderer that accepts an
///    input, and `CodeRenderer` handles the Phase 1 code case only.
/// 2. **Phase 2 rendering** — HTML routes to the local `HTMLRenderer` and URL to
///    the `URLRenderer`; URL capture is gated on the network entitlement, and a
///    gated capture throws a *typed* error, never a blank image.
/// 3. **No-network code path** — code rendering produces a real asset without any
///    URL configuration, and the app target ships with no network entitlement.

// MARK: - Input classification

@Suite("CaptureInput · CS-040")
struct CaptureInputTests {
    @Test func diagnosticKindIsAStableNonPIILabel() throws {
        // The label names the *kind*, never the user's content.
        #expect(CaptureInput.code("secret token", languageHint: nil).diagnosticKind == "code")
        #expect(
            CaptureInput.url(try #require(URL(string: "https://example.com/secret")))
                .diagnosticKind == "url")
        #expect(CaptureInput.html("<p>secret</p>").diagnosticKind == "html")
    }
}

// MARK: - Routing

@MainActor
@Suite("RenderCoordinator routing · CS-040")
struct RenderCoordinatorRoutingTests {
    @Test func codeRendererAcceptsOnlyCode() throws {
        let renderer = CodeRenderer()
        #expect(renderer.canRender(.code("x", languageHint: nil)))
        #expect(!renderer.canRender(.url(try #require(URL(string: "https://example.com")))))
        #expect(!renderer.canRender(.html("<b>x</b>")))
    }

    @Test func standardCoordinatorRoutesEachInputToTheRightRenderer() throws {
        // Phase 2 is wired: HTML routes to the local HTMLRenderer and URL to the
        // URLRenderer (the latter still gated on the network entitlement at render
        // time).
        let coordinator = RenderCoordinator.standard
        #expect(coordinator.renderer(for: .code("x", languageHint: nil)) is CodeRenderer)
        #expect(coordinator.renderer(for: .html("<b>x</b>")) is HTMLRenderer)
        #expect(
            coordinator.renderer(for: .url(try #require(URL(string: "https://example.com"))))
                is URLRenderer)
    }

    @Test func firstAcceptingRendererWins() throws {
        // Routing is "first that accepts", so order is priority: a code-accepting
        // renderer placed before `CodeRenderer` would intercept code. Verify the
        // documented order by putting `CodeRenderer` first.
        let coordinator = RenderCoordinator(renderers: [CodeRenderer(), HTMLRenderer()])
        let chosen = coordinator.renderer(for: .code("x", languageHint: nil))
        #expect(chosen is CodeRenderer)
    }

    @Test func unroutableInputThrowsNoRendererFor() async throws {
        // A coordinator with no renderers cannot route anything; the error names
        // the kind, not the content.
        let coordinator = RenderCoordinator(renderers: [])
        await #expect(throws: RenderError.noRendererFor(kind: "code")) {
            try await coordinator.render(.code("x", languageHint: nil), config: SnapshotConfig())
        }
    }
}

// MARK: - Phase 2 rendering (HTML local, URL gated)

@MainActor
@Suite("Phase 2 rendering · CS-040")
struct Phase2RenderingTests {
    @Test func htmlRoutesToTheLocalRenderer() throws {
        // HTML renders locally; the standard coordinator routes it to the real
        // HTMLRenderer.
        let coordinator = RenderCoordinator.standard
        #expect(coordinator.renderer(for: .html("<h1>Hello</h1>")) is HTMLRenderer)
    }

    @Test func urlRoutesToTheURLRenderer() throws {
        // URL routes to the real URLRenderer; whether a capture can run is decided at
        // render time by the network entitlement, not by routing.
        let coordinator = RenderCoordinator.standard
        let input = CaptureInput.url(try #require(URL(string: "https://example.com")))
        #expect(coordinator.renderer(for: input) is URLRenderer)
    }

    @Test func urlCaptureWithoutTheEntitlementThrowsTypedNotABlankImage() async throws {
        // The "never a blank image" contract covers the entitlement gate: on a build
        // without the network entitlement, a URL render throws a typed
        // urlCaptureDisabled before touching WebKit — never an empty asset (CS-038).
        let renderer = URLRenderer(isNetworkCaptureEnabled: false)
        let input = CaptureInput.url(try #require(URL(string: "https://example.com")))
        await #expect(throws: RenderError.urlCaptureDisabled) {
            try await renderer.render(input, config: SnapshotConfig())
        }
    }

    @Test func renderErrorCasesAreDistinct() throws {
        // The typed-error contract (failed vs. unroutable vs. disabled) only holds if
        // the cases are not interchangeable: a test asserting a *specific* error would
        // silently pass against the wrong one if these collapsed.
        #expect(RenderError.urlCaptureDisabled != .renderFailed)
        #expect(RenderError.noRendererFor(kind: "url") != .renderFailed)
        #expect(RenderError.noRendererFor(kind: "url") != .urlCaptureDisabled)
        // Associated values participate in equality, so a drifted kind is not equal to
        // the right one.
        #expect(RenderError.noRendererFor(kind: "url") != .noRendererFor(kind: "html"))
        // Sanity: identical cases with identical payloads remain equal (what
        // `#expect(throws:)` relies on).
        #expect(RenderError.noRendererFor(kind: "url") == .noRendererFor(kind: "url"))
        #expect(RenderError.urlCaptureDisabled == .urlCaptureDisabled)
    }
}

// MARK: - No-network code path

@MainActor
@Suite("Code rendering needs no network or URL config · CS-040")
struct CodeRenderingNoNetworkTests {
    @Test func codeRendererProducesAnAssetWithoutURLConfig() async throws {
        // Rendering code goes through the abstraction and yields a real image with
        // no URL, no network, and no web configuration involved.
        let coordinator = RenderCoordinator.standard
        let asset = try await coordinator.render(
            .code("let answer = 42", languageHint: .swift), config: SnapshotConfig())
        #expect(asset.pixelWidth > 0)
        #expect(asset.pixelHeight > 0)
        #expect(asset.profile == .sRGB)
    }

    @Test func languageHintOverridesTheConfigLanguage() async throws {
        // The renderer honors the detector's hint over the config's stored language
        // (classification done upstream is respected, not re-derived).
        var config = SnapshotConfig()
        config.language = .plaintext
        let asset = try await CodeRenderer().render(
            .code("print(1)", languageHint: .python), config: config)
        #expect(asset.pixelWidth > 0)
    }

    @Test func nonCodeInputThrowsFromCodeRenderer() async throws {
        // Calling `CodeRenderer` with an input it rejects is a routing mistake and
        // throws, rather than producing an image.
        let url = CaptureInput.url(try #require(URL(string: "https://example.com")))
        await #expect(throws: RenderError.noRendererFor(kind: "url")) {
            try await CodeRenderer().render(url, config: SnapshotConfig())
        }
    }

    /// The app target ships **without** `com.apple.security.network.client`, so the
    /// Phase 1 render path provably cannot reach the network (CS-011/CS-040). The
    /// entitlements file is excluded from the app's compiled sources and is not a
    /// bundle resource, so it is read from the source tree via `#filePath` — the
    /// same anchoring the golden fixtures use.
    @Test func appHasNoNetworkClientEntitlement() throws {
        let entitlements = Self.appEntitlements()
        let data = try Data(contentsOf: entitlements)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property list")

        #expect(
            plist["com.apple.security.network.client"] == nil,
            "Phase 1 must not request the network client entitlement (CS-011/CS-040)")
        // The sandbox is on and file access is the only granted capability, so the
        // guard fails loudly if a network key is ever added alongside it.
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
    }

    /// `<repo>/Vitrine/Resources/Vitrine.entitlements`, derived from this file at
    /// `<repo>/Tests/RendererTests.swift`.
    private static func appEntitlements() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // <repo>/Tests
            .deletingLastPathComponent()  // <repo>
            .appendingPathComponent("Vitrine", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Vitrine.entitlements", isDirectory: false)
    }
}

// MARK: - Quick capture wiring

@MainActor
@Suite("QuickCapture classification · CS-040", .serialized)
struct QuickCaptureClassificationTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineCS040-\(UUID().uuidString)")!
    }

    @Test func clipboardCodeClassifiesAsCodeWithDetectedLanguage() {
        let input = QuickCapture.classify("def greet():\n    pass", treatURLsAsScreenshot: false)
        guard case .code(let code, let hint) = input else {
            Issue.record("Expected a code input, got \(input)")
            return
        }
        #expect(code == "def greet():\n    pass")
        #expect(hint == .python)
    }

    @Test func markdownFenceIsStrippedDuringClassification() {
        let input = QuickCapture.classify(
            "```swift\nlet x = 1\n```", treatURLsAsScreenshot: false)
        guard case .code(let code, let hint) = input else {
            Issue.record("Expected a code input, got \(input)")
            return
        }
        #expect(code == "let x = 1")
        #expect(hint == .swift)
    }

    @Test func urlClassifiesAsURLOnlyWhenScreenshotEnabled() throws {
        // With the opt-in off, a URL stays on the code path (rendered as text).
        let asCode = QuickCapture.classify("https://example.com", treatURLsAsScreenshot: false)
        guard case .code = asCode else {
            Issue.record("Expected a code input with the opt-in off, got \(asCode)")
            return
        }

        // With the opt-in on, the same text classifies as a URL input.
        let asURL = QuickCapture.classify("https://example.com", treatURLsAsScreenshot: true)
        guard case .url(let url) = asURL else {
            Issue.record("Expected a url input, got \(asURL)")
            return
        }
        #expect(url == (try #require(URL(string: "https://example.com"))))
    }

    @Test func nonURLTextNeverClassifiesAsURLEvenWhenEnabled() {
        // Plain code with the URL opt-in on still classifies as code: only a single
        // http(s) URL trips the URL branch.
        let input = QuickCapture.classify("let x = 1", treatURLsAsScreenshot: true)
        guard case .code = input else {
            Issue.record("Expected a code input, got \(input)")
            return
        }
    }

    @Test func classifyURLReturnsNilForNonURL() {
        #expect(QuickCapture.classifyURL("not a url") == nil)
        #expect(QuickCapture.classifyURL("ftp://example.com") == nil)
    }

    @Test func classifyURLTrimsSurroundingWhitespaceIntoTheURLValue() throws {
        // A pasted URL often carries trailing whitespace/newlines; classification
        // trims before building the `URL`, so the input carries the clean URL (not
        // one that would fail to load) and still classifies as `.url`.
        let input = try #require(QuickCapture.classifyURL("  https://example.com/path  \n"))
        guard case .url(let url) = input else {
            Issue.record("Expected a url input, got \(input)")
            return
        }
        #expect(url == (try #require(URL(string: "https://example.com/path"))))
    }

    @Test func classifyFallsBackToCodeCarryingTheOriginalTextWhenURLOptInIsOff() {
        // With the opt-in off, even a bare URL string takes the code path and the
        // input carries the text verbatim (it is framed as a snippet, unchanged
        // Phase 1 behavior) — proving the URL branch is gated, not the code path.
        let input = QuickCapture.classify("https://example.com", treatURLsAsScreenshot: false)
        guard case .code(let code, _) = input else {
            Issue.record("Expected a code input, got \(input)")
            return
        }
        #expect(code == "https://example.com")
    }

    @Test func quickCaptureReportsAURLOutcomeWhenEnabled() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.treatURLsAsScreenshot = true
        let recents = RecentsStore(defaults: freshDefaults())
        let outcome = QuickCapture.run(
            settings: settings, recents: recents, clipboard: { "https://example.com" })
        // `run` reports the URL outcome; nothing is rendered, copied, or recorded for
        // it here (the Web Snapshot window, opened by `perform`, owns the capture).
        #expect(outcome == .url("https://example.com"))
        #expect(recents.captures.isEmpty)
    }

    @Test func quickCaptureStillRendersURLTextWhenOptInIsOff() {
        // The URL branch is gated on the opt-in; without it, the URL text is framed
        // as a normal code capture (unchanged Phase 1 behavior).
        let settings = AppSettings(defaults: freshDefaults())
        settings.treatURLsAsScreenshot = false
        let recents = RecentsStore(defaults: freshDefaults())
        let outcome = QuickCapture.run(
            settings: settings, recents: recents, clipboard: { "https://example.com" })
        #expect(outcome == .copied)
        #expect(recents.captures.first?.code == "https://example.com")
    }
}

// MARK: - Code line wrap (#16)

@MainActor
@Suite("Code line wrap")
struct LineWrapTests {
    /// With wrap on, a long line is bounded to the wrap width instead of widening the
    /// card; the line reflows onto more rows, so the render is narrower and taller. This
    /// is the behavioral contract the Style-pane toggle promises.
    @Test func wrappingLongLinesNarrowsAndHeightensTheCard() throws {
        var wide = SnapshotConfig()
        wide.code = "let a = \"\(String(repeating: "x", count: 400))\""
        wide.language = .swift
        var wrapped = wide
        wrapped.wrapColumns = 60

        let wideImg = try #require(ExportManager.renderCGImage(wide, scale: 1))
        let wrappedImg = try #require(ExportManager.renderCGImage(wrapped, scale: 1))

        #expect(wrappedImg.width < wideImg.width)
        #expect(wrappedImg.height > wideImg.height)
    }

    /// `wrapColumns` round-trips through the settings codec, is cleared when off (so a
    /// later read restores "no wrap"), and a hand-edited out-of-range value is clamped.
    @Test func wrapColumnsPersistAndClampThroughTheCodec() {
        let defaults = UserDefaults(suiteName: "VitrineLineWrapTests-\(UUID().uuidString)")!

        var config = SnapshotConfig()
        config.wrapColumns = 72
        SettingsCodec.persistStyle(config, to: defaults)
        #expect(SettingsCodec.readConfig(from: defaults).wrapColumns == 72)

        config.wrapColumns = nil
        SettingsCodec.persistStyle(config, to: defaults)
        #expect(SettingsCodec.readConfig(from: defaults).wrapColumns == nil)

        defaults.set(5000, forKey: SettingsCodec.Keys.wrapColumns)
        #expect(
            SettingsCodec.readConfig(from: defaults).wrapColumns
                == SettingsDefaults.wrapColumnsRange.upperBound)
    }
}

import Foundation
import Testing

@testable import Vitrine

/// the renderer abstraction for typed inputs.
///
/// These suites prove the isolation properties of the typed-input seam:
///
/// 1. **web rendering** — HTML renders through the local `HTMLRenderer` and URL
///    through the `URLRenderer`; URL capture is gated on the network entitlement,
///    and a gated capture throws a *typed* error, never a blank image.
/// 2. **No-network code path** — the app target provably ships with no network
///    entitlement, so local code rendering cannot reach the network.

// MARK: - Input classification

@Suite("CaptureInput")
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

// MARK: - web rendering (HTML local, URL gated)

@MainActor
@Suite("web rendering")
struct WebRenderingTests {
    @Test func eachWebRendererAcceptsExactlyItsOwnInput() throws {
        // The two web renderers split the input space cleanly: HTML renders locally
        // through HTMLRenderer, a URL only through URLRenderer (whether the capture
        // can run is decided at render time by the network entitlement).
        let url = CaptureInput.url(try #require(URL(string: "https://example.com")))
        #expect(HTMLRenderer().canRender(.html("<h1>Hello</h1>")))
        #expect(!HTMLRenderer().canRender(url))
        #expect(URLRenderer().canRender(url))
        #expect(!URLRenderer().canRender(.html("<h1>Hello</h1>")))
    }

    @Test func urlCaptureWithoutTheEntitlementThrowsTypedNotABlankImage() async throws {
        // The "never a blank image" contract covers the entitlement gate: on a build
        // without the network entitlement, a URL render throws a typed
        // urlCaptureDisabled before touching WebKit — never an empty asset.
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
@Suite("Code rendering needs no network or URL config")
struct CodeRenderingNoNetworkTests {
    /// The app target ships **without** `com.apple.security.network.client`, so the
    /// local rendering render path provably cannot reach the network. The
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
            "local rendering must not request the network client entitlement")
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
@Suite("QuickCapture classification · ", .serialized)
struct QuickCaptureClassificationTests {
    private func freshDefaults() -> UserDefaults {
        testDefaults()
    }

    // These tests target the exact seams `QuickCapture.capture` calls —
    // `LanguageDetector.interpret` for the code path and `classifyURL` for the URL
    // gate. They used to run through a `classify` wrapper that re-implemented the
    // same composition and had no production call site, so they were pinning a copy
    // rather than the truth.

    @Test func clipboardCodeInterpretsWithDetectedLanguage() {
        let interpreted = LanguageDetector.interpret("def greet():\n    pass")
        #expect(interpreted.code == "def greet():\n    pass")
        #expect(interpreted.language == .python)
    }

    @Test func markdownFenceIsStrippedDuringInterpretation() {
        let interpreted = LanguageDetector.interpret("```swift\nlet x = 1\n```")
        #expect(interpreted.code == "let x = 1")
        #expect(interpreted.language == .swift)
    }

    @Test func nonURLTextNeverPassesTheURLGate() {
        // Only a single http(s) URL trips the URL branch; plain code never does,
        // regardless of the opt-in (`capture` consults the gate only when the opt-in
        // is on, and the opt-in behavior itself is covered by the `run` tests below).
        #expect(QuickCapture.classifyURL("let x = 1") == nil)
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
        // as a normal code capture (unchanged local rendering behavior).
        let settings = AppSettings(defaults: freshDefaults())
        settings.treatURLsAsScreenshot = false
        let recents = RecentsStore(defaults: freshDefaults())
        let outcome = QuickCapture.run(
            settings: settings, recents: recents, clipboard: { "https://example.com" })
        #expect(outcome == .copied)
        #expect(recents.captures.first?.code == "https://example.com")
    }
}

// MARK: - Code line wrap

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

    /// The wrap width belongs to the code column. Turning on line numbers should add a
    /// gutter beside that column, not steal columns from it and cause extra wraps.
    @Test func wrappingWithLineNumbersKeepsTheCodeColumnWidth() throws {
        var wrapped = SnapshotConfig()
        wrapped.code = "let a = \"\(String(repeating: "x", count: 400))\""
        wrapped.language = .swift
        wrapped.wrapColumns = 80

        var withGutter = wrapped
        withGutter.showLineNumbers = true

        let wrappedImg = try #require(ExportManager.renderCGImage(wrapped, scale: 1))
        let gutterImg = try #require(ExportManager.renderCGImage(withGutter, scale: 1))

        #expect(gutterImg.width > wrappedImg.width)
    }

    /// `wrapColumns` round-trips through the settings codec, is cleared when off (so a
    /// later read restores "no wrap"), and a hand-edited out-of-range value is clamped.
    @Test func wrapColumnsPersistAndClampThroughTheCodec() {
        let defaults = testDefaults()

        #expect(SettingsCodec.Keys.all.contains(SettingsCodec.Keys.wrapColumns))
        #expect(SettingsCodec.Keys.editorSessionSeed.contains(SettingsCodec.Keys.wrapColumns))

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

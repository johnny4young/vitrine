import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

/// CS-044 — web viewport presets, capture modes, wait strategies, and safety caps.
///
/// These suites prove the acceptance criteria the ticket asks for, as values the
/// tests drive directly without a web view:
///
/// 1. **Viewport presets** — 1200×630, 1440×900, 1920×1080, a mobile size, and a
///    custom width/height (clamped into a safe range).
/// 2. **Capture mode** — the user can choose the visible viewport or a full-page
///    capture.
/// 3. **Wait strategies** — DOM loaded, a fixed delay, and a best-effort
///    network-quiet settle.
/// 4. **Safety caps** — a maximum captured page height and a hard timeout ceiling
///    bound runaway memory and time use.
/// 5. **Bounded lazy-load** — the full-page scroll pass is strictly bounded so an
///    infinite-scroll page cannot loop forever.
///
/// ## Live WebKit vs. pure logic
///
/// Almost everything here is pure logic — preset sizes, capture-mode flags, wait
/// budgets, the timeout clamp, and config composition — so those suites always run
/// and assert on every machine. The single suite that rasterizes a real full-page
/// capture through `WKWebView` is gated on `WebKitAvailability.canRenderOffscreen`
/// (defined in `HTMLRendererTests`), because a sandboxed, ad-hoc-signed test host
/// cannot launch a web content process; it is reported as **skipped** there, never
/// silently passed.

// MARK: - Viewport presets

@Suite("Web viewport presets · CS-044")
struct WebViewportPresetTests {
    @Test func theFixedPresetsCoverTheRequiredSizes() {
        // The acceptance set: OpenGraph, two desktop sizes, and a mobile size, each
        // mapping to its exact documented pixel size.
        #expect(WebSnapshotConfig.ViewportPreset.openGraph.size == CGSize(width: 1200, height: 630))
        #expect(WebSnapshotConfig.ViewportPreset.desktop.size == CGSize(width: 1440, height: 900))
        #expect(WebSnapshotConfig.ViewportPreset.fullHD.size == CGSize(width: 1920, height: 1080))
        #expect(WebSnapshotConfig.ViewportPreset.mobile.size == CGSize(width: 390, height: 844))
    }

    @Test func theFixedPresetListIsExactlyTheNonCustomPresets() {
        // The picker lists every fixed preset and not the parameterized custom one.
        let kinds = WebSnapshotConfig.ViewportPreset.fixedPresets.map(\.kind)
        #expect(kinds == [.openGraph, .desktop, .fullHD, .mobile])
        #expect(!kinds.contains(.custom))
    }

    @Test func aCustomPresetCarriesItsOwnSize() {
        let preset = WebSnapshotConfig.ViewportPreset.custom(width: 800, height: 1200)
        #expect(preset.size == CGSize(width: 800, height: 1200))
        #expect(preset.kind == .custom)
    }

    @Test func aCustomPresetClampsAnOutOfRangeSizeIntoTheSafeRange() {
        // The clamping factory keeps a custom viewport usable and memory-safe: a
        // too-small or too-large dimension is pulled into `customDimensionRange`.
        let range = WebSnapshotConfig.ViewportPreset.customDimensionRange
        let tooSmall = WebSnapshotConfig.ViewportPreset.custom(clampingWidth: 1, height: 1)
        #expect(tooSmall.size == CGSize(width: range.lowerBound, height: range.lowerBound))
        let tooLarge = WebSnapshotConfig.ViewportPreset.custom(
            clampingWidth: 999_999, height: 999_999)
        #expect(tooLarge.size == CGSize(width: range.upperBound, height: range.upperBound))
        // A value already inside the range is left untouched.
        let inRange = WebSnapshotConfig.ViewportPreset.custom(clampingWidth: 1280, height: 720)
        #expect(inRange.size == CGSize(width: 1280, height: 720))
    }

    @Test func clampingASingleDimensionMatchesTheRange() {
        let range = WebSnapshotConfig.ViewportPreset.customDimensionRange
        #expect(WebSnapshotConfig.ViewportPreset.clampCustomDimension(-5) == range.lowerBound)
        #expect(WebSnapshotConfig.ViewportPreset.clampCustomDimension(10_000) == range.upperBound)
        #expect(WebSnapshotConfig.ViewportPreset.clampCustomDimension(2000) == 2000)
    }

    @Test func resolvingAPersistedKindRebuildsThePreset() {
        // The persistence round-trip: a stored kind plus a stored custom size
        // reconstructs the preset, ignoring the size for a fixed kind and clamping
        // it for a custom kind.
        #expect(
            WebSnapshotConfig.ViewportPreset.resolve(
                kind: .desktop, customWidth: 1, customHeight: 1) == .desktop)
        let custom = WebSnapshotConfig.ViewportPreset.resolve(
            kind: .custom, customWidth: 1024, customHeight: 768)
        #expect(custom == .custom(width: 1024, height: 768))
        // A custom kind with an out-of-range stored size is clamped, never degenerate.
        let clamped = WebSnapshotConfig.ViewportPreset.resolve(
            kind: .custom, customWidth: 0, customHeight: -1)
        let floor = WebSnapshotConfig.ViewportPreset.customDimensionRange.lowerBound
        #expect(clamped == .custom(width: floor, height: floor))
    }

    @Test func everyPresetKindHasANonEmptyDisplayName() {
        for kind in WebSnapshotConfig.ViewportPreset.Kind.allCases {
            let preset = WebSnapshotConfig.ViewportPreset.resolve(
                kind: kind, customWidth: 800, customHeight: 600)
            #expect(!preset.displayName.isEmpty)
        }
    }
}

// MARK: - Capture mode

@Suite("Web capture mode · CS-044")
struct WebCaptureModeTests {
    @Test func bothModesAreOffered() {
        #expect(WebSnapshotConfig.CaptureMode.allCases == [.visibleViewport, .fullPage])
    }

    @Test func onlyFullPageCapturesPastTheViewport() {
        #expect(WebSnapshotConfig.CaptureMode.visibleViewport.capturesFullHeight == false)
        #expect(WebSnapshotConfig.CaptureMode.fullPage.capturesFullHeight)
    }

    @Test func captureModesRoundTripThroughTheirRawValue() {
        for mode in WebSnapshotConfig.CaptureMode.allCases {
            #expect(WebSnapshotConfig.CaptureMode(rawValue: mode.rawValue) == mode)
            #expect(!mode.displayName.isEmpty)
        }
    }
}

// MARK: - Wait strategies

@Suite("Web wait strategies · CS-044")
struct WebWaitStrategyTests {
    @Test func theThreeStrategiesAreAvailable() {
        // DOM loaded, a fixed delay, and a best-effort network-quiet settle.
        #expect(WebSnapshotConfig.WaitStrategy.Kind.allCases.count == 3)
        #expect(
            Set(WebSnapshotConfig.WaitStrategy.Kind.allCases)
                == [.domContentLoaded, .fixedDelay, .networkQuiet])
    }

    @Test func domContentLoadedAddsNoPostLoadWait() {
        let strategy = WebSnapshotConfig.WaitStrategy.domContentLoaded
        #expect(strategy.postLoadDelay == .zero)
        #expect(strategy.totalBudget == WebSnapshotConfig.WaitStrategy.baseLoadBudget)
        #expect(strategy.kind == .domContentLoaded)
    }

    @Test func aFixedDelayExtendsTheBudgetByTheDelay() {
        let delay = Duration.seconds(3)
        let strategy = WebSnapshotConfig.WaitStrategy.fixedDelay(delay)
        #expect(strategy.postLoadDelay == delay)
        #expect(strategy.totalBudget == WebSnapshotConfig.WaitStrategy.baseLoadBudget + delay)
        #expect(strategy.kind == .fixedDelay)
    }

    @Test func networkQuietExtendsTheBudgetByItsBudget() {
        let budget = Duration.seconds(5)
        let strategy = WebSnapshotConfig.WaitStrategy.networkQuiet(budget: budget)
        #expect(strategy.postLoadDelay == budget)
        #expect(strategy.totalBudget == WebSnapshotConfig.WaitStrategy.baseLoadBudget + budget)
        #expect(strategy.kind == .networkQuiet)
    }

    @Test func resolvingAPersistedKindRebuildsTheStrategy() {
        #expect(
            WebSnapshotConfig.WaitStrategy.resolve(kind: .domContentLoaded, extraWaitSeconds: 9)
                == .domContentLoaded)
        #expect(
            WebSnapshotConfig.WaitStrategy.resolve(kind: .fixedDelay, extraWaitSeconds: 4)
                == .fixedDelay(.seconds(4)))
        #expect(
            WebSnapshotConfig.WaitStrategy.resolve(kind: .networkQuiet, extraWaitSeconds: 6)
                == .networkQuiet(budget: .seconds(6)))
    }

    @Test func resolvingClampsANegativeWaitToZero() {
        // A corrupt/hand-edited negative seconds can never produce a negative
        // `Duration`: it clamps to zero (CS-050 defensive posture).
        #expect(
            WebSnapshotConfig.WaitStrategy.resolve(kind: .fixedDelay, extraWaitSeconds: -10)
                == .fixedDelay(.zero))
        #expect(
            WebSnapshotConfig.WaitStrategy.resolve(kind: .networkQuiet, extraWaitSeconds: -1)
                == .networkQuiet(budget: .zero))
    }

    @Test func everyStrategyKindHasANonEmptyDisplayName() {
        let strategies: [WebSnapshotConfig.WaitStrategy] = [
            .domContentLoaded, .fixedDelay(.seconds(1)), .networkQuiet(budget: .seconds(1)),
        ]
        for strategy in strategies {
            #expect(!strategy.displayName.isEmpty)
        }
    }
}

// MARK: - Safety caps and the effective timeout

@Suite("Web capture safety caps · CS-044")
struct WebSafetyCapsTests {
    @Test func theStandardCapsBoundHeightAndTime() {
        let caps = WebSnapshotConfig.SafetyCaps.standard
        #expect(caps.maxPageHeight > 0)
        #expect(caps.maxTimeout > .zero)
    }

    @Test func aFullPageHeightTallerThanTheCapIsClipped() {
        let caps = WebSnapshotConfig.SafetyCaps(maxPageHeight: 5000, maxTimeout: .seconds(60))
        // A document far taller than the cap is clipped to the cap, so the bitmap's
        // pixel count is bounded no matter how long the page is.
        #expect(caps.clampPageHeight(50_000, viewportHeight: 800) == 5000)
        // A normal page shorter than the cap keeps its content height.
        #expect(caps.clampPageHeight(3200, viewportHeight: 800) == 3200)
    }

    @Test func aNonPositiveContentHeightFallsBackToTheViewportHeight() {
        // A failed measurement degrades to the viewport height rather than a
        // zero-height (undrawable) capture.
        let caps = WebSnapshotConfig.SafetyCaps(maxPageHeight: 5000, maxTimeout: .seconds(60))
        #expect(caps.clampPageHeight(0, viewportHeight: 720) == 720)
        #expect(caps.clampPageHeight(-100, viewportHeight: 720) == 720)
    }

    @Test func aContentHeightBelowTheViewportFloorsToTheViewportHeight() {
        // A short full-page document (content shorter than the viewport) floors to the
        // viewport height, so a full-page capture is never *shorter* than the visible
        // viewport — it fills it. This is the floor between the non-positive fallback
        // and the normal pass-through, and it sits below the cap so the cap is inert.
        let caps = WebSnapshotConfig.SafetyCaps(maxPageHeight: 5000, maxTimeout: .seconds(60))
        #expect(caps.clampPageHeight(300, viewportHeight: 720) == 720)
        // Content exactly at the viewport height is left at the viewport height.
        #expect(caps.clampPageHeight(720, viewportHeight: 720) == 720)
        // A viewport height of zero (degenerate) still yields a drawable 1pt floor.
        #expect(caps.clampPageHeight(0, viewportHeight: 0) == 1)
    }

    @Test func theTimeoutClampNeverExceedsTheCeiling() {
        // The hard timeout cap: a requested budget over the ceiling is clamped down;
        // a smaller budget is left as-is.
        let ceiling = Duration.seconds(60)
        #expect(
            WebSnapshotConfig.SafetyCaps.clampTimeout(.seconds(120), to: ceiling) == ceiling)
        #expect(
            WebSnapshotConfig.SafetyCaps.clampTimeout(.seconds(10), to: ceiling) == .seconds(10))
    }

    @Test func aGenerousWaitStrategyCannotExceedTheHardTimeoutCap() throws {
        // Even a wait strategy whose own budget would blow past the ceiling resolves
        // to a config timeout no greater than `maxTimeout` — the cap is always
        // enforced through the composed `timeout`.
        let url = try #require(URL(string: "https://example.com"))
        let caps = WebSnapshotConfig.SafetyCaps(maxPageHeight: 10_000, maxTimeout: .seconds(45))
        let config = try WebSnapshotConfig(
            captureURL: url,
            waitStrategy: .networkQuiet(budget: .seconds(600)),
            safetyCaps: caps)
        #expect(config.timeout == .seconds(45))
        #expect(config.timeout <= caps.maxTimeout)
    }

    @Test func theDefaultConfigTimeoutHonorsTheStandardCeiling() throws {
        // The default DOM-loaded strategy's budget is under the standard ceiling, so
        // the default config's timeout is the strategy budget, still within the cap.
        let url = try #require(URL(string: "https://example.com"))
        let config = try WebSnapshotConfig(captureURL: url)
        #expect(config.timeout <= WebSnapshotConfig.SafetyCaps.standard.maxTimeout)
        #expect(config.timeout == WebSnapshotConfig.WaitStrategy.baseLoadBudget)
    }
}

// MARK: - Config composition and defaults

@Suite("Web capture config composition · CS-044")
struct WebCaptureConfigCompositionTests {
    @Test func theDefaultConfigIsTheDeterministicSocialCardVisibleCapture() throws {
        let url = try #require(URL(string: "https://example.com"))
        let config = try WebSnapshotConfig(captureURL: url)
        #expect(config.viewportPreset == .openGraph)
        #expect(config.viewport == CGSize(width: 1200, height: 630))
        #expect(config.captureMode == .visibleViewport)
        #expect(config.waitStrategy == .domContentLoaded)
        #expect(config.safetyCaps == .standard)
    }

    @Test func theConfigCarriesEveryChosenKnob() throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let config = try WebSnapshotConfig(
            captureURL: url,
            viewportPreset: .custom(width: 1024, height: 768),
            captureMode: .fullPage,
            waitStrategy: .fixedDelay(.seconds(2)))
        #expect(config.viewport == CGSize(width: 1024, height: 768))
        #expect(config.captureMode == .fullPage)
        #expect(config.waitStrategy == .fixedDelay(.seconds(2)))
    }

    @Test func aRendererConfiguredFromSettingsAdoptsTheUsersChoices() {
        // The seam that connects the Input pane to the URL render path: a renderer
        // built from settings carries exactly the viewport, capture mode, and wait
        // strategy the user selected.
        let settings = AppSettings(defaults: Self.isolatedDefaults())
        settings.webCapture.viewportKind = .fullHD
        settings.webCapture.captureMode = .fullPage
        settings.webCapture.waitKind = .fixedDelay
        settings.webCapture.waitSeconds = 4
        settings.export.scale = 1

        let renderer = URLRenderer.configured(from: settings)
        #expect(renderer.viewportPreset == .fullHD)
        #expect(renderer.captureMode == .fullPage)
        #expect(renderer.waitStrategy == .fixedDelay(.seconds(4)))
        #expect(renderer.scale == 1)
    }

    @Test func aCustomViewportFromSettingsIsClampedIntoTheSafeRange() {
        // A hand-edited out-of-range custom size persisted in settings can never reach
        // the renderer as a degenerate viewport.
        let settings = AppSettings(defaults: Self.isolatedDefaults())
        settings.webCapture.viewportKind = .custom
        settings.webCapture.customViewportWidth = 100_000
        settings.webCapture.customViewportHeight = 1
        let renderer = URLRenderer.configured(from: settings)
        let range = WebSnapshotConfig.ViewportPreset.customDimensionRange
        #expect(renderer.viewportPreset.size.width == CGFloat(range.upperBound))
        #expect(renderer.viewportPreset.size.height == CGFloat(range.lowerBound))
    }

    @Test func theComposedViewportAndWaitMatchEveryPersistedDiscriminant() {
        // The two composed accessors must agree with the stored discriminant for every
        // case, not just the `.fullHD`/`.fixedDelay` pair the renderer seam covers. A
        // fixed viewport kind composes to that exact preset (ignoring the stored custom
        // size), and the network-quiet wait composes to a budget of the stored seconds —
        // the persistence seam the Input pane relies on.
        let settings = AppSettings(defaults: Self.isolatedDefaults())
        for kind in WebSnapshotConfig.ViewportPreset.Kind.allCases where kind != .custom {
            settings.webCapture.viewportKind = kind
            // The stored custom size is deliberately set to prove a fixed kind ignores it.
            settings.webCapture.customViewportWidth = 4321
            settings.webCapture.customViewportHeight = 1234
            #expect(settings.webCapture.viewportPreset.kind == kind)
            #expect(
                settings.webCapture.viewportPreset
                    == WebSnapshotConfig.ViewportPreset.resolve(
                        kind: kind, customWidth: 1, customHeight: 1))
        }

        settings.webCapture.waitKind = .networkQuiet
        settings.webCapture.waitSeconds = 6
        #expect(settings.webCapture.waitStrategy == .networkQuiet(budget: .seconds(6)))

        settings.webCapture.waitKind = .domContentLoaded
        // The DOM-loaded strategy ignores the stored seconds entirely.
        #expect(settings.webCapture.waitStrategy == .domContentLoaded)
    }

    /// A throwaway, uniquely-named defaults suite so a test never touches real app
    /// data and never collides with another test's settings.
    private static func isolatedDefaults() -> UserDefaults {
        let suite = "com.johnny4young.vitrine.web-config-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

// MARK: - Persistence round-trip

@Suite("Web capture settings persist and reset · CS-044")
struct WebCaptureSettingsPersistenceTests {
    @Test func theWebCaptureChoicesSurviveAReload() {
        // The user's viewport/mode/wait choices round-trip through `UserDefaults`, so
        // the picker shows the same selection on the next launch.
        let suite = "com.johnny4young.vitrine.web-persist-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        first.webCapture.viewportKind = .mobile
        first.webCapture.customViewportWidth = 1100
        first.webCapture.customViewportHeight = 1400
        first.webCapture.captureMode = .fullPage
        first.webCapture.waitKind = .networkQuiet
        first.webCapture.waitSeconds = 7

        let second = AppSettings(defaults: defaults)
        #expect(second.webCapture.viewportKind == .mobile)
        #expect(second.webCapture.customViewportWidth == 1100)
        #expect(second.webCapture.customViewportHeight == 1400)
        #expect(second.webCapture.captureMode == .fullPage)
        #expect(second.webCapture.waitKind == .networkQuiet)
        #expect(second.webCapture.waitSeconds == 7)
    }

    @Test func resetReturnsTheWebCaptureChoicesToTheirDefaults() {
        let suite = "com.johnny4young.vitrine.web-reset-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = AppSettings(defaults: defaults)
        settings.webCapture.viewportKind = .fullHD
        settings.webCapture.captureMode = .fullPage
        settings.webCapture.waitKind = .fixedDelay
        settings.webCapture.waitSeconds = 9

        settings.resetToDefaults()
        #expect(settings.webCapture.viewportKind == WebDefaults.viewportKind)
        #expect(settings.webCapture.captureMode == WebDefaults.captureMode)
        #expect(settings.webCapture.waitKind == WebDefaults.waitKind)
        #expect(settings.webCapture.waitSeconds == WebDefaults.waitSeconds)
    }

    @Test func aGarbagePersistedValueFallsBackToTheDocumentedDefault() {
        // The defensive-read posture (CS-050): an unrecognized raw value resolves to
        // the default rather than trapping or producing an invalid setting.
        let suite = "com.johnny4young.vitrine.web-garbage-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("not-a-real-kind", forKey: "webViewportKind")
        defaults.set("nonsense", forKey: "webCaptureMode")
        defaults.set("bogus", forKey: "webWaitKind")
        defaults.set(-99, forKey: "webWaitSeconds")
        defaults.set(-5, forKey: "webCustomViewportWidth")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.webCapture.viewportKind == WebDefaults.viewportKind)
        #expect(settings.webCapture.captureMode == WebDefaults.captureMode)
        #expect(settings.webCapture.waitKind == WebDefaults.waitKind)
        // A negative persisted seconds clamps to the documented non-negative range.
        #expect(settings.webCapture.waitSeconds >= 0)
        // A negative persisted custom width clamps into the safe range.
        #expect(
            settings.webCapture.customViewportWidth
                >= WebSnapshotConfig.ViewportPreset.customDimensionRange.lowerBound)
    }

    @Test func anOversizedPersistedWaitClampsToTheWaitCeiling() {
        // The other half of the wait-seconds clamp: a hand-edited value far above the
        // ceiling reads back as the ceiling, so the picker can never seed a wait that
        // would always blow past the hard timeout cap. The negative case is covered
        // above; this proves the upper bound is enforced on read, not just the lower.
        let suite = "com.johnny4young.vitrine.web-wait-ceiling-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(99_999, forKey: "webWaitSeconds")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.webCapture.waitSeconds == WebDefaults.waitSecondsRange.upperBound)
        // A value already inside the range is read back unchanged.
        defaults.set(12, forKey: "webWaitSeconds")
        #expect(AppSettings(defaults: defaults).webCapture.waitSeconds == 12)
    }

    @Test func anOutOfRangePersistedCustomHeightClampsOnRead() {
        // The custom-height read path mirrors the width path: an out-of-range stored
        // height is clamped into the safe range on read, so neither custom dimension
        // can reach the composed preset as a degenerate value. The width path is
        // covered above; this closes the symmetric gap on height.
        let range = WebSnapshotConfig.ViewportPreset.customDimensionRange
        let suite = "com.johnny4young.vitrine.web-custom-height-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(-7, forKey: "webCustomViewportHeight")
        #expect(AppSettings(defaults: defaults).webCapture.customViewportHeight == range.lowerBound)

        defaults.set(500_000, forKey: "webCustomViewportHeight")
        #expect(AppSettings(defaults: defaults).webCapture.customViewportHeight == range.upperBound)
    }

    @Test func theNewSettingsAdvanceTheSchemaWithoutLosingExistingValues() {
        // CS-044 adds additive keys with documented defaults: a store written by the
        // current build reads back at the current schema version, and the new web
        // keys do not disturb an unrelated existing value.
        let suite = "com.johnny4young.vitrine.web-schema-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let settings = AppSettings(defaults: defaults)
        settings.export.autoCopy = false
        settings.webCapture.captureMode = .fullPage

        #expect(defaults.integer(forKey: SettingsSchema.versionKey) == SettingsSchema.current)
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.export.autoCopy == false)
        #expect(reloaded.webCapture.captureMode == .fullPage)
    }
}

// MARK: - Bounded lazy-load policy

@Suite("Web full-page lazy-load is bounded · CS-044")
struct WebLazyLoadBoundTests {
    @Test func theLazyLoadScrollPassIsStrictlyBounded() {
        // The documented, bounded lazy-load behavior: the scroll pass performs a
        // fixed, finite number of steps, so an infinite-scroll page cannot loop
        // forever and the pass always terminates.
        #expect(URLSnapshotEngine.maxLazyLoadSteps > 0)
        #expect(URLSnapshotEngine.maxLazyLoadSteps <= 50)
        #expect(URLSnapshotEngine.lazyLoadStepPause > .zero)
    }
}

// MARK: - Live full-page capture of a tall local page (real image)

/// The one suite that rasterizes a full-page capture through `WKWebView`. A live
/// capture cannot use a real network in the test host, and validation rejects a
/// `file:` URL, so this drives the engine through the explicit hermetic hook
/// (`init(localFileURL:)`) against a local fixture page taller than the viewport.
/// It proves that a full-page capture extends past the visible viewport to the
/// document's content height, while a visible-viewport capture of the same page is
/// exactly the viewport size. It runs only where a web content process can launch
/// and is reported skipped otherwise.
@MainActor
@Suite(
    "URLSnapshotEngine full-page capture · CS-044",
    .enabled("requires a launchable WKWebView web process (unavailable in a sandboxed test host)") {
        await WebKitAvailability.canRenderOffscreen()
    })
struct WebFullPageCaptureRenderTests {
    /// A local HTML page whose body is forced far taller than any test viewport, so a
    /// full-page capture has real content below the fold to extend into. The explicit
    /// height makes the content height deterministic.
    private static func writeTallPage(contentHeight: Int) throws -> URL {
        let html = """
            <!doctype html><html><head><meta charset="utf-8"><style>
            html,body{margin:0;padding:0}
            body{background:#0b1020}
            .tall{height:\(contentHeight)px;background:linear-gradient(#0b1020,#203a8f)}
            </style></head><body><div class="tall"></div></body></html>
            """
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineFullPageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("tall.html")
        try html.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test func aVisibleViewportCaptureIsExactlyTheViewportSize() async throws {
        let engine = URLSnapshotEngine()
        let config = WebSnapshotConfig(
            localFileURL: try Self.writeTallPage(contentHeight: 4000),
            viewportPreset: .custom(width: 600, height: 400),
            captureMode: .visibleViewport, scale: 1)
        let image = try await engine.snapshot(of: config)
        // The visible-viewport mode ignores the tall content: the bitmap is exactly
        // viewport × scale, the determinism the acceptance criteria require.
        #expect(image.width == 600)
        #expect(image.height == 400)
    }

    @Test func aFullPageCaptureExtendsToTheContentHeight() async throws {
        let contentHeight = 3000
        let engine = URLSnapshotEngine()
        let config = WebSnapshotConfig(
            localFileURL: try Self.writeTallPage(contentHeight: contentHeight),
            viewportPreset: .custom(width: 600, height: 400),
            captureMode: .fullPage, scale: 1)
        let image = try await engine.snapshot(of: config)
        // The width is still the preset width.
        #expect(image.width == 600)
        // The height extends well past the 400pt viewport toward the content height,
        // and stays within the safety cap. (Exact pixels vary slightly with WebKit's
        // layout, so assert the page grew substantially rather than an exact number.)
        #expect(image.height > 400)
        #expect(image.height >= contentHeight - 200)
        #expect(CGFloat(image.height) <= config.safetyCaps.maxPageHeight)
    }

    @Test func aFullPageCaptureIsClippedToTheMaxPageHeightCap() async throws {
        // A document far taller than the cap is clipped to the cap, so the bitmap's
        // pixel count is bounded no matter how long the page is.
        let cappedCaps = WebSnapshotConfig.SafetyCaps(maxPageHeight: 1200, maxTimeout: .seconds(60))
        let engine = URLSnapshotEngine()
        let config = WebSnapshotConfig(
            localFileURL: try Self.writeTallPage(contentHeight: 8000),
            viewportPreset: .custom(width: 500, height: 400),
            captureMode: .fullPage, safetyCaps: cappedCaps, scale: 1)
        let image = try await engine.snapshot(of: config)
        #expect(image.width == 500)
        // Clipped to the 1200pt cap, not the 8000pt document height.
        #expect(image.height == 1200)
    }
}

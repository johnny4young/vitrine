import AppKit
import Foundation
import Testing

@testable import Vitrine

// CS-053 — window restoration and multi-window editing.
//
// The acceptance bullets these tests pin:
//   • the editor window remembers size/position across launches (frame-autosave
//     identity is stable per window, and a restored frame is recovered onto a
//     visible screen);
//   • users can open multiple editor windows, each with its own config — modeled by
//     independent per-window settings that do not clobber the global default;
//   • per-window config does not clobber global defaults; "make default" is explicit;
//   • behaves correctly across display changes (unplugged monitor) without
//     off-screen windows;
//   • the per-window draft round-trips through state restoration (encode/decode).

// MARK: - Per-window identity (frame autosave name)

@Suite("Editor window identity")
struct EditorWindowIdentityTests {
    @Test func primaryKeepsTheBareLegacyAutosaveName() {
        // The first window keeps the bare `editor` name so an upgrade from the prior
        // single-window build restores the frame it had saved.
        #expect(EditorWindowIdentity.primary.index == 1)
        #expect(EditorWindowIdentity.primary.frameAutosaveName == "editor")
    }

    @Test func additionalWindowsAppendTheirIndex() {
        #expect(EditorWindowIdentity(index: 2).frameAutosaveName == "editor-2")
        #expect(EditorWindowIdentity(index: 3).frameAutosaveName == "editor-3")
    }

    @Test func restorationIdentifierMirrorsAutosaveName() {
        #expect(EditorWindowIdentity(index: 1).restorationIdentifier.rawValue == "editor")
        #expect(EditorWindowIdentity(index: 4).restorationIdentifier.rawValue == "editor-4")
    }

    @Test func windowTitleDisambiguatesAdditionalWindows() {
        // The primary window reads simply "Vitrine Editor"; additional windows append
        // their index so several open editors are distinguishable in the Window menu
        // and Mission Control rather than all reading identically (CS-053). The index
        // is the same suffix the autosave name and accessibility identifier use.
        #expect(EditorWindowIdentity.primary.windowTitle == "Vitrine Editor")
        #expect(EditorWindowIdentity(index: 2).windowTitle == "Vitrine Editor 2")
        #expect(EditorWindowIdentity(index: 3).windowTitle == "Vitrine Editor 3")
        // The bare base name has no trailing index, so it never collides with window 2.
        #expect(
            EditorWindowIdentity.primary.windowTitle != EditorWindowIdentity(index: 2).windowTitle)
    }

    @Test func aNonPositiveIndexClampsToThePrimarySlot() {
        // A stray non-positive index never mints an unusable autosave name.
        #expect(EditorWindowIdentity(index: 0).index == 1)
        #expect(EditorWindowIdentity(index: -5).frameAutosaveName == "editor")
    }

    @Test func nextAvailableIndexFillsTheLowestFreeSlot() {
        #expect(EditorWindowIdentity.nextAvailableIndex(notIn: []) == 1)
        #expect(EditorWindowIdentity.nextAvailableIndex(notIn: [1]) == 2)
        #expect(EditorWindowIdentity.nextAvailableIndex(notIn: [1, 2, 3]) == 4)
        // A freed middle slot is reused before a new, higher index is minted, so a
        // closed window's remembered frame is what the next window adopts.
        #expect(EditorWindowIdentity.nextAvailableIndex(notIn: [1, 3]) == 2)
        #expect(EditorWindowIdentity.nextAvailableIndex(notIn: [2, 3]) == 1)
    }

    @Test func identityIsValueEqualByIndex() {
        #expect(EditorWindowIdentity(index: 2) == EditorWindowIdentity(index: 2))
        #expect(EditorWindowIdentity(index: 2) != EditorWindowIdentity(index: 3))
        #expect(EditorWindowIdentity(index: 1) == .primary)
    }
}

// MARK: - Per-window draft config encode / decode

@MainActor
@Suite("Editor window state encode/decode")
struct EditorWindowStateTests {
    /// A config exercising every archived field with non-default values, so a lost or
    /// mistyped key surfaces as a round-trip mismatch.
    private func richConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42\nprint(answer)"
        config.language = .python
        config.theme = .dracula
        config.fontName = "Fira Code"
        config.fontSize = 18
        config.fontLigatures = true
        config.padding = 48
        config.cornerRadius = 18
        config.shadowRadius = 40
        config.showChrome = false
        config.showShadow = false
        config.showLineNumbers = true
        config.highlightedLineRanges = [1...1, 3...5]
        config.background = .gradient(.sunset)
        config.metadata = SnapshotMetadata(
            filename: "main.py", title: "Demo", caption: "A caption", showLanguageBadge: true)
        return config
    }

    @Test func roundTripsEveryFieldThroughTheStateBridge() {
        let original = richConfig()
        let restored = EditorWindowState(config: original).config()

        #expect(restored.code == original.code)
        #expect(restored.language == original.language)
        #expect(restored.theme.id == original.theme.id)
        #expect(restored.fontName == original.fontName)
        #expect(restored.fontSize == original.fontSize)
        #expect(restored.fontLigatures == original.fontLigatures)
        #expect(restored.padding == original.padding)
        #expect(restored.cornerRadius == original.cornerRadius)
        #expect(restored.shadowRadius == original.shadowRadius)
        #expect(restored.showChrome == original.showChrome)
        #expect(restored.showShadow == original.showShadow)
        #expect(restored.showLineNumbers == original.showLineNumbers)
        #expect(restored.highlightedLineRanges == original.highlightedLineRanges)
        #expect(restored.background == original.background)
        #expect(restored.metadata == original.metadata)
    }

    @Test func roundTripsThroughJSONData() throws {
        let original = richConfig()
        let data = try #require(EditorWindowState(config: original).encoded())
        let decoded = try #require(EditorWindowState.decoded(from: data))
        let restored = decoded.config()

        #expect(restored.code == original.code)
        #expect(restored.theme.id == original.theme.id)
        #expect(restored.language == original.language)
        #expect(restored.background == original.background)
        #expect(restored.highlightedLineRanges == original.highlightedLineRanges)
    }

    @Test func defaultConfigRoundTripsToItself() {
        // The empty default draft must survive a round trip unchanged so a brand-new
        // window restores to exactly the factory configuration.
        let restored = EditorWindowState(config: SnapshotConfig()).config()
        #expect(restored == SnapshotConfig())
    }

    @Test func decodingCorruptOrMissingDataYieldsNil() {
        #expect(EditorWindowState.decoded(from: nil) == nil)
        #expect(EditorWindowState.decoded(from: Data("not json".utf8)) == nil)
        #expect(EditorWindowState.decoded(from: Data()) == nil)
    }

    @Test func aPartialPayloadDecodesToFieldDefaults() throws {
        // A truncated restoration blob (only `code` present) must still rebuild a
        // complete, valid draft: every absent field falls back to its `SnapshotConfig`
        // default rather than failing the decode (CS-050 posture).
        let partial = #"{"code":"x = 1"}"#
        let state = try #require(EditorWindowState.decoded(from: Data(partial.utf8)))
        let config = state.config()
        let fallback = SnapshotConfig()
        #expect(config.code == "x = 1")
        #expect(config.language == fallback.language)
        #expect(config.theme.id == fallback.theme.id)
        #expect(config.fontName == fallback.fontName)
        #expect(config.padding == fallback.padding)
        #expect(config.background == fallback.background)
    }

    @Test func anUnknownThemeIDFallsBackToTheDefaultTheme() {
        // A draft naming a theme this build does not know about resolves to One Dark
        // (the documented fallback) rather than producing an invalid theme.
        var state = EditorWindowState(config: SnapshotConfig())
        state.themeID = "no-such-theme-xyz"
        #expect(state.config().theme.id == Theme.oneDark.id)
    }

    @Test func aCustomThemeIDResolvesThroughTheProvidedStore() {
        // A window editing a *custom* theme restores it by resolving the id through a
        // custom-theme store, proving the bridge is not limited to built-ins.
        let store = CustomThemeStore(
            defaults: UserDefaults(suiteName: "WindowStateThemeTests-\(UUID().uuidString)")!)
        let custom = store.addTheme(
            named: "My Theme",
            palette: ThemePalette(
                background: HexColor("#101010")!, foreground: HexColor("#EEEEEE")!))

        var config = SnapshotConfig()
        config.theme = custom
        let restored = EditorWindowState(config: config).config(themes: store)
        #expect(restored.theme.id == custom.id)
        #expect(restored.theme.displayName == custom.displayName)
    }

    @Test func outOfRangeNumericFieldsAreClampedOnDecode() {
        // A hand-edited blob with absurd numbers can never drive the renderer out of
        // bounds: numeric fields are clamped to their documented ranges, mirroring
        // AppSettings' defensive reads.
        var state = EditorWindowState(config: SnapshotConfig())
        state.fontSize = 9999
        state.padding = -100
        let config = state.config()
        #expect(config.fontSize == SettingsDefaults.fontSizeRange.upperBound)
        #expect(config.padding == SettingsDefaults.paddingRange.lowerBound)
    }

    @Test func anUnknownFontNameFallsBackToTheDefaultFont() {
        var state = EditorWindowState(config: SnapshotConfig())
        state.fontName = "Definitely Not Installed 9000"
        #expect(state.config().fontName == SnapshotConfig().fontName)
    }
}

// MARK: - Off-screen recovery (frame geometry)

@Suite("Window frame off-screen recovery")
struct WindowFrameSolverTests {
    /// A single 1440×900 main screen at the origin (a common laptop layout).
    private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func anOnScreenFrameIsReturnedUnchanged() {
        let frame = CGRect(x: 100, y: 80, width: 800, height: 600)
        #expect(WindowFrameSolver.isReachable(frame, on: [laptop]))
        #expect(WindowFrameSolver.onScreenFrame(for: frame, visibleFrames: [laptop]) == frame)
    }

    @Test func aFullyOffScreenFrameIsPulledBackOntoTheScreen() {
        // A frame saved on a now-unplugged second monitor far to the right.
        let stranded = CGRect(x: 4000, y: 2000, width: 800, height: 600)
        #expect(!WindowFrameSolver.isReachable(stranded, on: [laptop]))

        let recovered = WindowFrameSolver.onScreenFrame(for: stranded, visibleFrames: [laptop])
        // Size is preserved and the recovered frame sits fully inside the screen.
        #expect(recovered.size == stranded.size)
        #expect(WindowFrameSolver.isReachable(recovered, on: [laptop]))
        #expect(laptop.contains(recovered))
    }

    @Test func aFrameHangingOffAnEdgeIsNudgedFullyOnScreen() {
        // Mostly on-screen but its title bar peeks past the right/top edges far enough
        // that too little remains grabbable.
        let hanging = CGRect(x: 1400, y: 870, width: 800, height: 600)
        let recovered = WindowFrameSolver.onScreenFrame(for: hanging, visibleFrames: [laptop])
        #expect(recovered.size == hanging.size)
        #expect(laptop.contains(recovered))
    }

    @Test func aWindowLargerThanTheScreenIsResizedToFitIt() {
        // A window taller and wider than the only screen cannot fit at its saved size;
        // it is shrunk to the screen so every control ends up reachable — an
        // overhanging window would leave its far-edge controls permanently off-screen
        // (the small-display failure mode seen on CI's 1024x768 virtual display).
        let huge = CGRect(x: 5000, y: 5000, width: 2000, height: 1400)
        let recovered = WindowFrameSolver.onScreenFrame(for: huge, visibleFrames: [laptop])
        #expect(recovered.size == laptop.size)
        #expect(laptop.contains(recovered))
    }

    @Test func aStrandedOversizedWindowShrinksOnlyTheOverflowingAxis() {
        // Only the width exceeds the screen: the height is preserved while the width
        // is brought down to fit, so recovery never shrinks more than it must.
        let wide = CGRect(x: 4000, y: 2000, width: 1600, height: 700)
        let recovered = WindowFrameSolver.onScreenFrame(for: wide, visibleFrames: [laptop])
        #expect(recovered.width == laptop.width)
        #expect(recovered.height == 700)
        #expect(laptop.contains(recovered))
    }

    @Test func withNoVisibleScreensTheFrameIsLeftToTheCallerFallback() {
        // No displays reported: the solver does not invent a frame; the caller owns
        // the "no displays" fallback (e.g. a headless test host).
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(!WindowFrameSolver.isReachable(frame, on: []))
        #expect(WindowFrameSolver.onScreenFrame(for: frame, visibleFrames: []) == frame)
    }

    @Test func aFrameReachableOnAnySecondScreenIsKept() {
        // Two displays side by side; a frame living on the right-hand screen is already
        // reachable and must not be dragged back to the primary.
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let onRight = CGRect(x: 1600, y: 100, width: 800, height: 600)
        #expect(WindowFrameSolver.isReachable(onRight, on: [left, right]))
        #expect(
            WindowFrameSolver.onScreenFrame(for: onRight, visibleFrames: [left, right]) == onRight)
    }

    @Test func recoveryPrefersTheScreenWithTheMostOverlap() {
        // A frame straddling two screens but with too little on either is moved onto
        // the screen it overlaps the most, preserving size.
        let left = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let right = CGRect(x: 1000, y: 0, width: 2000, height: 1400)
        // Sits mostly off the top, overlapping the larger right screen more.
        let straddling = CGRect(x: 900, y: 1350, width: 600, height: 500)
        let recovered = WindowFrameSolver.onScreenFrame(
            for: straddling, visibleFrames: [left, right])
        #expect(recovered.size == straddling.size)
        #expect(right.contains(recovered))
    }

    @Test func aTinyWindowOnlyNeedsToBeFullyVisible() {
        // A window smaller than the minimum visible extent is only required to be
        // fully on screen (it cannot expose more than its own size).
        let tiny = CGRect(x: 1430, y: 0, width: 40, height: 40)
        let recovered = WindowFrameSolver.onScreenFrame(for: tiny, visibleFrames: [laptop])
        #expect(laptop.contains(recovered))
        #expect(recovered.size == tiny.size)
    }
}

// MARK: - Per-window sessions: independence and explicit "make default"

@MainActor
@Suite("Editor session independence")
struct EditorSessionIndependenceTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "EditorSessionTests-\(UUID().uuidString)")!
    }

    @Test func aSessionSeedsTheDefaultStyleFromTheSource() {
        // Opening a window starts from the user's default look: the seeded session
        // reflects the source store's persisted style.
        let defaults = freshDefaults()
        let source = AppSettings(defaults: defaults)
        source.config.theme = .monokai
        source.config.fontName = "Fira Code"
        source.config.padding = 56
        source.exportScale = 3

        let session = AppSettings.makeEditorSession(seededFrom: defaults)
        #expect(session.config.theme.id == "monokai")
        #expect(session.config.fontName == "Fira Code")
        #expect(session.config.padding == 56)
        #expect(session.exportScale == 3)
    }

    @Test func editingASessionDoesNotClobberTheGlobalDefault() {
        // The core CS-053 guarantee: a window's edits never touch the app-wide default
        // store — only its own volatile suite.
        let defaults = freshDefaults()
        let source = AppSettings(defaults: defaults)
        source.config.theme = .oneDark
        source.config.code = ""

        let session = AppSettings.makeEditorSession(seededFrom: defaults)
        session.config.theme = .dracula
        session.config.code = "print('only in this window')"
        session.config.padding = 12

        // Re-reading the source store sees none of the window's edits.
        let reloadedSource = AppSettings(defaults: defaults)
        #expect(reloadedSource.config.theme.id == Theme.oneDark.id)
        #expect(reloadedSource.config.code.isEmpty)
        #expect(reloadedSource.config.padding == SnapshotConfig().padding)
    }

    @Test func twoSessionsAreFullyIndependent() {
        // Two windows opened from the same default each edit their own config without
        // affecting the other (multi-window editing).
        let defaults = freshDefaults()
        _ = AppSettings(defaults: defaults)

        let a = AppSettings.makeEditorSession(seededFrom: defaults)
        let b = AppSettings.makeEditorSession(seededFrom: defaults)
        a.config.theme = .dracula
        a.config.code = "A"
        b.config.theme = .github
        b.config.code = "B"

        #expect(a.config.theme.id == "dracula")
        #expect(b.config.theme.id == "github")
        #expect(a.config.code == "A")
        #expect(b.config.code == "B")
    }

    @Test func makeDefaultExplicitlyPromotesAWindowStyleToTheAppDefault() {
        // "Make default" is the one explicit path from a window's config back into the
        // shared default — and it persists, so a reload sees it.
        let defaults = freshDefaults()
        let appDefault = AppSettings(defaults: defaults)
        appDefault.config.theme = .oneDark
        appDefault.exportScale = 1

        let session = AppSettings.makeEditorSession(seededFrom: defaults)
        session.config.theme = .dracula
        session.config.padding = 64
        session.exportScale = 3

        // Nothing changes until the explicit promotion.
        #expect(appDefault.config.theme.id == Theme.oneDark.id)
        appDefault.makeDefault(from: session)

        #expect(appDefault.config.theme.id == "dracula")
        #expect(appDefault.config.padding == 64)
        #expect(appDefault.exportScale == 3)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.config.theme.id == "dracula")
        #expect(reloaded.config.padding == 64)
        #expect(reloaded.exportScale == 3)
    }

    @Test func discardingAVolatileStoreLeavesTheSourceUntouched() {
        // Closing a window tears down its throwaway suite; the app-wide default store
        // is never affected by the teardown.
        let defaults = freshDefaults()
        let source = AppSettings(defaults: defaults)
        source.config.theme = .monokai

        let session = AppSettings.makeEditorSession(seededFrom: defaults)
        session.config.code = "scratch"
        session.discardVolatileStore()

        let reloadedSource = AppSettings(defaults: defaults)
        #expect(reloadedSource.config.theme.id == "monokai")
    }

    @Test func theSharedInstanceHasNoVolatileStoreToDiscard() {
        // A persistent (non-session) instance never reports a volatile suite, so a
        // stray discard on it is a harmless no-op.
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.volatileSuiteName == nil)
        settings.discardVolatileStore()  // no crash, no effect
        #expect(settings.volatileSuiteName == nil)
    }
}

// MARK: - Secure state restoration stays enabled

@MainActor
@Suite("Secure state restoration")
struct SecureRestorationTests {
    @Test func theAppDelegateOptsIntoSecureRestorableState() {
        // CS-053 requires secure restoration to remain enabled. The delegate's opt-in
        // is asserted directly so a regression that disabled it would fail here.
        let delegate = AppDelegate()
        #expect(delegate.applicationSupportsSecureRestorableState(.shared))
    }
}

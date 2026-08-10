import Foundation
import Testing

@testable import Vitrine

// The style/document surface lives in three hand-kept persistence surfaces —
// `SettingsCodec` (app defaults + editor-session seed), `EditorWindowState` (window
// restoration), and `StyleSnapshot` (named presets) — and nothing forced them to agree:
// `shadowRadius` shipped in the restoration blob but in neither of the other two, so
// "Shadow depth" silently reset to 20 in new windows, after relaunch, and through saved
// presets. `WindowStateTests.archiveCoversEverySeededDocumentKey` guards the restoration
// side; these suites guard the codec and preset sides.

@MainActor
@Suite("Style codec completeness")
struct StyleCodecCompletenessTests {
    private func freshDefaults() -> UserDefaults {
        testDefaults()
    }

    /// A config whose every *persisted* field is non-default, so a key that stops
    /// round-tripping shows up as a mismatch. Conditional keys are exercised on their
    /// written branch (`wrapColumns` non-nil, `annotations` non-empty).
    private func richConfig() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.language = .python
        config.theme = .dracula
        config.fontName = "Fira Code"
        config.fontSize = 18
        config.fontLigatures = true
        config.padding = 48
        config.cornerRadius = 18
        config.shadowRadius = 40
        config.showChrome = false
        config.windowTitle = "Demo window"
        config.showShadow = false
        config.showLineNumbers = true
        config.wrapColumns = 72
        config.highlightedLineRanges = [1...1, 3...5]
        config.focusHighlightedLines = true
        config.diffDecorations = true
        config.annotations = [
            Annotation(
                kind: .counter, start: CGPoint(x: 0.2, y: 0.3), end: CGPoint(x: 0.25, y: 0.35),
                text: "step one", number: 1)
        ]
        config.background = .gradient(.sunset)
        config.metadata = SnapshotMetadata(
            filename: "main.py", title: "Demo", caption: "A caption", showLanguageBadge: true)
        return config
    }

    /// Wholesale round-trip: everything `persistStyle` writes must read back equal, and
    /// everything it deliberately excludes must read back as the default. The exclusions
    /// are spelled out one by one so adding a `SnapshotConfig` field forces a decision
    /// here — persist it or excuse it — instead of silently dropping it.
    @Test func persistedStyleReadsBackWholesale() {
        let defaults = freshDefaults()
        let rich = richConfig()
        SettingsCodec.persistStyle(rich, to: defaults)

        var expected = rich
        // Deliberately unpersisted, each with its reason:
        expected.code = ""  // document text, never style
        expected.redactedLineRanges = []  // secret marks on a specific document (see persistStyle)
        expected.watermark = nil  // Brand Kit owns its own persistence
        expected.foregroundImage = nil  // per-capture beautified image, not a default
        expected.imageFrame = .none  // frame of that image, travels with it
        expected.imageFrameAppearance = .auto
        expected.terminalColumns = nil  // measured from the capture, not a preference

        #expect(SettingsCodec.readConfig(from: defaults) == expected)
    }

    /// Structural guard: every document/style key in the editor-session seed must
    /// actually be written by `persistStyle` (the seed copies these keys into a new
    /// window's suite, so a key nothing writes seeds nothing). Output-preference keys are
    /// excused because other stores persist them.
    @Test func persistStyleWritesEveryStyleKeyInTheSeed() {
        let defaults = freshDefaults()
        SettingsCodec.persistStyle(richConfig(), to: defaults)

        let excused: Set<String> = [
            // Persisted by ExportSettings / the selected-preset store, not by persistStyle.
            SettingsCodec.Keys.exportScale, SettingsCodec.Keys.exportFormat,
            SettingsCodec.Keys.colorProfile, SettingsCodec.Keys.richClipboard,
            SettingsCodec.Keys.textSidecar, SettingsCodec.Keys.selectedPreset,
            // Legacy read-only fallback: `persistBackground` deliberately clears it and
            // writes `backgroundStyle`; it stays in the seed so an old store's value can
            // still seed a window once.
            SettingsCodec.Keys.gradientPreset,
        ]
        let missing = SettingsCodec.Keys.editorSessionSeed
            .filter { !excused.contains($0) && defaults.object(forKey: $0) == nil }
        #expect(
            missing.isEmpty,
            """
            These editor-session seed keys are never written by persistStyle, so a new \
            window cannot inherit them: \(missing.sorted().joined(separator: ", ")). \
            Write them in persistStyle, or excuse them here with the store that owns them.
            """)
    }

    @Test func shadowRadiusRoundTripsAndClampsThroughTheCodec() {
        let defaults = freshDefaults()

        #expect(SettingsCodec.Keys.all.contains(SettingsCodec.Keys.shadowRadius))
        #expect(SettingsCodec.Keys.editorSessionSeed.contains(SettingsCodec.Keys.shadowRadius))

        var config = SnapshotConfig()
        config.shadowRadius = 40
        SettingsCodec.persistStyle(config, to: defaults)
        #expect(SettingsCodec.readConfig(from: defaults).shadowRadius == 40)

        // A hand-edited out-of-range value clamps instead of driving `.shadow(radius:)`
        // into a pathological blur, mirroring the window-restoration read.
        defaults.set(5000.0, forKey: SettingsCodec.Keys.shadowRadius)
        #expect(
            SettingsCodec.readConfig(from: defaults).shadowRadius
                <= SettingsDefaults.shadowRadiusRange.upperBound)
    }

    /// "Reset All Settings" clears by iterating `Keys.all`, so a preference written
    /// outside the codec must still be listed there. The safe-area toggle is written by
    /// the inspector's `@AppStorage` and was missing from the list, surviving every reset.
    @Test func resetListCoversTheSafeAreaGuidesPreference() {
        #expect(SettingsCodec.Keys.all.contains(SafeAreaGuide.storageKey))
    }
}

@Suite("Style preset carries the shadow depth")
struct StyleSnapshotShadowRadiusTests {
    @Test func captureApplyRoundTripsShadowRadius() {
        var config = SnapshotConfig()
        config.shadowRadius = 34

        var target = SnapshotConfig()
        StyleSnapshot(capturing: config).apply(to: &target)
        #expect(target.shadowRadius == 34)
    }

    @Test func aPresetSavedBeforeTheFieldExistedAppliesItsOriginalLook() throws {
        // An older preset file has no `shadowRadius` key. It must decode to the type
        // default — the value every capture rendered with when the preset was saved —
        // not to zero or garbage.
        let legacyJSON = """
            {"themeID":"dracula","fontName":"JetBrains Mono","fontSize":14,
             "fontLigatures":false,"padding":32,"cornerRadius":8,"showChrome":true,
             "showShadow":true,"showLineNumbers":false,
             "background":{"kind":"gradient","preset":"Sunset"}}
            """
        let decoded = try JSONDecoder().decode(
            StyleSnapshot.self, from: Data(legacyJSON.utf8))
        #expect(decoded.shadowRadius == SnapshotConfig.defaultShadowRadius)
        // The fixture's background decodes as written — proof this exercises a real
        // legacy file, not the tolerant-decode fallback (which would yield aurora).
        #expect(decoded.background == .gradient(.sunset))
    }

    @Test func decodeClampsAnOutOfRangeShadowRadius() throws {
        // The rest of the fixture is a *valid* file on purpose: only `shadowRadius`
        // is hostile, so the clamp — not the tolerant whole-field fallback — is what
        // the assertion exercises. The background check proves the fixture decoded as
        // written rather than degrading to the aurora fallback.
        let hostile = """
            {"themeID":"dracula","shadowRadius":9999,
             "background":{"kind":"gradient","preset":"Sunset"}}
            """
        let decoded = try JSONDecoder().decode(StyleSnapshot.self, from: Data(hostile.utf8))
        #expect(decoded.shadowRadius <= SettingsDefaults.shadowRadiusRange.upperBound)
        #expect(decoded.background == .gradient(.sunset))
    }

    @Test func encodeDecodeRoundTripsTheField() throws {
        let snapshot = StyleSnapshot(
            themeID: "dracula", shadowRadius: 28, background: .gradient(.aurora))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(StyleSnapshot.self, from: data)
        #expect(decoded.shadowRadius == 28)
        #expect(decoded == snapshot)
    }
}

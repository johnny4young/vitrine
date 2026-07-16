import Foundation
import ServiceManagement
import Testing

@testable import Vitrine

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineTests-\(UUID().uuidString)")!
}

@Suite("Preferences")
struct PreferencesTests {
    @Test func hotkeyAction() {
        #expect(HotkeyAction.allCases.count == 2)
        #expect(HotkeyAction.quickCapture.id == "quickCapture")
        #expect(!HotkeyAction.openEditor.displayName.isEmpty)
    }

    @Test func exportFormat() {
        #expect(ExportFormat.png.displayName == "PNG")
        #expect(ExportFormat.pdf.displayName == "PDF")
    }
}

@Suite("SnapshotConfig shadow")
struct SnapshotConfigShadowTests {
    @Test func shadowToggleZeroesRadius() {
        var config = SnapshotConfig()
        #expect(config.effectiveShadowRadius == config.shadowRadius)
        config.showShadow = false
        #expect(config.effectiveShadowRadius == 0)
    }
}

@Suite("Capture")
struct CaptureTests {
    @Test func menuTitleIsSingleLineAndTruncated() {
        let long = String(repeating: "x", count: 80)
        let capture = Capture(
            code: "\(long)\nsecond line", languageID: "swift", themeID: "one-dark")
        #expect(!capture.menuTitle.contains("\n"))
        #expect(capture.menuTitle.count <= 40)
        #expect(capture.language == .swift)
        #expect(capture.theme.id == "one-dark")
    }

    @Test func codableRoundTrip() throws {
        let capture = Capture(code: "let x = 1", languageID: "swift", themeID: "dracula")
        let data = try JSONEncoder().encode(capture)
        let decoded = try JSONDecoder().decode(Capture.self, from: data)
        #expect(decoded == capture)
    }

    @Test func applyingReplacesContentAndClearsContentBoundMarks() {
        var base = SnapshotConfig()
        base.padding = 72
        base.code = "old"
        base.language = .python
        base.theme = .oneLight
        base.highlightedLineRanges = [1...2]
        base.annotations = [Annotation(kind: .rectangle, start: .zero, end: CGPoint(x: 1, y: 1))]
        let capture = Capture(code: "let value = 42", languageID: "swift", themeID: "dracula")

        let applied = capture.applying(to: base)

        #expect(applied.code == capture.code)
        #expect(applied.language == .swift)
        #expect(applied.theme == .dracula)
        #expect(applied.padding == 72)
        #expect(applied.highlightedLineRanges.isEmpty)
        #expect(applied.annotations.isEmpty)
    }

    @Test func searchMatchesCodeLanguageAndThemeAcrossTerms() {
        let capture = Capture(
            code: "fn main() { println!(\"hello\"); }",
            languageID: Language.rust.rawValue,
            themeID: Theme.dracula.id)

        #expect(capture.matchesSearch(""))
        #expect(capture.matchesSearch("PRINTLN"))
        #expect(capture.matchesSearch("rust dracula"))
        #expect(!capture.matchesSearch("rust github"))
    }

    @Test func gallerySortsWithinPinnedAndUnpinnedGroups() {
        let oldestPinned = Capture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            code: "pinned rust", languageID: Language.rust.rawValue,
            themeID: Theme.dracula.id, date: Date(timeIntervalSinceReferenceDate: 1),
            isPinned: true)
        let olderPython = Capture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            code: "python", languageID: Language.python.rawValue,
            themeID: Theme.oneDark.id, date: Date(timeIntervalSinceReferenceDate: 2))
        let newerGo = Capture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            code: "go", languageID: Language.go.rawValue,
            themeID: Theme.github.id, date: Date(timeIntervalSinceReferenceDate: 3))
        let newestPinned = Capture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            code: "pinned swift", languageID: Language.swift.rawValue,
            themeID: Theme.oneLight.id, date: Date(timeIntervalSinceReferenceDate: 4),
            isPinned: true)
        let captures = [olderPython, newestPinned, newerGo, oldestPinned]

        #expect(
            RecentsSortOrder.newestFirst.sorted(captures).map(\.id)
                == [newestPinned.id, oldestPinned.id, newerGo.id, olderPython.id])
        #expect(
            RecentsSortOrder.oldestFirst.sorted(captures).map(\.id)
                == [oldestPinned.id, newestPinned.id, olderPython.id, newerGo.id])
        #expect(
            RecentsSortOrder.language.sorted(captures).map(\.id)
                == [oldestPinned.id, newestPinned.id, newerGo.id, olderPython.id])
    }

    /// Captures added in the same instant carry equal dates; ties must fall back to
    /// the input's position following the sort's direction, never a UUID comparison —
    /// a random-UUID tie-break ordered equal-date captures differently from run to
    /// run, the flake that hit CI (testRecentsCanSortOldestFirstWithoutDisplacingPins).
    @Test func equalDatesPreserveInsertionOrderNotUUIDOrder() {
        let sharedDate = Date(timeIntervalSinceReferenceDate: 100)
        // Deliberately give the LATER-inserted capture the LEXICALLY SMALLER UUID, so
        // a regression back to UUID ordering flips the result and fails this test.
        let first = Capture(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!,
            code: "first", languageID: Language.go.rawValue,
            themeID: Theme.github.id, date: sharedDate)
        let second = Capture(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            code: "second", languageID: Language.rust.rawValue,
            themeID: Theme.dracula.id, date: sharedDate)
        let mruOrder = [second, first]  // the store keeps newest additions first

        #expect(
            RecentsSortOrder.newestFirst.sorted(mruOrder).map(\.id) == [second.id, first.id],
            "equal dates must keep the store's MRU order under newest-first")
        #expect(
            RecentsSortOrder.oldestFirst.sorted(mruOrder).map(\.id) == [first.id, second.id],
            "equal dates under oldest-first must put the first-added capture first")
    }

    /// The exact CI scenario that flaked twice: `--demo-recents` seeds Go/Python/Rust
    /// (Go pinned) fast enough that the runner's quantized clock stamps equal dates;
    /// "Oldest First" must still show Go (pin), Python, Rust — the insertion order.
    @Test func oldestFirstWithEqualDatesFollowsInsertionOrder() {
        let defaults = UserDefaults(suiteName: "VitrineRecentsTie-\(UUID().uuidString)")!
        let store = RecentsStore(defaults: defaults)
        let sharedDate = Date(timeIntervalSinceReferenceDate: 700)
        let go = Capture(
            code: "go", languageID: Language.go.rawValue, themeID: Theme.github.id,
            date: sharedDate)
        let python = Capture(
            code: "python", languageID: Language.python.rawValue, themeID: Theme.oneDark.id,
            date: sharedDate)
        let rust = Capture(
            code: "rust", languageID: Language.rust.rawValue, themeID: Theme.dracula.id,
            date: sharedDate)
        store.add(go)
        store.add(python)
        store.add(rust)
        store.updatePinned(id: go.id, isPinned: true)

        #expect(
            RecentsSortOrder.oldestFirst.sorted(store.captures).map(\.id)
                == [go.id, python.id, rust.id])
    }

    /// The exact CI scenario: the demo seed `add`s three captures whose `Date()`s can
    /// land on one coarse clock tick on a hosted runner, then pins the first. With
    /// equal dates the store must still list the LATER-added capture first within the
    /// unpinned group (`add` appends, so insertion recency — not a random UUID — breaks
    /// the tie). This is the unit-level reproduction of the flaky
    /// testRecentsCanSortOldestFirstWithoutDisplacingPins CI failure.
    @Test func equalDateAddsKeepLaterAdditionsFirstInTheStore() {
        let defaults = UserDefaults(suiteName: "VitrineRecentsTie-\(UUID().uuidString)")!
        let store = RecentsStore(defaults: defaults)
        let sharedDate = Date(timeIntervalSinceReferenceDate: 500)
        let go = Capture(
            code: "go", languageID: Language.go.rawValue, themeID: Theme.github.id,
            date: sharedDate)
        let python = Capture(
            code: "python", languageID: Language.python.rawValue, themeID: Theme.oneDark.id,
            date: sharedDate)
        let rust = Capture(
            code: "rust", languageID: Language.rust.rawValue, themeID: Theme.dracula.id,
            date: sharedDate)
        store.add(go)
        store.add(python)
        store.add(rust)
        store.updatePinned(id: go.id, isPinned: true)

        // Pinned Go leads; Rust was added last so it outranks Python on the tie.
        #expect(store.captures.map(\.id) == [go.id, rust.id, python.id])
        // The gallery's default sort preserves the store's order.
        #expect(
            RecentsSortOrder.newestFirst.sorted(store.captures).map(\.id)
                == [go.id, rust.id, python.id])
    }
}

@MainActor
@Suite("AppSettings")
struct AppSettingsTests {
    @Test func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.hotkeyAction = .openEditor
        first.export.format = .pdf
        first.treatURLsAsScreenshot = true
        first.export.scale = 3
        first.config.padding = 48
        first.config.theme = .dracula

        let second = AppSettings(defaults: defaults)
        #expect(second.hotkeyAction == .openEditor)
        #expect(second.export.format == .pdf)
        #expect(second.treatURLsAsScreenshot)
        #expect(second.export.scale == 3)
        #expect(second.config.padding == 48)
        #expect(second.config.theme.id == "dracula")
    }

    @Test func recentLanguagesAreMostRecentFirstAndDeduped() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.noteLanguageUsed(.python)
        settings.noteLanguageUsed(.go)
        settings.noteLanguageUsed(.python)
        #expect(settings.recentLanguages.first == .python)
        #expect(settings.recentLanguages.filter { $0 == .python }.count == 1)
        #expect(settings.orderedLanguages.first == .python)
        #expect(Set(settings.orderedLanguages).count == Language.allCases.count)
    }
}

@MainActor
@Suite("LaunchAtLogin")
struct LaunchAtLoginTests {
    @Test func statusMapping() {
        #expect(LaunchAtLogin.isEnabled(for: .enabled))
        #expect(!LaunchAtLogin.isEnabled(for: .notRegistered))
        #expect(!LaunchAtLogin.isEnabled(for: .requiresApproval))
    }
}

@MainActor
@Suite("Notifier")
struct NotifierTests {
    @Test func outcomeMessages() {
        #expect(Notifier.message(for: .copied) != nil)
        #expect(Notifier.message(for: .empty)?.localizedCaseInsensitiveContains("empty") == true)
        #expect(Notifier.message(for: .url("x"))?.localizedCaseInsensitiveContains("url") == true)
        #expect(Notifier.message(for: .rendered) != nil)
    }
}

@MainActor
@Suite("QuickCapture", .serialized)
struct QuickCaptureTests {
    @Test func emptyClipboardReturnsEmpty() {
        let outcome = QuickCapture.run(
            settings: AppSettings(defaults: freshDefaults()),
            recents: RecentsStore(defaults: freshDefaults()),
            clipboard: { nil })
        #expect(outcome == .empty)
    }

    @Test func codeIsCapturedAndStored() {
        let recents = RecentsStore(defaults: freshDefaults())
        let outcome = QuickCapture.run(
            settings: AppSettings(defaults: freshDefaults()),
            recents: recents,
            clipboard: { "let x = 1" })
        #expect(outcome == .copied)
        #expect(recents.captures.first?.code == "let x = 1")
    }

    @Test func urlBranchesWhenScreenshotEnabled() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.treatURLsAsScreenshot = true
        let recents = RecentsStore(defaults: freshDefaults())
        let outcome = QuickCapture.run(
            settings: settings, recents: recents, clipboard: { "https://example.com" })
        #expect(outcome == .url("https://example.com"))
        #expect(recents.captures.isEmpty)
    }
}

@MainActor
@Suite("Debouncer")
struct DebouncerTests {
    @Test func coalescesRapidCalls() async {
        let debouncer = Debouncer(interval: .milliseconds(40))
        var count = 0
        for _ in 0..<5 { debouncer.schedule { count += 1 } }
        try? await Task.sleep(for: .milliseconds(160))
        #expect(count == 1)
    }
}

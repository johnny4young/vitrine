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

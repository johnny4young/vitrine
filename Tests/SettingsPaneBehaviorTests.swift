import Foundation
import ServiceManagement
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

/// Settings behaviors that sit behind AppKit or system services.
@MainActor
@Suite("Settings pane behavior")
struct SettingsPaneBehaviorTests {
    private struct RegistrationError: Error {}

    @Test func launchAtLoginShowsTheSystemStatusAfterAFailedChange() {
        var status = SMAppService.Status.notRegistered
        let model = LaunchAtLoginModel(
            service: LaunchAtLogin.Service(
                status: { status },
                register: { throw RegistrationError() },
                unregister: { status = .notRegistered }))

        model.setEnabled(true)
        #expect(!model.isOn)

        status = .requiresApproval
        model.refresh()
        #expect(!model.isOn)
        #expect(model.requiresApproval)
    }

    @Test func launchAtLoginTurnsOnWhenRegistrationSucceeds() {
        var status = SMAppService.Status.notRegistered
        let model = LaunchAtLoginModel(
            service: LaunchAtLogin.Service(
                status: { status },
                register: { status = .enabled },
                unregister: { status = .notRegistered }))

        model.setEnabled(true)
        #expect(model.isOn)
        #expect(!model.requiresApproval)
    }

    @Test func styleSlidersUseThePersistedRanges() {
        #expect(StyleSettingsView.cornerRadiusRange == SettingsDefaults.cornerRadiusRange)
        #expect(StyleSettingsView.shadowRadiusRange == SettingsDefaults.shadowRadiusRange)
        #expect(StyleSettingsView.paddingRange == SettingsDefaults.paddingRange)
        #expect(StyleSettingsView.fontSizeRange == SettingsDefaults.fontSizeRange)
    }

    @Test func styleSettingsCanEditEveryPersistedCanvasDefault() throws {
        let source = try String(
            contentsOf: Self.repoFile("Vitrine", "Settings", "StyleSettingsView.swift"),
            encoding: .utf8)
        for identifier in ["corner-radius-slider", "shadow-radius-slider", "window-title-field"] {
            #expect(source.contains("\"\(identifier)\""), "missing \(identifier)")
        }
    }

    @Test func shellIntegrationFollowsTheChosenStartupFile() {
        func shell(_ path: String) -> ShellInit.Shell {
            ShellIntegrationInstaller.shell(for: URL(fileURLWithPath: path), fallback: .zsh)
        }
        #expect(shell("/Users/me/.config/fish/config.fish") == .fish)
        #expect(shell("/Users/me/.bashrc") == .bash)
        #expect(shell("/Users/me/.bash_profile") == .bash)
        #expect(shell("/Users/me/.zprofile") == .zsh)
        #expect(
            ShellIntegrationInstaller.shell(
                for: URL(fileURLWithPath: "/Users/me/custom-init"), fallback: .bash) == .bash)
    }

    @Test func cliInstallReportsAnExistingItemWithoutTheSudoFallback() throws {
        let bin = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-cli-reason-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bin) }
        try Data("a file".utf8).write(to: bin.appendingPathComponent("vitrine"))

        let outcome = CLIToolInstaller.install(
            URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli"),
            into: bin)

        #expect(outcome == .failed(.existingItem))
        #expect(!CLIToolInstaller.FailureReason.existingItem.needsAdministrator)
        #expect(CLIToolInstaller.FailureReason.permission.needsAdministrator)
    }

    @Test func freePlacementStepsStayOnTheCanvas() {
        let nudged = FreeWatermarkDragHandle.nudged(
            CGPoint(x: 0.99, y: 0.5), dx: FreeWatermarkDragHandle.step, dy: 0)
        #expect(nudged.x == 1)
        let left = FreeWatermarkDragHandle.nudged(
            CGPoint(x: 0.5, y: 0.5), dx: -FreeWatermarkDragHandle.step, dy: 0)
        #expect(abs(left.x - 0.48) < 0.0001)
    }

    @Test func helpPresetsTopicPointsToTheLibraryPane() throws {
        let catalog = try Self.catalog()
        let entry = try #require(catalog["help.topic.presets.body"])
        #expect(Self.value(entry, "en")?.contains("Settings ▸ Library") == true)
        #expect(Self.value(entry, "es")?.contains("Ajustes ▸ Biblioteca") == true)
    }

    /// Interpolated messages compile to format keys the literal scan skips.
    @Test func interpolatedSettingsMessagesAreTranslated() throws {
        let catalog = try Self.catalog()
        for key in [
            "This preset file uses a newer format (version %lld) this app can't read.",
            "This theme file uses a newer format (version %lld) this app can't read.",
            "The theme is missing the required \"%@\" color.",
            "The recipe canvas %lldx%lld must use dimensions between 64 and 2048.",
            "The workspace recipe is invalid: %@",
            "This signs Vitrine out of %@ and removes their saved website data. It does not end sessions on those servers.",
        ] {
            let entry = try #require(catalog[key], "missing \(key)")
            #expect(Self.value(entry, "es") != nil, "no es for \(key)")
        }
    }

    /// The app-side copies key the catalog by the domain's English text, so a domain
    /// edit without a catalog update fails here.
    @Test func domainCopyShownInSettingsHasSpanishTranslations() throws {
        let catalog = try Self.catalog()
        var english = ExportFormat.allCases.map(\.summary) + ColorProfile.allCases.map(\.summary)
        english += ExportPreset.all.map(\.summary)
        english += [
            StylePresetDocument.ImportError.notAPresetFile.message,
            StylePresetDocument.ImportError.fileTooLarge.message,
            CustomThemeDocument.ImportError.notAThemeFile.message,
            WorkspaceRecipeFile.ReadError.tooLarge.message,
        ]
        for text in english {
            let entry = try #require(catalog[text], "missing \(text)")
            #expect(Self.value(entry, "es") != nil, "no es for \(text)")
        }
    }

    private static func catalog() throws -> [String: Any] {
        let data = try Data(
            contentsOf: repoFile("Vitrine", "Resources", "Localizable.xcstrings"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: Any])
    }

    private static func value(_ entry: Any, _ language: String) -> String? {
        let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    private static func repoFile(_ components: String...) -> URL {
        components.reduce(
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        ) { $0.appendingPathComponent($1) }
    }
}

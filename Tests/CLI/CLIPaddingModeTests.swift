import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

@Suite("Padding mode flag")
@MainActor
struct CLIPaddingModeTests {
    private func config(_ mode: PaddingMode) -> SnapshotConfig {
        var config = SnapshotConfig(code: "let answer = 42", language: .swift)
        config.paddingMode = mode
        return config
    }

    @Test func theFlagReachesTheConfigAndKeepsItsDefault() throws {
        let flagged = try CLIArguments.parse([
            "render", "in.swift", "--out", "o.png", "--padding-mode", "Balanced",
        ])
        #expect(flagged.makeConfig(code: "x", language: .swift).paddingMode == .balanced)
        let bare = try CLIArguments.parse(["render", "in.swift", "--out", "o.png"])
        #expect(bare.makeConfig(code: "x", language: .swift).paddingMode == .manual)
        #expect(throws: CLIError.invalidValue(flag: "--padding-mode", value: "golden")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "o.png", "--padding-mode", "golden",
            ])
        }
    }

    @Test func theCopiedCommandCarriesBalanceOnlyWhenOn() {
        func line(_ style: SnapshotConfig) -> String {
            let command = CLIReproductionCommand(
                style: style, destinationPresetID: nil, scale: SettingsDefaults.exportScale,
                format: .png, profile: .fallback, watermark: nil)
            guard case .command(let line) = command.outcome() else { return "" }
            return line
        }
        #expect(line(config(.balanced)).contains("--padding-mode balanced"))
        #expect(line(config(.manual)).contains("--padding-mode") == false)
    }

    @Test func balanceIsRefusedWithBlurBoxesThatItWouldMove() throws {
        #expect(throws: CLIError.self) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "o.png", "--padding-mode", "balanced",
                "--blur-box", "0.1,0.1,0.5,0.5",
            ])
        }
        let manual = try CLIArguments.parse([
            "render", "in.swift", "--out", "o.png", "--padding-mode", "manual",
            "--blur-box", "0.1,0.1,0.5,0.5",
        ])
        #expect(manual.makeConfig(code: "x", language: .swift).paddingMode == .manual)
    }

    @Test func aBalancedRecipeKeepsManualUnderBlurBoxes() throws {
        var options = try CLIArguments.parse([
            "render", "in.swift", "--out", "o.png", "--blur-box", "0.1,0.1,0.5,0.5",
        ])
        options.recipe = WorkspaceRecipe(
            name: "Balanced",
            style: StyleSnapshot(
                themeID: Theme.oneDark.id, paddingMode: .balanced, background: .gradient(.aurora)))
        #expect(options.makeConfig(code: "x", language: .swift).paddingMode == .manual)
        options.blurBoxes = []
        #expect(options.makeConfig(code: "x", language: .swift).paddingMode == .balanced)
    }
}

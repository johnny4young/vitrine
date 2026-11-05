import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

@Suite("Terminal palette flag")
@MainActor
struct CLITerminalPaletteTests {
    private func capture(_ palette: TerminalPaletteMode) -> SnapshotConfig {
        var config = SnapshotConfig(code: "", language: .terminal)
        config.terminalPalette = palette
        return config
    }

    @Test func theFlagReachesTheRenderedConfig() throws {
        let options = try CLIArguments.parse([
            "render", "in.log", "--out", "o.png", "--language", "terminal",
            "--terminal-palette", "RAW",
        ])
        #expect(options.makeConfig(code: "x", language: .terminal).terminalPalette == .raw)
    }

    @Test func theFlagSaysWhereItApplies() throws {
        let option = try #require(CLIArgumentSchema.options.first { $0.id == .terminalPalette })
        #expect(option.description.contains("Only affects --language terminal"))
    }

    @Test func aBareRenderKeepsTheDefault() throws {
        let options = try CLIArguments.parse(["render", "in.log", "--out", "o.png"])
        #expect(options.makeConfig(code: "x", language: .terminal).terminalPalette == .theme)
    }

    @Test func anUnknownValueIsRejected() {
        #expect(throws: CLIError.invalidValue(flag: "--terminal-palette", value: "neon")) {
            try CLIArguments.parse([
                "render", "in.log", "--out", "o.png", "--terminal-palette", "neon",
            ])
        }
    }

    @Test func theFreeCaptureCommandEditorHandoffAndImageInputRefuseTheFlag() {
        #expect(throws: CLIError.unknownFlag("--terminal-palette")) {
            try CLIArguments.parse([
                "terminal-capture", "in.log", "--copy", "--terminal-palette", "raw",
            ])
        }
        #expect(throws: CLIError.self) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--terminal-palette", "raw"])
        }
        #expect(throws: CLIError.self) {
            try CLIArguments.parse([
                "render", "--image", "a.png", "--out", "o.png", "--terminal-palette", "raw",
            ])
        }
    }

    @Test func theCopiedCommandReproducesThePaletteOnlyWhereItApplies() {
        func line(_ style: SnapshotConfig) -> String {
            let command = CLIReproductionCommand(
                style: style, destinationPresetID: nil, scale: SettingsDefaults.exportScale,
                format: .png, profile: .fallback, watermark: nil)
            guard case .command(let line) = command.outcome() else { return "" }
            return line
        }
        #expect(line(capture(.raw)).contains("--terminal-palette raw"))
        #expect(line(capture(.theme)).contains("--terminal-palette") == false)

        var swift = capture(.raw)
        swift.language = .swift
        #expect(line(swift).contains("vitrine render"))
        #expect(line(swift).contains("--terminal-palette") == false)
    }
}

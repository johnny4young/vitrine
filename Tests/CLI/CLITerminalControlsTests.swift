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

    @Test func theCursorFlagReachesTheConfigAndKeepsItsDefault() throws {
        let flagged = try CLIArguments.parse([
            "render", "in.log", "--out", "o.png", "--language", "terminal",
            "--terminal-cursor", "BAR",
        ])
        #expect(flagged.makeConfig(code: "x", language: .terminal).terminalCursor == .bar)
        let bare = try CLIArguments.parse(["render", "in.log", "--out", "o.png"])
        #expect(bare.makeConfig(code: "x", language: .terminal).terminalCursor == .hidden)
    }

    @Test func theCursorFlagIsRefusedWhereItCannotApply() {
        #expect(throws: CLIError.invalidValue(flag: "--terminal-cursor", value: "beam")) {
            try CLIArguments.parse([
                "render", "in.log", "--out", "o.png", "--terminal-cursor", "beam",
            ])
        }
        #expect(throws: CLIError.unknownFlag("--terminal-cursor")) {
            try CLIArguments.parse([
                "terminal-capture", "in.log", "--copy", "--terminal-cursor", "bar",
            ])
        }
        #expect(throws: CLIError.self) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--terminal-cursor", "bar"])
        }
        #expect(throws: CLIError.self) {
            try CLIArguments.parse([
                "render", "--image", "a.png", "--out", "o.png", "--terminal-cursor", "bar",
            ])
        }
    }

    @Test func theCropFlagsReachTheConfigAndRefuseWhatTheyCannotMean() throws {
        let flagged = try CLIArguments.parse([
            "render", "in.log", "--out", "o.png", "--terminal-crop-rows", "18-6",
            "--terminal-crop-columns", "4",
        ])
        let crop = flagged.makeConfig(code: "x", language: .terminal).terminalCrop
        #expect(crop == TerminalCrop(rows: 6...18, columns: 4...4))
        let bare = try CLIArguments.parse(["render", "in.log", "--out", "o.png"])
        #expect(bare.makeConfig(code: "x", language: .terminal).terminalCrop.isEmpty)

        for value in ["3,7", "3,4", "0-4", "x", "1-\(TerminalCrop.maximum + 1)"] {
            #expect(throws: CLIError.invalidValue(flag: "--terminal-crop-rows", value: value)) {
                try CLIArguments.parse([
                    "render", "in.log", "--out", "o.png", "--terminal-crop-rows", value,
                ])
            }
        }
        #expect(throws: CLIError.unknownFlag("--terminal-crop-columns")) {
            try CLIArguments.parse([
                "terminal-capture", "in.log", "--copy", "--terminal-crop-columns", "1-4",
            ])
        }
        #expect(throws: CLIError.self) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--terminal-crop-rows", "1-2"])
        }
        #expect(throws: CLIError.self) {
            try CLIArguments.parse([
                "render", "--image", "a.png", "--out", "o.png", "--terminal-crop-rows", "1-2",
            ])
        }
    }

    @Test func aBlurBoxRefusesACropSoItCannotSlideOffWhatItHides() throws {
        for crop in ["--terminal-crop-rows", "--terminal-crop-columns"] {
            let refusal = CLIError.incompatibleOptions(
                "Cannot combine --blur-box with --terminal-crop-rows or --terminal-crop-columns.")
            #expect(throws: refusal) {
                try CLIArguments.parse([
                    "render", "in.log", "--out", "o.png", "--blur-box", "0.1,0.36,0.9,0.46",
                    crop, "3-8",
                ])
            }
        }
        _ = try CLIArguments.parse([
            "render", "in.log", "--out", "o.png", "--blur-box", "0.1,0.36,0.9,0.46",
        ])
    }

    @Test func redactSecretsNumbersTheWholeScreenUnderACrop() throws {
        let token = "gh" + "p_" + String(repeating: "x", count: 36)
        let options = try CLIArguments.parse([
            "render", "in.log", "--out", "o.png", "--terminal-crop-rows", "2-3",
            "--redact-secrets",
        ])
        let config = options.makeConfig(code: "ok\nok\n\(token)", language: .terminal)
        #expect(config.redactedLineRanges == [3...3])
        #expect(config.sidecarText == "ok\n[redacted]")
    }

    @Test func theCopiedCommandCarriesTheCursorOnlyWhereItApplies() {
        func line(_ style: SnapshotConfig) -> String {
            let command = CLIReproductionCommand(
                style: style, destinationPresetID: nil, scale: SettingsDefaults.exportScale,
                format: .png, profile: .fallback, watermark: nil)
            guard case .command(let line) = command.outcome() else { return "" }
            return line
        }
        var bar = capture(.theme)
        bar.terminalCursor = .bar
        #expect(line(bar).contains("--terminal-cursor bar"))
        #expect(line(capture(.theme)).contains("--terminal-cursor") == false)

        bar.language = .swift
        #expect(line(bar).contains("vitrine render"))
        #expect(line(bar).contains("--terminal-cursor") == false)
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

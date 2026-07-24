import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Precedence rules that materialize parsed options into render configuration.
@MainActor
@Suite("CLI configuration")
struct CLIConfigurationTests: CLITestSupport {
    // MARK: - Preset/scale precedence

    @Test func presetSeedsScaleAndFixedSize() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "opengraph",
        ])
        // OpenGraph is a fixed 1200×630 preset at 1×.
        #expect(options.effectiveScale == 1)
        #expect(options.fixedSize == CGSize(width: 1200, height: 630))
    }

    @Test func explicitScaleOverridesPresetScale() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "opengraph", "--scale", "2",
        ])
        // An explicit --scale wins over the preset's recommended scale.
        #expect(options.effectiveScale == 2)
        #expect(options.fixedSize == CGSize(width: 1200, height: 630))
    }

    @Test func customCanvasSizeOverridesPresetDimensionsButNotItsScale() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "opengraph",
            "--canvas-size", "800X450",
        ])

        #expect(options.canvasSize == CGSize(width: 800, height: 450))
        #expect(options.fixedSize == CGSize(width: 800, height: 450))
        #expect(options.effectiveScale == 1)
    }

    @Test func effectiveScaleClampsAnOutOfRangeValueDefensively() throws {
        // `--scale` is range-checked at parse time, but `effectiveScale` also clamps
        // defensively so a value reaching `CLIOptions` by any other route (e.g. a
        // constructed instance) can never drive the renderer out of the 1...3 band.
        var tooHigh = try CLIArguments.parse(["render", "in.swift", "-o", "o.png"])
        tooHigh.scale = 9
        // Above the range clamps to the ceiling.
        #expect(tooHigh.effectiveScale == 3)

        var tooLow = try CLIArguments.parse(["render", "in.swift", "-o", "o.png"])
        tooLow.scale = 0
        // Below the range falls back to the app default, not the floor.
        #expect(tooLow.effectiveScale == CGFloat(SettingsDefaults.exportScale))
    }

    @Test func presetBackgroundIsAppliedButCodeIsNot() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "transparent-slide",
        ])
        let config = options.makeConfig(code: "X", language: .swift)
        // The transparent-slide preset sets a transparent background…
        #expect(config.background == .transparent)
        // …and never touches the source.
        #expect(config.code == "X")
    }

    @Test func builtInStylePresetAppliesPresentationWithoutChangingDestinationSizing() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "opengraph",
            "--style-preset", "builtin.minimal",
        ])
        let config = options.makeConfig(code: "let value = 42", language: .swift)

        #expect(options.stylePresetID == "builtin.minimal")
        #expect(options.resolvedStylePreset?.name == "Minimal Light")
        #expect(options.fixedSize == CGSize(width: 1200, height: 630))
        #expect(config.theme.id == Theme.github.id)
        #expect(config.padding == 32)
        #expect(!config.showShadow)
        #expect(config.background == .solid(RGBAColor(.white)))
        #expect(config.code == "let value = 42")
    }

    @Test func explicitStyleFlagsOverrideBuiltInStylePreset() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--style-preset", "builtin.minimal",
            "--theme", "dracula", "--background", "night", "--shadow", "--padding", "48",
        ])
        let config = options.makeConfig(code: "X", language: .swift)

        #expect(config.theme.id == Theme.dracula.id)
        #expect(config.background == .gradient(.night))
        #expect(config.showShadow)
        #expect(config.padding == 48)
    }

    @Test func transparentFlagOverridesPresetBackground() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "twitter", "--transparent",
        ])
        // --transparent is the last word on the background even over a preset that
        // supplies a gradient.
        let config = options.makeConfig(code: "X", language: .swift)
        #expect(config.background == .transparent)
    }

    @Test func backgroundOverridesPresetBackground() throws {
        let gradient = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "twitter", "--background",
            "carbon",
        ])
        #expect(gradient.background == .gradient(.carbon))
        #expect(gradient.makeConfig(code: "X", language: .swift).background == .gradient(.carbon))

        let solid = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "twitter",
            "--background-color", "#1E293BCC",
        ])
        let expected = try #require(RGBAColor(hex: "#1E293BCC"))
        #expect(solid.background == .solid(expected))
        #expect(solid.makeConfig(code: "X", language: .swift).background == .solid(expected))
    }

    @Test func localBackgroundImageBuildsAnImageBackgroundAfterImport() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "twitter",
            "--background-image", "/tmp/background.png",
        ])
        #expect(options.backgroundImagePath == "/tmp/background.png")

        let reference = ImageReference(fileName: "imported.png")
        let config = options.makeConfig(
            code: "X", language: .swift, backgroundImageReference: reference)
        #expect(config.background == .image(ImageBackground(reference: reference)))
    }

    @Test func localBackgroundImageControlsMapToTheExistingRenderModel() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--background-image", "photo.png",
            "--background-fit", "FIT", "--background-blur", "12.5",
            "--background-dimming", "0.35",
        ])
        #expect(options.backgroundImageFit == .fit)
        #expect(options.backgroundImageBlur == 12.5)
        #expect(options.backgroundImageDimming == 0.35)

        let reference = ImageReference(fileName: "imported.png")
        let config = options.makeConfig(
            code: "X", language: .swift, backgroundImageReference: reference)
        #expect(
            config.background
                == .image(
                    ImageBackground(
                        reference: reference, fit: .fit, blur: 12.5, dimming: 0.35)))
    }

    @Test func localBackgroundImageControlsRejectInvalidOrInertValues() {
        #expect(throws: CLIError.invalidValue(flag: "--background-fit", value: "stretch")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--background-image", "photo.png",
                "--background-fit", "stretch",
            ])
        }
        for value in ["-1", "41", "nan"] {
            #expect(throws: CLIError.invalidValue(flag: "--background-blur", value: value)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--background-image", "photo.png",
                    "--background-blur", value,
                ])
            }
        }
        for value in ["-0.1", "1.1", "infinity"] {
            #expect(throws: CLIError.invalidValue(flag: "--background-dimming", value: value)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--background-image", "photo.png",
                    "--background-dimming", value,
                ])
            }
        }
        for (flag, value) in [
            ("--background-fit", "fit"),
            ("--background-blur", "10"),
            ("--background-dimming", "0.2"),
        ] {
            #expect(
                throws: CLIError.incompatibleOptions("\(flag) requires --background-image.")
            ) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", flag, value,
                ])
            }
        }
    }

    @Test func backgroundModesRejectAmbiguousCombinations() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --background with --background-color.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--background", "night",
                "--background-color", "#000",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --transparent with --background or --background-color.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--transparent", "--background",
                "ocean",
            ])
        }

        for conflictingOption in [
            ["--background", "night"],
            ["--background-color", "#000"],
            ["--background-gradient", "#000,#FFF"],
            ["--transparent"],
        ] {
            #expect(
                throws: CLIError.incompatibleOptions(
                    "Cannot combine --background-image with another background option.")
            ) {
                try CLIArguments.parse(
                    [
                        "render", "in.swift", "-o", "o.png", "--background-image",
                        "photo.png",
                    ] + conflictingOption)
            }
        }
    }

    @Test func themeOverrideIsApplied() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--theme", "dracula",
        ])
        let config = options.makeConfig(code: "X", language: .swift)
        #expect(config.theme.id == "dracula")
    }

}

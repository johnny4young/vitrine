import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Parsing coverage for defaults, flag mapping, aliases, and source modes.
@MainActor
@Suite("CLI argument parsing")
struct CLIArgumentParsingTests: CLITestSupport {
    // MARK: - Argument parsing: defaults match the app

    @Test func bareRenderUsesAppDefaults() throws {
        let options = try CLIArguments.parse(["render", "input.swift", "--out", "out.png"])
        #expect(options.inputPath == "input.swift")
        #expect(options.outputPath == "out.png")
        #expect(options.inputKind == .code)
        // No overrides → the app's own defaults.
        #expect(options.themeID == nil)
        #expect(options.language == nil)
        #expect(options.presetID == nil)
        #expect(options.multiSizePresetIDs.isEmpty)
        #expect(options.stylePresetID == nil)
        #expect(options.canvasSize == nil)
        #expect(options.scale == nil)
        #expect(options.format == .png)
        #expect(options.profile == .sRGB)
        #expect(options.transparent == false)
        #expect(options.background == nil)
        #expect(options.backgroundImagePath == nil)
        #expect(options.backgroundImageFit == nil)
        #expect(options.backgroundImageBlur == nil)
        #expect(options.backgroundImageDimming == nil)
        #expect(options.watermarkText == nil)
        #expect(options.watermarkLogoPath == nil)
        #expect(options.watermarkColor == nil)
        #expect(options.watermarkPosition == nil)
        #expect(options.watermarkFreePosition == nil)
        #expect(options.calloutText == nil)
        #expect(options.calloutPosition == nil)
        #expect(options.calloutColor == nil)
        #expect(options.calloutSize == nil)
        #expect(options.counterNumber == nil)
        #expect(options.counterPosition == nil)
        #expect(options.counterColor == nil)
        #expect(options.counterSize == nil)
        #expect(options.arrows.isEmpty)
        #expect(options.lines.isEmpty)
        #expect(options.rectangles.isEmpty)
        #expect(options.highlighters.isEmpty)
        #expect(options.blurBoxes.isEmpty)
        #expect(options.imageFrame == nil)
        #expect(options.frameAppearance == nil)
        #expect(!options.formatCode)
        #expect(options.jsonOutput == false)
    }

    @Test func defaultConfigMatchesTheAppDefaultConfig() throws {
        let options = try CLIArguments.parse(["render", "input.swift", "--out", "out.png"])
        let config = options.makeConfig(code: "let x = 1", language: .swift)
        // A bare CLI render reproduces SnapshotConfig()'s defaults exactly — same
        // theme, font, padding, background, and chrome the editor starts with.
        let appDefault = SnapshotConfig()
        #expect(config.theme.id == appDefault.theme.id)
        #expect(config.fontName == appDefault.fontName)
        #expect(config.fontLigatures == appDefault.fontLigatures)
        #expect(config.fontSize == appDefault.fontSize)
        #expect(config.padding == appDefault.padding)
        #expect(config.cornerRadius == appDefault.cornerRadius)
        #expect(config.shadowRadius == appDefault.shadowRadius)
        #expect(config.background == appDefault.background)
        #expect(config.showChrome == appDefault.showChrome)
        #expect(config.showShadow == appDefault.showShadow)
        #expect(config.showLineNumbers == appDefault.showLineNumbers)
        #expect(config.highlightedLineRanges == appDefault.highlightedLineRanges)
        #expect(config.redactedLineRanges == appDefault.redactedLineRanges)
        #expect(config.focusHighlightedLines == appDefault.focusHighlightedLines)
        #expect(config.diffDecorations == appDefault.diffDecorations)
        // Only code and language come from the input.
        #expect(config.code == "let x = 1")
        #expect(config.language == .swift)
    }

    @Test func defaultScaleMatchesAppDefault() throws {
        let options = try CLIArguments.parse(["render", "input.swift", "--out", "out.png"])
        #expect(options.effectiveScale == CGFloat(SettingsDefaults.exportScale))
        #expect(options.fixedSize == nil)
    }

    @Test func multiSizeDefaultsToEveryPresetInCanonicalOrder() throws {
        let options = try CLIArguments.parse([
            "multi-size", "input.swift", "--out", "cards",
        ])

        #expect(options.command == .multiSize)
        #expect(options.inputPath == "input.swift")
        #expect(options.outputPath == "cards")
        #expect(options.presetID == nil)
        #expect(options.multiSizePresetIDs == ExportPreset.all.map(\.id))
        #expect(options.format == .png)
    }

    @Test func multiSizePresetSelectionIsValidatedDedupedAndCanonicallyOrdered() throws {
        let options = try CLIArguments.parse([
            "multi-size", "input.swift", "--out", "cards",
            "--presets", "opengraph,twitter,opengraph",
        ])
        #expect(options.multiSizePresetIDs == ["twitter", "opengraph"])

        let all = try CLIArguments.parse([
            "multi-size", "input.swift", "--out", "cards", "--presets", "all",
        ])
        #expect(all.multiSizePresetIDs == ExportPreset.all.map(\.id))

        for raw in ["", "twitter,", "all,twitter", "twitter,unknown"] {
            #expect(throws: CLIError.invalidValue(flag: "--presets", value: raw)) {
                try CLIArguments.parse([
                    "multi-size", "input.swift", "--out", "cards", "--presets", raw,
                ])
            }
        }
    }

    @Test func multiSizeRejectsAmbiguousGeometryAndNonFanoutControls() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine multi-size with --preset; use --presets.")
        ) {
            try CLIArguments.parse([
                "multi-size", "input.swift", "--out", "cards", "--preset", "twitter",
            ])
        }
        for arguments in [
            ["--canvas-size", "800x600"], ["--scale", "2"],
        ] {
            #expect(
                throws: CLIError.incompatibleOptions(
                    "Cannot combine multi-size with --canvas-size or --scale; destination presets pin their dimensions."
                )
            ) {
                try CLIArguments.parse(
                    ["multi-size", "input.swift", "--out", "cards"] + arguments)
            }
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine render with --presets.")
        ) {
            try CLIArguments.parse([
                "render", "input.swift", "--out", "card.png", "--presets", "twitter",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine multi-size with --copy or --edit.")
        ) {
            try CLIArguments.parse([
                "multi-size", "input.swift", "--out", "cards", "--copy",
            ])
        }
    }

    // MARK: - Argument parsing: every option maps to its field

    @Test func parsesEveryOption() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.py",
            "--out", "image.png",
            "--theme", "dracula",
            "--language", "python",
            "--preset", "opengraph",
            "--style-preset", "builtin.midnight",
            "--canvas-size", "800x600",
            "--scale", "3",
            "--font", "Fira Code",
            "--font-ligatures",
            "--font-size", "16",
            "--padding", "48",
            "--corner-radius", "12",
            "--shadow-radius", "24",
            "--terminal-width", "100",
            "--wrap-columns", "88",
            "--format-code",
            "--format", "png",
            "--profile", "p3",
            "--transparent",
            "--watermark", "@jane · vitrine",
            "--watermark-color", "#7DD3FC",
            "--watermark-position", "top-left",
            "--no-overwrite",
            "--window-title", "Release build",
            "--filename", "Sources/App.swift",
            "--title", "Launch checklist",
            "--caption", "Ready for the docs site.",
            "--language-badge",
            "--line-numbers",
            "--no-chrome",
            "--no-shadow",
            "--highlight-lines", "2, 4-6",
            "--redact-lines", "7, 9-10",
            "--redact-secrets",
            "--focus-lines",
            "--diff-bands",
        ])
        #expect(options.inputPath == "snippet.py")
        #expect(options.outputPath == "image.png")
        #expect(options.themeID == "dracula")
        #expect(options.language == .python)
        #expect(options.presetID == "opengraph")
        #expect(options.stylePresetID == "builtin.midnight")
        #expect(options.canvasSize == CGSize(width: 800, height: 600))
        #expect(options.scale == 3)
        #expect(options.fontName == "Fira Code")
        #expect(options.fontLigatures == true)
        #expect(options.fontSize == 16)
        #expect(options.padding == 48)
        #expect(options.cornerRadius == 12)
        #expect(options.shadowRadius == 24)
        #expect(options.terminalColumns == 100)
        #expect(options.wrapColumns == 88)
        #expect(options.formatCode)
        #expect(options.profile == .displayP3)
        #expect(options.transparent)
        #expect(options.watermarkText == "@jane · vitrine")
        #expect(options.watermarkColor == RGBAColor(hex: "#7DD3FC"))
        #expect(options.watermarkPosition == .topLeft)
        #expect(options.noOverwrite)
        #expect(!options.jsonOutput)
        #expect(options.windowTitle == "Release build")
        #expect(options.metadataFilename == "Sources/App.swift")
        #expect(options.metadataTitle == "Launch checklist")
        #expect(options.metadataCaption == "Ready for the docs site.")
        #expect(options.showLanguageBadge)
        #expect(options.showLineNumbers == true)
        #expect(options.showChrome == false)
        #expect(options.showShadow == false)
        #expect(options.highlightedLineRanges == [2...2, 4...6])
        #expect(options.redactedLineRanges == [7...7, 9...10])
        #expect(options.redactSecrets)
        #expect(options.focusHighlightedLines == true)
        #expect(options.diffDecorations == true)
    }

    @Test func terminalWidthDefaultsToNilAndFlowsIntoTheConfig() throws {
        // Absent flag → infer (nil); present → carried onto the rendered SnapshotConfig
        // so the canvas and the text sidecar reconstruct at exactly that width.
        let inferred = try CLIArguments.parse(["render", "out.log", "-o", "o.png"])
        #expect(inferred.terminalColumns == nil)
        #expect(inferred.makeConfig(code: "", language: .terminal).terminalColumns == nil)

        let pinned = try CLIArguments.parse([
            "render", "out.log", "-o", "o.png", "--terminal-width", "120",
        ])
        #expect(pinned.makeConfig(code: "", language: .terminal).terminalColumns == 120)
    }

    @Test func redactSecretsScansTerminalVisibleText() throws {
        let options = try CLIArguments.parse([
            "render", "session.log", "-o", "o.png", "--language", "terminal",
            "--terminal-width", "80", "--redact-secrets",
        ])

        let config = options.makeConfig(
            code: "fetching...\rexport API_KEY=\(String(repeating: "k", count: 20))",
            language: .terminal)

        #expect(options.redactSecrets)
        #expect(config.redactedLineRanges == [1...1])
        #expect(config.sidecarText == SnapshotConfig.redactedLinePlaceholder)
    }

    @Test func wrapColumnsDefaultsToNilAndFlowsIntoTheConfig() throws {
        // Absent flag → size to content; present → use the same soft-wrap setting as
        // the editor's "Wrap long lines" control.
        let unwrapped = try CLIArguments.parse(["render", "snippet.swift", "-o", "o.png"])
        #expect(unwrapped.wrapColumns == nil)
        #expect(unwrapped.makeConfig(code: "", language: .swift).wrapColumns == nil)

        let wrapped = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--wrap-columns", "96",
        ])
        #expect(wrapped.wrapColumns == 96)
        #expect(wrapped.makeConfig(code: "", language: .swift).wrapColumns == 96)
    }

    @Test func formatCodeUsesTheEditorsLocalFormatter() throws {
        let unchanged = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
        ])
        let source = "struct Card {\nlet title = \"Vitrine\"\n}"
        #expect(!unchanged.formatCode)
        #expect(unchanged.makeConfig(code: source, language: .swift).code == source)

        let formatted = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--format-code",
        ])
        #expect(formatted.formatCode)
        #expect(
            formatted.makeConfig(code: source, language: .swift).code
                == "struct Card {\n  let title = \"Vitrine\"\n}")

        let alias = try CLIArguments.parse([
            "render", "snippet.json", "-o", "o.png", "--tidy",
        ])
        #expect(alias.formatCode)
        #expect(
            alias.makeConfig(code: #"{"name":"Vitrine"}"#, language: .json).code
                == "{\n  \"name\": \"Vitrine\"\n}")
    }

    @Test func formatCodeRunsBeforeSecretScanningAndSidecars() throws {
        let token = "sk-" + String(repeating: "a", count: 24)
        let source = "struct Secrets {\nlet token = \"\(token)\"\n}"
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--format-code", "--redact-secrets",
        ])

        let config = options.makeConfig(code: source, language: .swift)
        #expect(config.redactedLineRanges == [2...2])
        #expect(config.code.contains("  let token"))
        #expect(!config.sidecarText.contains(token))
        #expect(config.sidecarText.contains(SnapshotConfig.redactedLinePlaceholder))
    }

    @Test func customBackgroundGradientBuildsEvenStopsAndAnAngle() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
            "--background-gradient", "#FF453A,#FFD60A,#64D2FFCC",
            "--background-angle", "215",
        ])

        let background = try #require(options.background)
        let gradient: CustomGradient
        if case .customGradient(let value) = background {
            gradient = value
        } else {
            Issue.record("expected a custom gradient background")
            return
        }
        #expect(gradient.angle == 215)
        #expect(gradient.stops.map(\.location) == [0, 0.5, 1])
        #expect(
            gradient.stops.map(\.color)
                == ["#FF453A", "#FFD60A", "#64D2FFCC"].compactMap(RGBAColor.init(hex:)))
        #expect(
            options.makeConfig(code: "print(\"ship\")", language: .swift).background
                == background)

        let defaultOptions = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
            "--background-gradient", "#4F46E5,#06B6D4",
        ])
        let defaultBackground = try #require(defaultOptions.background)
        guard case .customGradient(let defaultGradient) = defaultBackground else {
            Issue.record("expected a custom gradient background")
            return
        }
        #expect(defaultGradient.angle == CustomGradient.default.angle)
    }

    @Test func customBackgroundGradientRejectsMalformedOrConflictingOptions() {
        #expect(
            throws: CLIError.invalidValue(
                flag: "--background-gradient", value: "#FF453A")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "-o", "o.png",
                "--background-gradient", "#FF453A",
            ])
        }
        #expect(
            throws: CLIError.invalidValue(
                flag: "--background-gradient", value: "#FF453A,blue")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "-o", "o.png",
                "--background-gradient", "#FF453A,blue",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--background-angle", value: "361")) {
            try CLIArguments.parse([
                "render", "snippet.swift", "-o", "o.png",
                "--background-gradient", "#FF453A,#64D2FF", "--background-angle", "361",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--background-angle requires --background-gradient.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "-o", "o.png", "--background-angle", "90",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --background-gradient with --background or --background-color.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "-o", "o.png",
                "--background", "night", "--background-gradient", "#FF453A,#64D2FF",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --transparent with --background-gradient.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "-o", "o.png",
                "--transparent", "--background-gradient", "#FF453A,#64D2FF",
            ])
        }
    }

    @Test func styleOptionsDefaultToNilAndFlowIntoTheConfig() throws {
        let defaults = try CLIArguments.parse(["render", "snippet.swift", "-o", "o.png"])
        #expect(defaults.fontLigatures == nil)
        #expect(defaults.fontSize == nil)
        #expect(defaults.padding == nil)
        #expect(defaults.cornerRadius == nil)
        #expect(defaults.shadowRadius == nil)
        #expect(defaults.showLineNumbers == nil)
        #expect(defaults.showChrome == nil)
        #expect(defaults.showShadow == nil)
        #expect(defaults.highlightedLineRanges == nil)
        #expect(defaults.redactedLineRanges == nil)
        #expect(defaults.redactSecrets == false)
        #expect(defaults.focusHighlightedLines == nil)
        #expect(defaults.diffDecorations == nil)

        let options = try CLIArguments.parse([
            "render", "snippet.swift",
            "-o", "o.png",
            "--font", "Fira Code",
            "--font-ligatures",
            "--font-size", "15.5",
            "--padding", "40",
            "--corner-radius", "10",
            "--shadow-radius", "18",
            "--line-numbers",
            "--no-chrome",
            "--no-shadow",
            "--highlight-lines", "2, 4-6",
            "--redact-lines", "8-9",
            "--redact-secrets",
            "--focus-lines",
            "--diff-bands",
        ])

        let config = options.makeConfig(
            code: "print(\"styled\")\nlet token = \"sk-\(String(repeating: "a", count: 24))\"",
            language: .swift)
        #expect(config.fontName == "Fira Code")
        #expect(config.fontLigatures)
        #expect(config.fontSize == 15.5)
        #expect(config.padding == 40)
        #expect(config.cornerRadius == 10)
        #expect(config.shadowRadius == 18)
        #expect(config.showLineNumbers)
        #expect(!config.showChrome)
        #expect(!config.showShadow)
        #expect(config.highlightedLineRanges == [2...2, 4...6])
        #expect(config.redactedLineRanges == [2...2, 8...9])
        #expect(config.focusHighlightedLines)
        #expect(config.diffDecorations)

        let ligaturesOff = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--font-ligatures", "--no-font-ligatures",
        ])
        #expect(ligaturesOff.fontLigatures == false)
        #expect(!ligaturesOff.makeConfig(code: "", language: .swift).fontLigatures)

        let lineEmphasisOff = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--focus-lines", "--no-focus-lines",
            "--diff-bands", "--no-diff-bands",
        ])
        let lineEmphasisOffConfig = lineEmphasisOff.makeConfig(code: "", language: .swift)
        #expect(lineEmphasisOff.focusHighlightedLines == false)
        #expect(lineEmphasisOff.diffDecorations == false)
        #expect(!lineEmphasisOffConfig.focusHighlightedLines)
        #expect(!lineEmphasisOffConfig.diffDecorations)
    }

    @Test func metadataHeaderOptionsFlowIntoTheRenderedConfig() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift",
            "--out", "card.png",
            "--window-title", "Release checklist",
            "--filename", "Sources/Release.swift",
            "--title", "Ship the app",
            "--caption", "Every exported image can carry context.",
            "--language-badge",
        ])

        let config = options.makeConfig(code: "print(\"ship\")", language: .swift)
        #expect(config.windowTitle == "Release checklist")
        #expect(config.metadata.filename == "Sources/Release.swift")
        #expect(config.metadata.title == "Ship the app")
        #expect(config.metadata.caption == "Every exported image can carry context.")
        #expect(config.metadata.showLanguageBadge)
    }

    @Test func shortFlagsAndOrderingAreAccepted() throws {
        // `-o` alias, and the input positional after the flags.
        let options = try CLIArguments.parse([
            "render", "-o", "out.png", "--theme", "nord", "input.go",
        ])
        #expect(options.inputPath == "input.go")
        #expect(options.outputPath == "out.png")
        #expect(options.themeID == "nord")
    }

    @Test func formatAndProfileSpellings() throws {
        let pdf = try CLIArguments.parse([
            "render", "a.swift", "-o", "a.pdf", "--format", "pdf",
        ])
        #expect(pdf.format == .pdf)

        let srgb = try CLIArguments.parse([
            "render", "a.swift", "-o", "a.png", "--profile", "srgb",
        ])
        #expect(srgb.profile == .sRGB)
    }

    @Test func profileAcceptsRawEnumNamesAndIsCaseInsensitive() throws {
        // The parser lowercases the value and also accepts the raw enum spellings
        // and ICC names in addition to the documented `srgb`/`p3` short forms.
        func profile(_ raw: String) throws -> ColorProfile {
            try CLIArguments.parse(["render", "a.swift", "-o", "a.png", "--profile", raw])
                .profile
        }
        #expect(try profile("P3") == .displayP3)
        #expect(try profile("displayp3") == .displayP3)
        #expect(try profile("display-p3") == .displayP3)
        #expect(try profile("SRGB") == .sRGB)
        #expect(try profile("srgb-iec61966-2.1") == .sRGB)
    }

    @Test func formatSpellingIsCaseInsensitive() throws {
        // `--format` lowercases its value, so an upper-case spelling still maps.
        let png = try CLIArguments.parse(["render", "a.swift", "-o", "a.png", "--format", "PNG"])
        #expect(png.format == .png)
        let pdf = try CLIArguments.parse(["render", "a.swift", "-o", "a.pdf", "--format", "Pdf"])
        #expect(pdf.format == .pdf)
        let avif = try CLIArguments.parse([
            "render", "a.swift", "-o", "a.avif", "--format", "AVIF",
        ])
        #expect(avif.format == .avif)
    }

    @Test func renderInfersFormatFromKnownOutputExtensions() throws {
        let pdf = try CLIArguments.parse(["render", "a.swift", "-o", "a.pdf"])
        #expect(pdf.format == .pdf)

        let heic = try CLIArguments.parse(["render", "a.swift", "-o", "a.HEIC"])
        #expect(heic.format == .heic)

        let avif = try CLIArguments.parse(["render", "a.swift", "-o", "a.AVIF"])
        #expect(avif.format == .avif)

        let unknown = try CLIArguments.parse(["render", "a.swift", "-o", "a.export"])
        #expect(unknown.format == .png)

        let batchDirectory = try CLIArguments.parse(["batch", "Sources", "-o", "cards.pdf"])
        #expect(batchDirectory.format == .png)
    }

    @Test func renderRejectsExplicitFormatExtensionMismatches() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Output extension .png does not match --format pdf.")
        ) {
            try CLIArguments.parse(["render", "a.swift", "-o", "a.png", "--format", "pdf"])
        }
    }

}

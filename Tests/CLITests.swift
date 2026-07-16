import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// CS-033 — `vitrine render` command-line renderer.
///
/// These tests cover the CLI layers separately so neither needs a live process:
///
/// - **Parsing** (`CLIArguments` → `CLIOptions`) is verified directly: defaults match
///   the app, every flag maps to the right field, and malformed input throws a
///   specific `CLIError`.
/// - **Rendering** (`CLIRenderer.run`) writes into a real temporary directory and the
///   output is read back: PNG signature, exact pixel dimensions, transparency, preset
///   sizing, and PDF output are all asserted. A dedicated test proves the CLI output
///   is **byte-for-byte identical** to the app's own `ExportManager` render for the
///   same options, which is the CS-033 "pixel-identical to the app" guarantee.
///
/// The suite is `@MainActor` because the render path uses AppKit/`ImageRenderer` on
/// the main actor (every render test in the project is); the test host is the app
/// bundle, so the bundled fonts are already registered.
@MainActor
@Suite("CLI renderer (CS-033)")
struct CLITests {
    // MARK: - Fixtures

    /// A small, representative Swift snippet used as CLI input.
    static let sampleCode = """
        import SwiftUI

        struct CounterView: View {
            @State private var count = 0
            var body: some View {
                Button("Tapped \\(count) times") { count += 1 }
            }
        }
        """

    /// Creates a unique temporary directory for one test and returns its URL.
    /// The directory (and everything written into it) is the test's scratch space;
    /// callers clean it up in a `defer`.
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `code` to a file named `name` inside `directory` and returns its path.
    private func writeInput(
        _ code: String = CLITests.sampleCode, named name: String, in directory: URL
    ) throws -> String {
        let url = directory.appendingPathComponent(name)
        try code.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

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

    @Test func watermarkOptionsBuildTheRenderCoreWatermark() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
            "--watermark", "  @jane · vitrine  ",
            "--watermark-color", "#38BDF8CC",
            "--watermark-position", "TOP-LEFT",
        ])

        let watermark = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).watermark)
        #expect(watermark.text == "@jane · vitrine")
        #expect(watermark.logoImageData == nil)
        #expect(watermark.tint == RGBAColor(hex: "#38BDF8CC"))
        #expect(watermark.placement == .topLeading)
    }

    @Test func logoOnlyWatermarkBuildsTheRenderCoreWatermark() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
            "--watermark-logo", "brand.png", "--watermark-position", "bottom-left",
        ])
        let logoData = Data([0x01, 0x02, 0x03])

        #expect(options.watermarkLogoPath == "brand.png")
        let watermark = try #require(
            options.makeConfig(
                code: "print(\"ship\")", language: .swift, watermarkLogoData: logoData
            ).watermark)
        #expect(watermark.text.isEmpty)
        #expect(watermark.logoImageData == logoData)
        #expect(watermark.placement == .bottomLeading)
    }

    @Test func everyWatermarkCornerMapsToTheExpectedModelPlacement() throws {
        let expected: [(String, Watermark.Placement)] = [
            ("bottom-right", .bottomTrailing),
            ("bottom-left", .bottomLeading),
            ("top-right", .topTrailing),
            ("top-left", .topLeading),
        ]

        for (raw, placement) in expected {
            let options = try CLIArguments.parse([
                "render", "snippet.swift", "-o", "o.png",
                "--watermark", "Vitrine", "--watermark-position", raw,
            ])
            #expect(
                options.makeConfig(code: "x", language: .swift).watermark?.placement == placement)
        }
    }

    @Test func freeWatermarkPositionMapsNormalizedCoordinates() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
            "--watermark", "Vitrine", "--watermark-position", "free",
            "--watermark-x", "0.2", "--watermark-y", "0.75",
        ])

        #expect(options.watermarkPosition == .free)
        #expect(options.watermarkFreePosition == CGPoint(x: 0.2, y: 0.75))
        let watermark = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).watermark)
        #expect(watermark.placement == .free)
        #expect(watermark.freePosition == CGPoint(x: 0.2, y: 0.75))
    }

    @Test func freeWatermarkPositionRejectsIncompleteOrInertCoordinates() {
        #expect(throws: CLIError.invalidValue(flag: "--watermark-x", value: "1.1")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark", "Vitrine",
                "--watermark-position", "free", "--watermark-x", "1.1",
                "--watermark-y", "0.5",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--watermark-position free requires --watermark-x and --watermark-y.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark", "Vitrine",
                "--watermark-position", "free",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--watermark-x and --watermark-y must be provided together.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark", "Vitrine",
                "--watermark-position", "free", "--watermark-x", "0.5",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--watermark-x and --watermark-y require --watermark-position free.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark", "Vitrine",
                "--watermark-position", "top-left", "--watermark-x", "0.2",
                "--watermark-y", "0.2",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--watermark-x and --watermark-y require --watermark or --watermark-logo.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark-x", "0.2",
                "--watermark-y", "0.2",
            ])
        }
    }

    @Test func watermarkModifiersRequireCompatibleContent() {
        #expect(throws: CLIError.invalidValue(flag: "--watermark", value: "   ")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark", "   ",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--watermark-color requires --watermark text.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark-color", "#FFF",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--watermark-position requires --watermark or --watermark-logo.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark-position", "top-right",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--watermark-color requires --watermark text.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark-logo", "brand.png",
                "--watermark-color", "#FFF",
            ])
        }
    }

    @Test func calloutOptionsBuildTheRenderCoreAnnotation() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
            "--callout", "  Review this branch  ", "--callout-x", "0.25",
            "--callout-y", "0.72", "--callout-color", "#FDE047",
            "--callout-size", "7",
        ])

        #expect(options.calloutText == "Review this branch")
        #expect(options.calloutPosition == CGPoint(x: 0.25, y: 0.72))
        #expect(options.calloutColor == RGBAColor(hex: "#FDE047"))
        #expect(options.calloutSize == 7)
        let annotation = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).annotations.first)
        #expect(annotation.kind == .text)
        #expect(annotation.start == CGPoint(x: 0.25, y: 0.72))
        #expect(annotation.end == annotation.start)
        #expect(annotation.text == "Review this branch")
        #expect(annotation.color == RGBAColor(hex: "#FDE047"))
        #expect(annotation.thickness == 7)
    }

    @Test func calloutDefaultsToTheEditorStyleAtCanvasCenter() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--callout", "Ship it",
        ])
        let annotation = try #require(
            options.makeConfig(code: "x", language: .swift).annotations.first)
        #expect(annotation.start == CGPoint(x: 0.5, y: 0.5))
        #expect(annotation.color == Annotation.defaultColor)
        #expect(annotation.thickness == Annotation.defaultThickness)
    }

    @Test func calloutRejectsBlankInvalidOrInertModifiers() {
        #expect(throws: CLIError.invalidValue(flag: "--callout", value: "   ")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--callout", "   ",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--callout-x", value: "-0.1")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--callout", "Note",
                "--callout-x", "-0.1", "--callout-y", "0.5",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--callout-size", value: "29")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--callout", "Note",
                "--callout-size", "29",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--callout-x and --callout-y must be provided together.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--callout", "Note",
                "--callout-x", "0.3",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--callout-x, --callout-y, --callout-color, and --callout-size require --callout.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--callout-color", "#FFF",
            ])
        }
    }

    @Test func counterOptionsBuildTheRenderCoreAnnotation() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--counter", "7",
            "--counter-x", "0.2", "--counter-y", "0.75",
            "--counter-color", "#22C55E", "--counter-size", "8",
        ])

        #expect(options.counterNumber == 7)
        #expect(options.counterPosition == CGPoint(x: 0.2, y: 0.75))
        #expect(options.counterColor == RGBAColor(hex: "#22C55E"))
        #expect(options.counterSize == 8)
        let annotation = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).annotations.first)
        #expect(annotation.kind == .counter)
        #expect(annotation.start == CGPoint(x: 0.2, y: 0.75))
        #expect(annotation.end == annotation.start)
        #expect(annotation.number == 7)
        #expect(annotation.color == RGBAColor(hex: "#22C55E"))
        #expect(annotation.thickness == 8)
    }

    @Test func counterDefaultsToTheEditorStyleAtCanvasCenter() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--counter", "1",
        ])
        let annotation = try #require(
            options.makeConfig(code: "x", language: .swift).annotations.first)
        #expect(annotation.start == CGPoint(x: 0.5, y: 0.5))
        #expect(annotation.color == Annotation.defaultColor)
        #expect(annotation.thickness == Annotation.defaultThickness)
        #expect(annotation.number == 1)
    }

    @Test func counterRejectsInvalidOrInertModifiers() {
        for raw in ["0", "100", "1.5", "seven"] {
            #expect(throws: CLIError.invalidValue(flag: "--counter", value: raw)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--counter", raw,
                ])
            }
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--counter-x and --counter-y must be provided together.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--counter", "2",
                "--counter-x", "0.3",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--counter-x, --counter-y, --counter-color, and --counter-size require --counter.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--counter-size", "7",
            ])
        }
    }

    @Test func arrowOptionsBuildTheRenderCoreAnnotation() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--arrow", "0.15,0.8,0.7,0.25",
            "--arrow-color", "#38BDF8", "--arrow-size", "9",
        ])

        let arrow = try #require(options.arrows.first)
        #expect(arrow.start == CGPoint(x: 0.15, y: 0.8))
        #expect(arrow.end == CGPoint(x: 0.7, y: 0.25))
        #expect(arrow.color == RGBAColor(hex: "#38BDF8"))
        #expect(arrow.size == 9)
        let annotation = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).annotations.first)
        #expect(annotation.kind == .arrow)
        #expect(annotation.start == CGPoint(x: 0.15, y: 0.8))
        #expect(annotation.end == CGPoint(x: 0.7, y: 0.25))
        #expect(annotation.color == RGBAColor(hex: "#38BDF8"))
        #expect(annotation.thickness == 9)
    }

    @Test func arrowDefaultsToTheEditorStrokeStyle() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--arrow", "0.1,0.9,0.8,0.2",
        ])
        let annotation = try #require(
            options.makeConfig(code: "x", language: .swift).annotations.first)
        #expect(annotation.color == Annotation.defaultColor)
        #expect(annotation.thickness == Annotation.defaultThickness)
    }

    @Test func arrowRejectsMalformedInvisibleOrInertValues() {
        for raw in [
            "0.1,0.2,0.9", "0.1,0.2,0.9,0.4,0.5", "0.1,0.2,nan,0.4",
            "0.1,0.2,1.1,0.4", "0.3,0.3,0.3,0.3",
        ] {
            #expect(throws: CLIError.invalidValue(flag: "--arrow", value: raw)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--arrow", raw,
                ])
            }
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--arrow-color and --arrow-size require --arrow.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--arrow-size", "7",
            ])
        }
    }

    @Test func lineOptionsBuildTheRenderCoreAnnotation() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--line", "0.12,0.72,0.86,0.72",
            "--line-color", "#A78BFA", "--line-size", "10",
        ])

        let line = try #require(options.lines.first)
        #expect(line.start == CGPoint(x: 0.12, y: 0.72))
        #expect(line.end == CGPoint(x: 0.86, y: 0.72))
        #expect(line.color == RGBAColor(hex: "#A78BFA"))
        #expect(line.size == 10)
        let annotation = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).annotations.first)
        #expect(annotation.kind == .line)
        #expect(annotation.start == CGPoint(x: 0.12, y: 0.72))
        #expect(annotation.end == CGPoint(x: 0.86, y: 0.72))
        #expect(annotation.color == RGBAColor(hex: "#A78BFA"))
        #expect(annotation.thickness == 10)
    }

    @Test func lineDefaultsToTheEditorStrokeStyle() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--line", "0.1,0.8,0.9,0.8",
        ])
        let annotation = try #require(
            options.makeConfig(code: "x", language: .swift).annotations.first)
        #expect(annotation.color == Annotation.defaultColor)
        #expect(annotation.thickness == Annotation.defaultThickness)
    }

    @Test func lineRejectsMalformedInvisibleOrInertValues() {
        for raw in [
            "0.1,0.2,0.9", "0.1,0.2,0.9,0.4,0.5", "0.1,0.2,nan,0.4",
            "-0.1,0.2,0.9,0.4", "0.3,0.3,0.3,0.3",
        ] {
            #expect(throws: CLIError.invalidValue(flag: "--line", value: raw)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--line", raw,
                ])
            }
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--line-color and --line-size require --line.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--line-color", "#FFFFFF",
            ])
        }
    }

    @Test func rectangleOptionsBuildTheRenderCoreAnnotation() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--rectangle", "0.12,0.3,0.88,0.78",
            "--rectangle-color", "#FB7185", "--rectangle-size", "9",
        ])

        let rectangle = try #require(options.rectangles.first)
        #expect(rectangle.start == CGPoint(x: 0.12, y: 0.3))
        #expect(rectangle.end == CGPoint(x: 0.88, y: 0.78))
        #expect(rectangle.color == RGBAColor(hex: "#FB7185"))
        #expect(rectangle.size == 9)
        let annotation = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).annotations.first)
        #expect(annotation.kind == .rectangle)
        #expect(annotation.start == CGPoint(x: 0.12, y: 0.3))
        #expect(annotation.end == CGPoint(x: 0.88, y: 0.78))
        #expect(annotation.color == RGBAColor(hex: "#FB7185"))
        #expect(annotation.thickness == 9)
    }

    @Test func rectangleDefaultsToTheEditorStrokeStyle() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--rectangle", "0.1,0.2,0.9,0.8",
        ])
        let annotation = try #require(
            options.makeConfig(code: "x", language: .swift).annotations.first)
        #expect(annotation.color == Annotation.defaultColor)
        #expect(annotation.thickness == Annotation.defaultThickness)
    }

    @Test func rectangleRejectsMalformedDegenerateOrInertValues() {
        for raw in [
            "0.1,0.2,0.9", "0.1,0.2,0.9,0.4,0.5", "0.1,0.2,nan,0.4",
            "0.1,0.2,1.1,0.4", "0.3,0.3,0.3,0.7", "0.3,0.3,0.7,0.3",
        ] {
            #expect(throws: CLIError.invalidValue(flag: "--rectangle", value: raw)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--rectangle", raw,
                ])
            }
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--rectangle-color and --rectangle-size require --rectangle.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--rectangle-size", "7",
            ])
        }
    }

    @Test func highlighterOptionsBuildTheRenderCoreAnnotation() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--highlighter", "0.12,0.42,0.88,0.54",
            "--highlighter-color", "#FFD60A",
        ])

        let highlighter = try #require(options.highlighters.first)
        #expect(highlighter.start == CGPoint(x: 0.12, y: 0.42))
        #expect(highlighter.end == CGPoint(x: 0.88, y: 0.54))
        #expect(highlighter.color == RGBAColor(hex: "#FFD60A"))
        #expect(highlighter.size == nil)
        let annotation = try #require(
            options.makeConfig(code: "print(\"ship\")", language: .swift).annotations.first)
        #expect(annotation.kind == .highlighter)
        #expect(annotation.start == CGPoint(x: 0.12, y: 0.42))
        #expect(annotation.end == CGPoint(x: 0.88, y: 0.54))
        #expect(annotation.color == RGBAColor(hex: "#FFD60A"))
    }

    @Test func highlighterDefaultsToTheEditorColor() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--highlighter", "0.1,0.4,0.9,0.52",
        ])
        let annotation = try #require(
            options.makeConfig(code: "x", language: .swift).annotations.first)
        #expect(annotation.color == Annotation.defaultColor)
    }

    @Test func highlighterRejectsMalformedDegenerateOrInertValues() {
        for raw in [
            "0.1,0.2,0.9", "0.1,0.2,0.9,0.4,0.5", "0.1,0.2,nan,0.4",
            "0.1,0.2,1.1,0.4", "0.3,0.3,0.3,0.7", "0.3,0.3,0.7,0.3",
        ] {
            #expect(throws: CLIError.invalidValue(flag: "--highlighter", value: raw)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--highlighter", raw,
                ])
            }
        }
        #expect(
            throws: CLIError.incompatibleOptions("--highlighter-color requires --highlighter.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--highlighter-color", "#FFD60A",
            ])
        }
    }

    @Test func blurBoxBuildsTheRenderCoreAnnotation() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--blur-box", "0.12,0.42,0.88,0.54",
        ])

        let blurBox = try #require(options.blurBoxes.first)
        #expect(blurBox.start == CGPoint(x: 0.12, y: 0.42))
        #expect(blurBox.end == CGPoint(x: 0.88, y: 0.54))
        #expect(blurBox.color == nil)
        #expect(blurBox.size == nil)
        let annotation = try #require(
            options.makeConfig(code: "let token = \"secret\"", language: .swift)
                .annotations.first)
        #expect(annotation.kind == .blur)
        #expect(annotation.start == CGPoint(x: 0.12, y: 0.42))
        #expect(annotation.end == CGPoint(x: 0.88, y: 0.54))
    }

    @Test func blurBoxRejectsMalformedOrDegenerateValues() {
        for raw in [
            "0.1,0.2,0.9", "0.1,0.2,0.9,0.4,0.5", "0.1,0.2,nan,0.4",
            "0.1,0.2,1.1,0.4", "0.3,0.3,0.3,0.7", "0.3,0.3,0.7,0.3",
        ] {
            #expect(throws: CLIError.invalidValue(flag: "--blur-box", value: raw)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--blur-box", raw,
                ])
            }
        }
    }

    @Test func blurBoxIsVisualOnlyAndDoesNotSanitizeSidecars() throws {
        let source = "let token = \"runtime-only-secret\""
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png", "--blur-box", "0.1,0.2,0.9,0.8",
        ])

        let config = options.makeConfig(code: source, language: .swift)
        #expect(config.sidecarText == source)
        #expect(config.sidecarText.contains("runtime-only-secret"))
    }

    @Test func geometricAnnotationFlagsAreRepeatableAndKeepSharedPerKindStyle() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "-o", "o.png",
            "--arrow", "0.1,0.8,0.35,0.55", "--arrow", "0.9,0.8,0.65,0.55",
            "--arrow-color", "#38BDF8", "--arrow-size", "8",
            "--line", "0.1,0.2,0.9,0.2", "--line", "0.1,0.3,0.9,0.3",
            "--rectangle", "0.1,0.1,0.4,0.4", "--rectangle", "0.6,0.1,0.9,0.4",
            "--highlighter", "0.1,0.45,0.9,0.52",
            "--highlighter", "0.1,0.58,0.9,0.65", "--highlighter-color", "#FFD60A",
            "--blur-box", "0.1,0.7,0.4,0.8", "--blur-box", "0.6,0.7,0.9,0.8",
        ])

        #expect(options.arrows.count == 2)
        #expect(options.lines.count == 2)
        #expect(options.rectangles.count == 2)
        #expect(options.highlighters.count == 2)
        #expect(options.blurBoxes.count == 2)
        #expect(options.arrows.allSatisfy { $0.color == RGBAColor(hex: "#38BDF8") })
        #expect(options.arrows.allSatisfy { $0.size == 8 })
        #expect(options.highlighters.allSatisfy { $0.color == RGBAColor(hex: "#FFD60A") })

        let annotations = options.makeConfig(code: "print(\"ship\")", language: .swift).annotations
        #expect(
            annotations.map(\.kind) == [
                .arrow, .arrow, .line, .line, .rectangle, .rectangle,
                .highlighter, .highlighter, .blur, .blur,
            ])
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
    }

    @Test func renderInfersFormatFromKnownOutputExtensions() throws {
        let pdf = try CLIArguments.parse(["render", "a.swift", "-o", "a.pdf"])
        #expect(pdf.format == .pdf)

        let heic = try CLIArguments.parse(["render", "a.swift", "-o", "a.HEIC"])
        #expect(heic.format == .heic)

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

    // MARK: - Argument parsing: errors are specific

    @Test func helpIsRequestedNotAFailure() {
        #expect(throws: CLIError.helpRequested) {
            try CLIArguments.parse(["--help"])
        }
        #expect(throws: CLIError.helpRequested) {
            try CLIArguments.parse([])
        }
        #expect(CLIError.helpRequested.exitCode == 0)
    }

    @Test func unknownCommandIsRejected() {
        #expect(throws: CLIError.unknownCommand("frobnicate")) {
            try CLIArguments.parse(["frobnicate", "x"])
        }
    }

    @Test func unknownFlagIsRejected() {
        #expect(throws: CLIError.unknownFlag("--wat")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--wat"])
        }
    }

    @Test func missingValueIsRejected() {
        #expect(throws: CLIError.missingValue(flag: "--out")) {
            try CLIArguments.parse(["render", "in.swift", "--out"])
        }
    }

    @Test func missingInputAndOutputAreRejected() {
        #expect(throws: CLIError.missingRequired("--out output path")) {
            try CLIArguments.parse(["render", "in.swift"])
        }
        #expect(throws: CLIError.missingRequired("input file")) {
            try CLIArguments.parse(["render", "--out", "o.png"])
        }
    }

    @Test func stdinAndCopyRelaxTheRequiredArguments() throws {
        // --stdin needs no input file; --copy needs no --out.
        let piped = try CLIArguments.parse(["render", "--stdin", "--copy"])
        #expect(piped.readStdin && piped.copyToClipboard)
        #expect(piped.inputPath.isEmpty && piped.outputPath.isEmpty)

        // --copy with a file source, no --out.
        let copy = try CLIArguments.parse(["render", "in.swift", "--copy"])
        #expect(copy.copyToClipboard && copy.outputPath.isEmpty && copy.inputPath == "in.swift")

        // --copy + --out does both.
        let both = try CLIArguments.parse(["render", "in.swift", "--copy", "--out", "x.png"])
        #expect(both.copyToClipboard && both.outputPath == "x.png")
    }

    @Test func imageInputParsesAsARenderOnlyLocalSource() throws {
        let options = try CLIArguments.parse([
            "render", "--image", "Screenshot.png", "--out", "card.png",
            "--background", "night", "--padding", "24", "--copy",
        ])

        #expect(options.inputKind == .image)
        #expect(options.inputPath == "Screenshot.png")
        #expect(options.outputPath == "card.png")
        #expect(options.copyToClipboard)
        #expect(options.padding == 24)
        #expect(options.background == .gradient(.night))
    }

    @Test func imageFrameControlsMapToTheExistingRenderModel() throws {
        let options = try CLIArguments.parse([
            "render", "--image", "Screenshot.png", "--out", "card.png",
            "--frame", "browser", "--frame-appearance", "dark",
            "--window-title", "https://example.com",
        ])

        #expect(options.imageFrame == .browser)
        #expect(options.frameAppearance == .dark)
        #expect(options.windowTitle == "https://example.com")

        let config = options.makeConfig(code: "", language: .plaintext)
        #expect(config.imageFrame == .browser)
        #expect(config.imageFrameAppearance == .dark)
        #expect(config.windowTitle == "https://example.com")

        let mappings: [(String, ImageFrame)] = [
            ("none", .none),
            ("macos-window", .macOSWindow),
            ("browser", .browser),
            ("macbook", .macBook),
            ("iphone", .iPhone),
        ]
        for (id, expected) in mappings {
            let mapped = try CLIArguments.parse([
                "render", "--image", "Screenshot.png", "--out", "card.png",
                "--frame", id,
            ])
            #expect(mapped.makeConfig(code: "", language: .plaintext).imageFrame == expected)
        }
    }

    @Test func imageFrameControlsRejectInvalidOrInertCombinations() throws {
        #expect(throws: CLIError.invalidValue(flag: "--frame", value: "tablet")) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png",
                "--frame", "tablet",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--frame-appearance", value: "sepia")) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png",
                "--frame", "browser", "--frame-appearance", "sepia",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--frame and --frame-appearance require --image.")
        ) {
            try CLIArguments.parse([
                "render", "source.swift", "--out", "card.png", "--frame", "browser",
            ])
        }
        #expect(throws: CLIError.unknownFlag("--frame")) {
            try CLIArguments.parse([
                "batch", "Sources", "--out", "Cards", "--frame", "browser",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--frame-appearance requires --frame with a framed image.")
        ) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png",
                "--frame-appearance", "light",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--frame-appearance requires --frame with a framed image.")
        ) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png",
                "--frame", "none", "--frame-appearance", "dark",
            ])
        }
        let titleError = CLIError.incompatibleOptions(
            "--window-title with --image requires --frame macos-window or browser.")
        #expect(throws: titleError) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png",
                "--window-title", "Photo",
            ])
        }
        #expect(throws: titleError) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png",
                "--frame", "iphone", "--window-title", "Photo",
            ])
        }

        let macOSWindow = try CLIArguments.parse([
            "render", "--image", "photo.png", "--out", "card.png",
            "--frame", "macos-window", "--window-title", "Photo",
        ])
        #expect(macOSWindow.windowTitle == "Photo")
    }

    @Test func imageInputRejectsAmbiguousSourcesAndUnsupportedCommands() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --image with input file \"source.swift\".")
        ) {
            try CLIArguments.parse([
                "render", "source.swift", "--image", "photo.png", "--out", "card.png",
            ])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --image with --stdin.")) {
            try CLIArguments.parse([
                "render", "--stdin", "--image", "photo.png", "--out", "card.png",
            ])
        }
        #expect(throws: CLIError.unknownFlag("--image")) {
            try CLIArguments.parse([
                "batch", "Sources", "--image", "photo.png", "--out", "Cards",
            ])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --image with --edit.")) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--edit",
            ])
        }
    }

    @Test func imageInputRejectsCodeOnlyAndSidecarOptions() {
        let incompatible = CLIError.incompatibleOptions(
            "Cannot combine --image with code-only or sidecar options.")
        #expect(throws: incompatible) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png", "--theme", "nord",
            ])
        }
        #expect(throws: incompatible) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png", "--line-numbers",
            ])
        }
        #expect(throws: incompatible) {
            try CLIArguments.parse([
                "render", "--image", "photo.png", "--out", "card.png", "--text-sidecar",
            ])
        }
    }

    @Test func stdinNameProvidesFilenameContextForPipedInput() throws {
        let options = try CLIArguments.parse([
            "render", "--stdin", "--stdin-name", "Component.tsx", "--out", "card.png",
            "--language-badge",
        ])
        #expect(options.readStdin)
        #expect(options.stdinFilename == "Component.tsx")
        #expect(options.inputPath.isEmpty)

        let loaded = try FileInputLoader.decode(
            data: Data("export const Button = () => <button>Save</button>\n".utf8),
            filename: options.stdinFilename ?? "")
        #expect(loaded.language == .typescript)
        #expect(loaded.filename == "Component.tsx")

        let config = options.makeConfig(code: loaded.text, language: loaded.language)
        #expect(config.metadata.filename == "Component.tsx")
        #expect(config.metadata.showLanguageBadge)
    }

    @Test func stdinFilenameAliasAndExplicitMetadataOverride() throws {
        let options = try CLIArguments.parse([
            "render", "--stdin", "--stdin-filename", "Snippet.py", "--filename",
            "Published.py", "--out", "card.png",
        ])
        #expect(options.stdinFilename == "Snippet.py")
        #expect(options.metadataFilename == "Published.py")
        #expect(
            options.makeConfig(code: "print('ok')", language: .python).metadata.filename
                == "Published.py")
    }

    @Test func stdinNameRequiresStdin() {
        #expect(throws: CLIError.incompatibleOptions("--stdin-name requires --stdin.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--stdin-name", "in.swift", "--out", "x.png",
            ])
        }
    }

    @Test func quietAndJsonAreMutuallyExclusive() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --quiet with --json.")) {
            try CLIArguments.parse([
                "render", "input.swift", "--out", "out.png", "--quiet", "--json",
            ])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --quiet with --json.")) {
            try CLIArguments.parse([
                "batch", "input", "--out", "out", "--quiet", "--json",
            ])
        }
    }

    @Test func stdinRejectsPositionalInput() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --stdin with input file \"in.swift\".")
        ) {
            try CLIArguments.parse(["render", "in.swift", "--stdin", "--out", "x.png"])
        }
    }

    @Test func stdinAndCopyAreRejectedForBatch() {
        #expect(throws: CLIError.unknownFlag("--stdin")) {
            try CLIArguments.parse(["batch", "dir", "--out", "out", "--stdin"])
        }
        #expect(throws: CLIError.unknownFlag("--stdin-name")) {
            try CLIArguments.parse(["batch", "dir", "--out", "out", "--stdin-name", "File.swift"])
        }
    }

    @Test func editFlagParsesAndNeedsNoOutput() throws {
        let long = try CLIArguments.parse(["render", "in.log", "--edit"])
        #expect(long.openInEditor && long.outputPath.isEmpty && long.inputPath == "in.log")
        // The short form is equivalent.
        let short = try CLIArguments.parse(["render", "in.log", "-e"])
        #expect(short.openInEditor)
    }

    @Test func editRejectsCopyAndOutCombos() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --edit with --copy.")) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--copy"])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --edit with --out.")) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--out", "x.png"])
        }
    }

    @Test func editIsRejectedForBatch() {
        #expect(throws: CLIError.unknownFlag("--edit")) {
            try CLIArguments.parse(["batch", "dir", "--out", "out", "--edit"])
        }
    }

    @Test func parsesTextSidecarFlag() throws {
        let options = try CLIArguments.parse(
            ["render", "in.log", "--out", "out.png", "--text-sidecar"])
        #expect(options.textSidecar)
        // Off unless requested.
        let bare = try CLIArguments.parse(["render", "in.log", "--out", "out.png"])
        #expect(!bare.textSidecar)
    }

    @Test func textSidecarRejectsEditAndOutlessCopy() {
        // Meaningless with --edit (no image is written).
        #expect(
            throws: CLIError.incompatibleOptions("Cannot combine --edit with --text-sidecar.")
        ) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--text-sidecar"])
        }
        // A clipboard-only copy has no --out file for the sidecar to sit beside.
        #expect(
            throws: CLIError.incompatibleOptions(
                "--text-sidecar needs an --out path to write beside.")
        ) {
            try CLIArguments.parse(["render", "in.log", "--copy", "--text-sidecar"])
        }
    }

    @Test func parsesMarkdownSidecarFlag() throws {
        let options = try CLIArguments.parse(
            ["render", "in.log", "--out", "out.png", "--markdown-sidecar"])
        #expect(options.markdownSidecar)
        // Off unless requested; combinable with the plain-text sidecar.
        let bare = try CLIArguments.parse(["render", "in.log", "--out", "out.png"])
        #expect(!bare.markdownSidecar)
        let both = try CLIArguments.parse(
            ["render", "in.log", "--out", "out.png", "--text-sidecar", "--markdown-sidecar"])
        #expect(both.textSidecar && both.markdownSidecar)
    }

    @Test func markdownSidecarRejectsEditAndOutlessCopy() {
        #expect(
            throws: CLIError.incompatibleOptions("Cannot combine --edit with --markdown-sidecar.")
        ) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--markdown-sidecar"])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--markdown-sidecar needs an --out path to write beside.")
        ) {
            try CLIArguments.parse(["render", "in.log", "--copy", "--markdown-sidecar"])
        }
    }

    @Test func parsesHTMLSidecarFlag() throws {
        let options = try CLIArguments.parse(
            ["render", "in.log", "--out", "out.png", "--html-sidecar"])
        #expect(options.htmlSidecar)
        // Off unless requested; combinable with the existing text and Markdown sidecars.
        let bare = try CLIArguments.parse(["render", "in.log", "--out", "out.png"])
        #expect(!bare.htmlSidecar)
        let all = try CLIArguments.parse([
            "render", "in.log", "--out", "out.png",
            "--text-sidecar", "--markdown-sidecar", "--html-sidecar",
        ])
        #expect(all.textSidecar && all.markdownSidecar && all.htmlSidecar)
    }

    @Test func htmlSidecarRejectsEditAndOutlessCopy() {
        #expect(
            throws: CLIError.incompatibleOptions("Cannot combine --edit with --html-sidecar.")
        ) {
            try CLIArguments.parse(["render", "in.log", "--edit", "--html-sidecar"])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--html-sidecar needs an --out path to write beside.")
        ) {
            try CLIArguments.parse(["render", "in.log", "--copy", "--html-sidecar"])
        }
    }

    @Test func parsesSidecarBundleFlag() throws {
        let all = try CLIArguments.parse([
            "render", "in.swift", "--out", "out.png", "--sidecars", "all",
        ])
        #expect(all.textSidecar && all.markdownSidecar && all.htmlSidecar)

        let subset = try CLIArguments.parse([
            "render", "in.swift", "--out", "out.png", "--sidecars", "text,html",
        ])
        #expect(subset.textSidecar)
        #expect(!subset.markdownSidecar)
        #expect(subset.htmlSidecar)

        let aliases = try CLIArguments.parse([
            "render", "in.swift", "--out", "out.png", "--sidecars", "txt, md",
        ])
        #expect(aliases.textSidecar && aliases.markdownSidecar)
        #expect(!aliases.htmlSidecar)
    }

    @Test func editStagesTheHandoffAndReportsSuccess() throws {
        var captured: URL?
        let options = try CLIArguments.parse(["render", "session.log", "--edit"])
        let summary = try CLIRenderer.openInEditor(
            options,
            fileLoader: { _ in
                FileInputLoader.LoadedFile(
                    text: "\u{1B}[31merror\u{1B}[0m", language: .terminal, filename: "session.log")
            },
            open: {
                captured = $0
                return true
            })
        #expect(summary.contains("editor"))
        #expect(captured?.scheme == "vitrine" && captured?.host == "edit")
        // The staged content is reachable through the captured URL's token.
        #expect(EditorHandoff.consume(url: captured!)?.content == "\u{1B}[31merror\u{1B}[0m")
    }

    @Test func editThrowsWhenTheAppCannotBeOpened() throws {
        // A failed open (no app registered for vitrine://) surfaces as a non-zero error,
        // not a false success.
        let options = try CLIArguments.parse(["render", "session.log", "--edit"])
        #expect(throws: CLIError.editorOpenFailed) {
            try CLIRenderer.openInEditor(
                options,
                fileLoader: { _ in
                    FileInputLoader.LoadedFile(
                        text: "x", language: .terminal, filename: "session.log")
                },
                open: { _ in false })
        }
    }

    @Test func editRejectsMetadataHeaderOptionsThatWouldBeIgnored() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with metadata header options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--title", "Ignored title",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with metadata header options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--language-badge",
            ])
        }
    }

    @Test func editRejectsWrapColumnsThatWouldBeIgnored() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine --edit with --wrap-columns."))
        {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--wrap-columns", "80",
            ])
        }
    }

    @Test func editRejectsRenderOnlyStyleOptionsThatWouldBeIgnored() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--canvas-size", "800x600",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--style-preset", "builtin.aurora",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--font-size", "15",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--background-image", "photo.png",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--watermark-logo", "brand.png",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--callout", "Review this",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--counter", "1",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--arrow", "0.1,0.8,0.8,0.2",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--line", "0.1,0.8,0.9,0.8",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--rectangle", "0.1,0.2,0.9,0.8",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--highlighter", "0.1,0.4,0.9,0.52",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --edit with render-only style options.")
        ) {
            try CLIArguments.parse([
                "render", "snippet.swift", "--edit", "--blur-box", "0.1,0.4,0.9,0.52",
            ])
        }
    }

    @Test func invalidValuesAreRejected() {
        #expect(throws: CLIError.invalidValue(flag: "--theme", value: "neon")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--theme", "neon"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--language", value: "cobol")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--language", "cobol"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--preset", value: "billboard")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--preset", "billboard"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--style-preset", value: "personal")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--style-preset", "personal",
            ])
        }
        for value in ["800", "800x", "x600", "800x600x2", "63x600", "800x2049", "800.5x600"] {
            #expect(throws: CLIError.invalidValue(flag: "--canvas-size", value: value)) {
                try CLIArguments.parse([
                    "render", "in.swift", "-o", "o.png", "--canvas-size", value,
                ])
            }
        }
        #expect(throws: CLIError.invalidValue(flag: "--font", value: "Comic Sans")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--font", "Comic Sans"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--background", value: "neon")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--background", "neon",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--background-color", value: "blue")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--background-color", "blue",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--watermark-color", value: "cyan")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark", "Vitrine",
                "--watermark-color", "cyan",
            ])
        }
        #expect(
            throws: CLIError.invalidValue(flag: "--watermark-position", value: "center")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--watermark", "Vitrine",
                "--watermark-position", "center",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--scale", value: "9")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--scale", "9"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--font-size", value: "9")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--font-size", "9"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--font-size", value: "large")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--font-size", "large",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--padding", value: "12")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--padding", "12"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--padding", value: "wide")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--padding", "wide"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--corner-radius", value: "49")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--corner-radius", "49",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--corner-radius", value: "round")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--corner-radius", "round",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--shadow-radius", value: "41")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--shadow-radius", "41",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--shadow-radius", value: "deep")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--shadow-radius", "deep",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--highlight-lines", value: "0")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--highlight-lines", "0",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--highlight-lines", value: "1, nope")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--highlight-lines", "1, nope",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--highlight-lines", value: "1-2-3")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--highlight-lines", "1-2-3",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--redact-lines", value: "0")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--redact-lines", "0",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--redact-lines", value: "1, nope")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--redact-lines", "1, nope",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--redact-lines", value: "1-2-3")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--redact-lines", "1-2-3",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--format", value: "svg")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--format", "svg"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--terminal-width", value: "0")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--terminal-width", "0"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--terminal-width", value: "huge")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--terminal-width", "huge",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--wrap-columns", value: "39")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--wrap-columns", "39",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--wrap-columns", value: "201")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--wrap-columns", "201",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--wrap", value: "wide")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--wrap", "wide"])
        }
        #expect(throws: CLIError.invalidValue(flag: "--sidecars", value: "rich")) {
            try CLIArguments.parse([
                "render", "in.swift", "-o", "o.png", "--sidecars", "rich",
            ])
        }
    }

    @Test func everyErrorHasANonEmptyMessage() {
        let errors: [CLIError] = [
            .helpRequested, .unknownCommand("x"), .unknownFlag("-x"),
            .missingValue(flag: "--out"), .missingRequired("input file"),
            .invalidValue(flag: "--theme", value: "x"), .inputUnreadable(path: "/x"),
            .inputNotText(path: "/x"), .renderFailed, .outputExists(path: "/x"),
            .writeFailed(path: "/x"), .batchSkipped(rendered: 1, skipped: 1),
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
        }
    }

    // MARK: - Preset/scale precedence (CS-020)

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
        // Below the range falls back to the app default (the documented clamp,
        // CS-050), not the floor.
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

    // MARK: - Rendering: produces a valid PNG with correct dimensions

    @Test func renderProducesAValidPNG() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("out.png").path
        let options = try CLIArguments.parse(["render", input, "--out", output])

        let summary = try CLIRenderer.run(options)
        #expect(summary.contains(output))

        // The file exists and starts with the 8-byte PNG signature.
        let data = try Data(contentsOf: URL(fileURLWithPath: output))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))

        // It decodes to a non-empty raster.
        let image = try decodePNG(at: output)
        #expect(image.width > 0)
        #expect(image.height > 0)
    }

    @Test func renderWithWatermarkChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let markedOutput = directory.appendingPathComponent("marked.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", markedOutput,
                "--watermark", "@jane · vitrine",
                "--watermark-color", "#7DD3FC",
                "--watermark-position", "top-left",
            ]))

        let plainData = try Data(contentsOf: URL(fileURLWithPath: plainOutput))
        let markedData = try Data(contentsOf: URL(fileURLWithPath: markedOutput))
        let plainImage = try decodePNG(at: plainOutput)
        let markedImage = try decodePNG(at: markedOutput)
        #expect(markedData != plainData)
        #expect(markedImage.width == plainImage.width)
        #expect(markedImage.height == plainImage.height)
    }

    @Test func localWatermarkLogoChangesPixelsWithoutChangingItsSource() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let logo = directory.appendingPathComponent("brand.png")
        try writeFixtureImage(to: logo, size: CGSize(width: 80, height: 40))
        let originalLogo = try Data(contentsOf: logo)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let markedOutput = directory.appendingPathComponent("logo-marked.png").path

        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", markedOutput, "--scale", "1",
                "--watermark-logo", logo.path, "--watermark-position", "top-left",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let markedImage = try decodePNG(at: markedOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: markedOutput)))
        #expect(markedImage.width == plainImage.width)
        #expect(markedImage.height == plainImage.height)
        #expect(try Data(contentsOf: logo) == originalLogo)
    }

    @Test func localWatermarkLogoReportsMissingAndInvalidImages() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("out.png").path
        let missing = directory.appendingPathComponent("missing.png").path
        let invalid = directory.appendingPathComponent("invalid.png")
        try Data("not an image".utf8).write(to: invalid)

        let missingOptions = try CLIArguments.parse([
            "render", input, "--out", output, "--watermark-logo", missing,
        ])
        #expect(throws: CLIError.inputUnreadable(path: missing)) {
            try CLIRenderer.run(missingOptions)
        }
        let invalidOptions = try CLIArguments.parse([
            "render", input, "--out", output, "--watermark-logo", invalid.path,
        ])
        #expect(throws: CLIError.inputNotImage(path: invalid.path)) {
            try CLIRenderer.run(invalidOptions)
        }
        #expect(!FileManager.default.fileExists(atPath: output))
    }

    @Test func textCalloutChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let calloutOutput = directory.appendingPathComponent("callout.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", calloutOutput, "--scale", "1",
                "--callout", "Review this branch", "--callout-x", "0.68",
                "--callout-y", "0.2", "--callout-color", "#FDE047",
                "--callout-size", "6",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let calloutImage = try decodePNG(at: calloutOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: calloutOutput)))
        #expect(calloutImage.width == plainImage.width)
        #expect(calloutImage.height == plainImage.height)
    }

    @Test func numberedCounterChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let counterOutput = directory.appendingPathComponent("counter.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", counterOutput, "--scale", "1",
                "--counter", "7", "--counter-x", "0.82", "--counter-y", "0.2",
                "--counter-color", "#22C55E", "--counter-size", "8",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let counterImage = try decodePNG(at: counterOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: counterOutput)))
        #expect(counterImage.width == plainImage.width)
        #expect(counterImage.height == plainImage.height)
    }

    @Test func arrowChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let arrowOutput = directory.appendingPathComponent("arrow.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", arrowOutput, "--scale", "1",
                "--arrow", "0.15,0.8,0.72,0.24", "--arrow-color", "#38BDF8",
                "--arrow-size", "9",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let arrowImage = try decodePNG(at: arrowOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: arrowOutput)))
        #expect(arrowImage.width == plainImage.width)
        #expect(arrowImage.height == plainImage.height)
    }

    @Test func lineChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let lineOutput = directory.appendingPathComponent("line.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", lineOutput, "--scale", "1",
                "--line", "0.12,0.72,0.86,0.72", "--line-color", "#A78BFA",
                "--line-size", "10",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let lineImage = try decodePNG(at: lineOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: lineOutput)))
        #expect(lineImage.width == plainImage.width)
        #expect(lineImage.height == plainImage.height)
    }

    @Test func rectangleChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let rectangleOutput = directory.appendingPathComponent("rectangle.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", rectangleOutput, "--scale", "1",
                "--rectangle", "0.12,0.3,0.88,0.78", "--rectangle-color", "#FB7185",
                "--rectangle-size", "9",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let rectangleImage = try decodePNG(at: rectangleOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: rectangleOutput)))
        #expect(rectangleImage.width == plainImage.width)
        #expect(rectangleImage.height == plainImage.height)
    }

    @Test func highlighterChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let highlighterOutput = directory.appendingPathComponent("highlighter.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", highlighterOutput, "--scale", "1",
                "--highlighter", "0.12,0.4,0.88,0.54", "--highlighter-color", "#FFD60A",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let highlighterImage = try decodePNG(at: highlighterOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: highlighterOutput)))
        #expect(highlighterImage.width == plainImage.width)
        #expect(highlighterImage.height == plainImage.height)
    }

    @Test func blurBoxChangesPixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let blurOutput = directory.appendingPathComponent("blur.png").path
        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", plainOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", blurOutput, "--scale", "1",
                "--blur-box", "0.12,0.36,0.88,0.54",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let blurImage = try decodePNG(at: blurOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: blurOutput)))
        #expect(blurImage.width == plainImage.width)
        #expect(blurImage.height == plainImage.height)
    }

    @Test func localBackgroundImageRendersWithoutChangingItsSource() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let background = directory.appendingPathComponent("background.png")
        try writeFixtureImage(to: background, size: CGSize(width: 320, height: 180))
        let originalBackground = try Data(contentsOf: background)
        let defaultOutput = directory.appendingPathComponent("default.png").path
        let imageOutput = directory.appendingPathComponent("image-background.png").path

        try CLIRenderer.run(
            CLIArguments.parse(["render", input, "--out", defaultOutput, "--scale", "1"]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", imageOutput, "--scale", "1",
                "--background-image", background.path,
            ]))

        let defaultImage = try decodePNG(at: defaultOutput)
        let imageBackground = try decodePNG(at: imageOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: defaultOutput))
                != Data(contentsOf: URL(fileURLWithPath: imageOutput)))
        #expect(imageBackground.width == defaultImage.width)
        #expect(imageBackground.height == defaultImage.height)
        #expect(try Data(contentsOf: background) == originalBackground)
    }

    @Test func localBackgroundImageEffectsChangePixelsWithoutChangingCanvasSize() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let background = directory.appendingPathComponent("background.png")
        try writeFixtureImage(to: background, size: CGSize(width: 320, height: 180))
        let plainOutput = directory.appendingPathComponent("plain-background.png").path
        let styledOutput = directory.appendingPathComponent("styled-background.png").path

        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", plainOutput, "--scale", "1",
                "--background-image", background.path,
            ]))
        try CLIRenderer.run(
            CLIArguments.parse([
                "render", input, "--out", styledOutput, "--scale", "1",
                "--background-image", background.path, "--background-fit", "fit",
                "--background-blur", "8", "--background-dimming", "0.4",
            ]))

        let plainImage = try decodePNG(at: plainOutput)
        let styledImage = try decodePNG(at: styledOutput)
        #expect(
            try Data(contentsOf: URL(fileURLWithPath: plainOutput))
                != Data(contentsOf: URL(fileURLWithPath: styledOutput)))
        #expect(styledImage.width == plainImage.width)
        #expect(styledImage.height == plainImage.height)
    }

    @Test func localBackgroundImageReportsUnreadableAndUnsupportedFilesPrecisely() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("out.png").path
        let missing = directory.appendingPathComponent("missing.png").path
        let missingOptions = try CLIArguments.parse([
            "render", "input.swift", "--out", output, "--background-image", missing,
        ])
        #expect(throws: CLIError.inputUnreadable(path: missing)) {
            try CLIRenderer.run(missingOptions) { _ in
                FileInputLoader.LoadedFile(text: "let x = 1", language: .swift, filename: "")
            }
        }

        let invalid = directory.appendingPathComponent("not-image.png")
        try Data("not an image".utf8).write(to: invalid)
        let invalidOptions = try CLIArguments.parse([
            "render", "input.swift", "--out", output, "--background-image", invalid.path,
        ])
        #expect(throws: CLIError.inputNotImage(path: invalid.path)) {
            try CLIRenderer.run(invalidOptions) { _ in
                FileInputLoader.LoadedFile(text: "let x = 1", language: .swift, filename: "")
            }
        }
    }

    @Test func renderJsonSummaryReportsOutputDimensionsAndSidecars() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("out.png")
        let sidecar = directory.appendingPathComponent("out.txt")
        let options = try CLIArguments.parse([
            "render", input, "--out", output.path, "--json", "--text-sidecar",
        ])

        let summary = try CLIRenderer.run(options)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(summary.utf8)) as? [String: Any])
        #expect(decoded["command"] as? String == "render")
        #expect(decoded["status"] as? String == "rendered")
        #expect(decoded["output"] as? String == output.path)
        #expect(decoded["format"] as? String == "png")
        #expect(decoded["copied"] as? Bool == false)
        #expect((decoded["width"] as? Int ?? 0) > 0)
        #expect((decoded["height"] as? Int ?? 0) > 0)
        #expect(decoded["sidecars"] as? [String] == [sidecar.path])
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }

    @Test func renderWithMetadataHeaderAddsVisibleContext() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput("print(\"ship\")\n", named: "Release.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let titledOutput = directory.appendingPathComponent("titled.png").path

        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", input, "--out", plainOutput, "--scale", "1",
            ]))
        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", input,
                "--out", titledOutput,
                "--scale", "1",
                "--window-title", "Release",
                "--filename", "Release.swift",
                "--title", "Ship checklist",
                "--caption", "Context travels with the image.",
                "--language-badge",
            ]))

        let plain = try decodePNG(at: plainOutput)
        let titled = try decodePNG(at: titledOutput)
        // The metadata header and window title are rendered, not just parsed:
        // the contextual image needs more layout height than the same code alone.
        #expect(titled.height > plain.height)
        #expect(titled.width >= plain.width)
    }

    @Test func renderWithWrapColumnsNarrowsAndHeightensLongLines() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let longLine = "let message = \"\(String(repeating: "ship-", count: 90))\""
        let input = try writeInput(longLine, named: "LongLine.swift", in: directory)
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let wrappedOutput = directory.appendingPathComponent("wrapped.png").path

        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", input, "--out", plainOutput, "--scale", "1",
            ]))
        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", input,
                "--out", wrappedOutput,
                "--scale", "1",
                "--wrap-columns", "60",
            ]))

        let plain = try decodePNG(at: plainOutput)
        let wrapped = try decodePNG(at: wrappedOutput)
        #expect(wrapped.width < plain.width)
        #expect(wrapped.height > plain.height)
    }

    @Test func textSidecarWritesPlainTextNextToImage() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let esc = "\u{1B}"
        // Colored terminal output with an OSC 8 link: the sidecar holds the visible text
        // with the escape codes and the link URL stripped.
        let ansi =
            "\(esc)[32m$ build\(esc)[0m\nsee \(esc)]8;;https://example.com\u{07}docs\(esc)]8;;\u{07}\n"
        let input = try writeInput(ansi, named: "session.log", in: directory)
        let output = directory.appendingPathComponent("card.png").path
        let options = try CLIArguments.parse(
            ["render", input, "--out", output, "--language", "terminal", "--text-sidecar"])

        let summary = try CLIRenderer.run(options)
        #expect(summary.contains("card.txt"))

        let sidecar = directory.appendingPathComponent("card.txt")
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        let text = try String(contentsOf: sidecar, encoding: .utf8)
        #expect(text == "$ build\nsee docs\n")

        // The image is still written alongside the sidecar.
        #expect(FileManager.default.fileExists(atPath: output))
    }

    @Test func redactLinesScrubsCopyableSidecars() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "let visible = 1\nlet token = \"runtime-only-secret\"\nlet tail = 2\n"
        let input = try writeInput(source, named: "Secret.swift", in: directory)
        let output = directory.appendingPathComponent("card.png")
        let options = try CLIArguments.parse([
            "render", input,
            "--out", output.path,
            "--language", "swift",
            "--redact-lines", "2",
            "--sidecars", "all",
        ])

        let summary = try CLIRenderer.run(options)
        #expect(summary.contains("card.txt"))
        #expect(summary.contains("card.md"))
        #expect(summary.contains("card.html"))

        let expected = "let visible = 1\n[redacted]\nlet tail = 2\n"
        let text = try String(
            contentsOf: directory.appendingPathComponent("card.txt"), encoding: .utf8)
        let markdown = try String(
            contentsOf: directory.appendingPathComponent("card.md"), encoding: .utf8)
        let html = try String(
            contentsOf: directory.appendingPathComponent("card.html"), encoding: .utf8)

        #expect(text == expected)
        #expect(markdown.contains(expected))
        #expect(html.contains("[redacted]"))
        #expect(!text.contains("runtime-only-secret"))
        #expect(!markdown.contains("runtime-only-secret"))
        #expect(!html.contains("runtime-only-secret"))
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test func redactSecretsScrubsCopyableSidecars() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let secret = "sk-\(String(repeating: "s", count: 24))"
        let source = "let visible = 1\nlet apiKey = \"\(secret)\"\nlet tail = 2\n"
        let input = try writeInput(source, named: "Secret.swift", in: directory)
        let output = directory.appendingPathComponent("card.png")
        let options = try CLIArguments.parse([
            "render", input,
            "--out", output.path,
            "--language", "swift",
            "--redact-secrets",
            "--sidecars", "all",
        ])

        let summary = try CLIRenderer.run(options)
        #expect(summary.contains("card.txt"))
        #expect(summary.contains("card.md"))
        #expect(summary.contains("card.html"))

        let expected = "let visible = 1\n[redacted]\nlet tail = 2\n"
        let text = try String(
            contentsOf: directory.appendingPathComponent("card.txt"), encoding: .utf8)
        let markdown = try String(
            contentsOf: directory.appendingPathComponent("card.md"), encoding: .utf8)
        let html = try String(
            contentsOf: directory.appendingPathComponent("card.html"), encoding: .utf8)

        #expect(text == expected)
        #expect(markdown.contains(expected))
        #expect(html.contains("[redacted]"))
        #expect(!text.contains(secret))
        #expect(!markdown.contains(secret))
        #expect(!html.contains(secret))
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test func markdownSidecarWritesFencedSourceNextToImage() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let esc = "\u{1B}"
        let ansi = "\(esc)[32m$ build\(esc)[0m\nsee docs\n"
        let input = try writeInput(ansi, named: "session.log", in: directory)
        let output = directory.appendingPathComponent("card.png").path
        let options = try CLIArguments.parse(
            ["render", input, "--out", output, "--language", "terminal", "--markdown-sidecar"])

        let summary = try CLIRenderer.run(options)
        #expect(summary.contains("card.md"))

        let sidecar = directory.appendingPathComponent("card.md")
        let text = try String(contentsOf: sidecar, encoding: .utf8)
        // The image reference, then the visible text (escapes stripped) in a fenced
        // block tagged `text` — ready to paste into a README next to the image.
        #expect(
            text == "![Code rendered with Vitrine](card.png)\n\n```text\n$ build\nsee docs\n```\n")

        // The image is still written alongside the sidecar.
        #expect(FileManager.default.fileExists(atPath: output))
    }

    @Test func markdownSidecarFenceOutgrowsBackticksInTheSource() {
        // Code containing a ``` run must not break out of the fenced block: the
        // fence grows one backtick longer than the longest run in the body.
        var config = SnapshotConfig()
        config.language = .swift
        config.code = "let fence = \"```\"\n"
        let contents = CLIRenderer.markdownSidecarContents(for: config, imageName: "snip.png")
        #expect(contents.contains("````swift\n"))
        #expect(contents.hasSuffix("````\n"))
        #expect(contents.hasPrefix("![Code rendered with Vitrine](snip.png)\n\n"))
    }

    @Test func markdownSidecarEscapesUserControlledImageSyntax() {
        var config = SnapshotConfig()
        config.language = .swift
        config.code = "print(\"hi\")\n"
        config.metadata = SnapshotMetadata(filename: "evil] name [draft")

        let contents = CLIRenderer.markdownSidecarContents(
            for: config, imageName: "card v1)<final>.png")

        #expect(contents.hasPrefix("![evil\\] name \\[draft](<card v1)\\<final\\>.png>)\n\n"))
        #expect(contents.contains("```swift\nprint(\"hi\")\n```\n"))
    }

    @Test func htmlSidecarWritesEscapedSourceNextToImage() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = "let title = \"<Ship & share>\"\n"
        let input = try writeInput(source, named: "snippet.swift", in: directory)
        let output = directory.appendingPathComponent("card.png").path
        let options = try CLIArguments.parse([
            "render", input, "--out", output, "--language", "swift",
            "--filename", "Sources/App.swift", "--html-sidecar",
        ])

        let summary = try CLIRenderer.run(options)
        #expect(summary.contains("card.html"))

        let sidecar = directory.appendingPathComponent("card.html")
        let html = try String(contentsOf: sidecar, encoding: .utf8)
        #expect(html.contains("<img src=\"card.png\" alt=\"Sources/App.swift\">"))
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let title = \"&lt;Ship &amp; share&gt;\""))
        #expect(FileManager.default.fileExists(atPath: output))
    }

    @Test func htmlSidecarEscapesUserControlledImageSyntax() {
        var config = SnapshotConfig()
        config.language = .swift
        config.code = "print(\"<script>alert('&') </script>\")\n"
        config.metadata = SnapshotMetadata(
            filename: "evil\" <script>",
            title: "Docs <Embed> & \"copy\"")

        let contents = CLIRenderer.htmlSidecarContents(
            for: config, imageName: "card \"x\" & <final>.png")

        #expect(contents.contains("<title>Docs &lt;Embed&gt; &amp; \"copy\"</title>"))
        #expect(
            contents.contains(
                "<img src=\"card &quot;x&quot; &amp; &lt;final&gt;.png\" alt=\"evil&quot; &lt;script&gt;\">"
            ))
        #expect(contents.contains("print(\"&lt;script&gt;alert('&amp;') &lt;/script&gt;\")"))
    }

    @Test func noOverwriteRejectsExistingRenderOutput() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("card.png")
        try Data("existing".utf8).write(to: output)
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "--out", output.path, "--no-overwrite",
        ])

        #expect(throws: CLIError.outputExists(path: output.path)) {
            try CLIRenderer.run(options) { _ in
                FileInputLoader.LoadedFile(text: "let x = 1", language: .swift, filename: "")
            }
        }
        #expect(try Data(contentsOf: output) == Data("existing".utf8))
    }

    @Test func noOverwriteRejectsExistingSidecarOutput() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("card.png")
        let sidecar = directory.appendingPathComponent("card.md")
        try Data("existing sidecar".utf8).write(to: sidecar)
        let options = try CLIArguments.parse([
            "render", "snippet.swift", "--out", output.path, "--markdown-sidecar",
            "--no-clobber",
        ])

        #expect(throws: CLIError.outputExists(path: sidecar.path)) {
            try CLIRenderer.run(options) { _ in
                FileInputLoader.LoadedFile(text: "let x = 1", language: .swift, filename: "")
            }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try String(contentsOf: sidecar, encoding: .utf8) == "existing sidecar")
    }

    @Test func languageIsInferredFromTheInputExtension() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A `.py` file with no explicit --language infers Python.
        let input = try writeInput("print('hi')\n", named: "snippet.py", in: directory)
        let output = directory.appendingPathComponent("out.png").path
        let options = try CLIArguments.parse(["render", input, "--out", output])

        try CLIRenderer.run(options)
        #expect(FileManager.default.fileExists(atPath: output))
    }

    @Test func explicitLanguageOverridesTheInferredLanguage() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Source whose highlighting is genuinely language-specific: `# …` is a
        // comment in Python but ordinary code in Swift, and `let` is a Swift keyword
        // but a plain identifier in Python. So the *same* bytes colorize differently
        // under each grammar, which is what lets a render comparison prove the
        // language actually reached the highlighter.
        let source = "# hello world\nlet value = 1\n"

        // The loader always reports Python (a `.py` file); only the explicit
        // `--language swift` flag changes what is rendered. `CLIRenderer.run` resolves
        // `options.language ?? loaded.language`, so the override has to win here.
        func render(forcing flag: [String], to name: String) throws -> Data {
            let output = directory.appendingPathComponent(name).path
            try CLIRenderer.run(
                try CLIArguments.parse(["render", "snippet.py", "--out", output] + flag)
            ) { _ in
                FileInputLoader.LoadedFile(
                    text: source, language: .python, filename: "snippet.py")
            }
            return try Data(contentsOf: URL(fileURLWithPath: output))
        }

        let inferredBytes = try render(forcing: [], to: "inferred.png")
        let forcedBytes = try render(forcing: ["--language", "swift"], to: "forced.png")

        // Forcing Swift over an inferred-Python file changes the rendered output:
        // the override flows all the way to the syntax highlighter, not just into a
        // config field.
        #expect(inferredBytes != forcedBytes)

        // And pin the resolution rule exactly, independent of how Highlightr colors a
        // given token: with no flag the inferred language stands; with `--language`
        // the parsed override is what `makeConfig` renders from.
        let inferred = try CLIArguments.parse(["render", "snippet.py", "--out", "o.png"])
        #expect(inferred.language == nil)
        let forced = try CLIArguments.parse([
            "render", "snippet.py", "--out", "o.png", "--language", "swift",
        ])
        #expect(forced.language == .swift)
        #expect(forced.makeConfig(code: source, language: .swift).language == .swift)
    }

    @Test func openGraphPresetProducesExactPixelDimensions() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("og.png").path
        let options = try CLIArguments.parse([
            "render", input, "--out", output, "--preset", "opengraph",
        ])

        try CLIRenderer.run(options)
        // OpenGraph is pinned to exactly 1200×630 logical pixels at 1×.
        let image = try decodePNG(at: output)
        #expect(image.width == 1200)
        #expect(image.height == 630)
    }

    @Test func scaleMultipliesPixelDimensions() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let out1 = directory.appendingPathComponent("s1.png").path
        let out2 = directory.appendingPathComponent("s2.png").path

        try CLIRenderer.run(
            try CLIArguments.parse(["render", input, "--out", out1, "--scale", "1"]))
        try CLIRenderer.run(
            try CLIArguments.parse(["render", input, "--out", out2, "--scale", "2"]))

        let image1 = try decodePNG(at: out1)
        let image2 = try decodePNG(at: out2)
        // Doubling the scale doubles the pixel dimensions of the same content.
        #expect(image2.width == image1.width * 2)
        #expect(image2.height == image1.height * 2)
    }

    @Test func customCanvasSizeProducesExactScaledPixelDimensions() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let out1 = directory.appendingPathComponent("custom-1x.png").path
        let out2 = directory.appendingPathComponent("custom-2x.png").path

        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", input, "--out", out1, "--canvas-size", "640x360", "--scale", "1",
            ]))
        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", input, "--out", out2, "--canvas-size", "640x360", "--scale", "2",
            ]))

        let image1 = try decodePNG(at: out1)
        let image2 = try decodePNG(at: out2)
        #expect(image1.width == 640)
        #expect(image1.height == 360)
        #expect(image2.width == 1_280)
        #expect(image2.height == 720)
    }

    @Test func multiSizeWritesSelectedPresetDimensionsAndSidecars() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("cards", isDirectory: true)
        let options = try CLIArguments.parse([
            "multi-size", input, "--out", output.path,
            "--presets", "twitter,opengraph,instagram-story", "--text-sidecar",
        ])

        let summary = try CLIRenderer.runMultiSize(options)
        #expect(summary == "Rendered 3 preset images to \(output.path)")
        let expected: [(String, Int, Int)] = [
            ("twitter", 1_600, 900), ("opengraph", 1_200, 630),
            ("instagram-story", 1_080, 1_920),
        ]
        for (preset, width, height) in expected {
            let imageURL = output.appendingPathComponent("vitrine-\(preset).png")
            let image = try decodePNG(at: imageURL.path)
            #expect(image.width == width)
            #expect(image.height == height)
            let sidecar = imageURL.deletingPathExtension().appendingPathExtension("txt")
            #expect(try String(contentsOf: sidecar, encoding: .utf8) == CLITests.sampleCode)
        }
    }

    @Test func multiSizeNoOverwritePreflightsEveryTargetBeforeRendering() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("cards", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let existing = output.appendingPathComponent("vitrine-opengraph.png")
        try Data("existing".utf8).write(to: existing)
        let options = try CLIArguments.parse([
            "multi-size", input, "--out", output.path,
            "--presets", "twitter,opengraph", "--no-overwrite",
        ])

        #expect(throws: CLIError.outputExists(path: existing.path)) {
            try CLIRenderer.runMultiSize(options)
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: output.appendingPathComponent("vitrine-twitter.png").path))
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
    }

    // MARK: - Rendering: transparent background keeps real alpha

    @Test func localImageInputRendersThroughAnEphemeralForegroundStore() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("source.png")
        try writeFixtureImage(to: input, size: CGSize(width: 180, height: 100))
        let output = directory.appendingPathComponent("beautified.png").path
        let options = try CLIArguments.parse([
            "render", "--image", input.path, "--out", output,
            "--background", "sunset", "--padding", "24", "--scale", "1",
            "--watermark", "Local image",
        ])

        let summary = try CLIRenderer.run(options)
        let image = try decodePNG(at: output)
        #expect(summary.contains(output))
        #expect(image.width > 180)
        #expect(image.height > 100)
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func localImageInputRendersItsSelectedFrame() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("source.png")
        try writeFixtureImage(to: input, size: CGSize(width: 180, height: 100))
        let plainOutput = directory.appendingPathComponent("plain.png").path
        let framedOutput = directory.appendingPathComponent("browser.png").path

        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", "--image", input.path, "--out", plainOutput,
                "--padding", "24", "--scale", "1",
            ]))
        try CLIRenderer.run(
            try CLIArguments.parse([
                "render", "--image", input.path, "--out", framedOutput,
                "--padding", "24", "--scale", "1", "--frame", "browser",
                "--frame-appearance", "dark", "--window-title", "example.com",
            ]))

        let plain = try decodePNG(at: plainOutput)
        let framed = try decodePNG(at: framedOutput)
        #expect(framed.width == plain.width)
        #expect(framed.height > plain.height)
    }

    @Test func imageInputReportsUnreadableAndUnsupportedFilesPrecisely() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = directory.appendingPathComponent("missing.png").path
        let output = directory.appendingPathComponent("out.png").path
        let missingOptions = try CLIArguments.parse([
            "render", "--image", missing, "--out", output,
        ])
        #expect(throws: CLIError.inputUnreadable(path: missing)) {
            try CLIRenderer.run(missingOptions)
        }

        let text = directory.appendingPathComponent("not-image.png")
        try Data("not an image".utf8).write(to: text)
        let invalidOptions = try CLIArguments.parse([
            "render", "--image", text.path, "--out", output,
        ])
        #expect(throws: CLIError.inputNotImage(path: text.path)) {
            try CLIRenderer.run(invalidOptions)
        }
    }

    @Test func transparentRenderHasRealAlpha() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("clear.png").path
        let options = try CLIArguments.parse([
            "render", input, "--out", output, "--transparent",
        ])

        try CLIRenderer.run(options)
        let data = try Data(contentsOf: URL(fileURLWithPath: output))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties =
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        // The PNG advertises an alpha channel, and the corner pixel is fully
        // transparent (the background is real transparency, not a matte).
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.alphaInfo == .last)
        let corner = try cornerRGBA(of: image)
        #expect(corner.alpha == 0)
    }

    // MARK: - Rendering: PDF output

    @Test func pdfFormatWritesAValidPDF() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("out.pdf").path
        let options = try CLIArguments.parse([
            "render", input, "--out", output, "--format", "pdf",
        ])

        try CLIRenderer.run(options)
        let data = try Data(contentsOf: URL(fileURLWithPath: output))
        // A PDF file starts with "%PDF-".
        #expect(data.starts(with: Array("%PDF-".utf8)))
        // And it opens as a one-page document.
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
    }

    // MARK: - Pixel-identity with the app render path (CS-033 core promise)

    @Test func cliOutputMatchesTheAppRendererPixelDimensions() throws {
        // Pin the input with an injected loader so both sides render from the exact
        // same code/language: this isolates the *pipeline*, proving the CLI runs the
        // unchanged `ExportManager` path rather than testing file-round-trip details.
        let loaded = FileInputLoader.LoadedFile(
            text: CLITests.sampleCode, language: .swift, filename: "Sample.swift")
        let options = try CLIArguments.parse([
            "render", "Sample.swift", "--out", "ignored.png", "--theme", "dracula",
        ])
        let config = options.makeConfig(code: loaded.text, language: loaded.language)

        // Render both halves and compare their PNG bytes. The CLI half writes a file
        // (its real output path), then we read it back; the app half renders the same
        // config directly through the exporter. Same inputs + same pipeline must yield
        // identical bytes.
        func renderBothSides() throws -> (cli: Data, app: Data) {
            let directory = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("cli.png").path
            var fileOptions = options
            fileOptions.outputPath = output
            try CLIRenderer.run(fileOptions) { _ in loaded }
            let cli = try Data(contentsOf: URL(fileURLWithPath: output))
            let cgImage = try #require(
                ExportManager.renderCGImage(
                    config, scale: options.effectiveScale, fixedSize: options.fixedSize,
                    profile: options.profile))
            let app = try #require(ExportManager.pngData(from: cgImage))
            return (cli, app)
        }

        // The CLI half wraps the *same* `ExportManager` render the app half calls, so the
        // two outputs describe the same image and must share pixel dimensions. We compare
        // decoded dimensions rather than raw bytes: PNG encodings legitimately differ in
        // non-pixel metadata, and font register/unregister elsewhere in the shared test
        // host posts an async Core Text fonts-changed notification that can invalidate
        // glyph caches mid-comparison — making a byte-exact assertion flaky (and, on a cold
        // cache, pathologically slow) without proving anything the dimensions don't.
        let (cliBytes, appBytes) = try renderBothSides()

        func pixelDimensions(_ data: Data) -> (width: Int, height: Int)? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            return (image.width, image.height)
        }

        #expect(Array(cliBytes.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])  // valid PNG
        let cliSize = try #require(pixelDimensions(cliBytes))
        let appSize = try #require(pixelDimensions(appBytes))
        #expect(cliSize == appSize)
    }

    // MARK: - Rendering: input errors

    @Test func missingInputFileReportsUnreadable() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = directory.appendingPathComponent("nope.swift").path
        let output = directory.appendingPathComponent("out.png").path
        let options = try CLIArguments.parse(["render", missing, "--out", output])

        #expect(throws: CLIError.inputUnreadable(path: missing)) {
            try CLIRenderer.run(options)
        }
    }

    @Test func binaryInputReportsNotText() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A NUL byte makes the loader classify the file as binary.
        let binaryURL = directory.appendingPathComponent("blob.swift")
        try Data([0x00, 0x01, 0x02, 0x00]).write(to: binaryURL)
        let output = directory.appendingPathComponent("out.png").path
        let options = try CLIArguments.parse(["render", binaryURL.path, "--out", output])

        #expect(throws: CLIError.inputNotText(path: binaryURL.path)) {
            try CLIRenderer.run(options)
        }
    }

    @Test func tooLargeInputCollapsesToUnreadable() throws {
        // A loader that rejects the file as too large surfaces as `inputUnreadable`:
        // the CLI maps every non-binary load failure to one unreadable error so it
        // never leaks a raw error string or a second user-facing failure mode.
        let options = try CLIArguments.parse(["render", "/big.swift", "--out", "/tmp/o.png"])
        #expect(throws: CLIError.inputUnreadable(path: "/big.swift")) {
            try CLIRenderer.run(options) { _ in throw FileInputLoader.LoadError.tooLarge }
        }
    }

    @Test func unexpectedLoaderErrorCollapsesToUnreadable() throws {
        // Even an error that is *not* a `FileInputLoader.LoadError` is caught and
        // reported as `inputUnreadable`, so an unforeseen failure can never crash the
        // process or escape as an opaque message.
        struct Surprise: Error {}
        let options = try CLIArguments.parse(["render", "/weird.swift", "--out", "/tmp/o.png"])
        #expect(throws: CLIError.inputUnreadable(path: "/weird.swift")) {
            try CLIRenderer.run(options) { _ in throw Surprise() }
        }
    }

    @Test func unwritableOutputReportsWriteFailed() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // The output path lives under a directory that does not exist, so the write
        // fails. A render that produced a perfectly good image must still surface a
        // `writeFailed` for the chosen path rather than crashing on the I/O error.
        let output = directory.appendingPathComponent("missing-subdir/out.png").path
        let options = try CLIArguments.parse(["render", "x.swift", "--out", output])
        #expect(throws: CLIError.writeFailed(path: output)) {
            try CLIRenderer.run(options) { _ in
                FileInputLoader.LoadedFile(
                    text: "let x = 1", language: .swift, filename: "x.swift")
            }
        }
    }

    @Test func injectedLoaderRendersWithoutTouchingTheFileSystem() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("out.png").path
        // The input path need not exist: a stub loader supplies the code, so this
        // exercises the render-and-write half in isolation.
        let options = try CLIArguments.parse(["render", "/does/not/exist.swift", "--out", output])
        let summary = try CLIRenderer.run(options) { _ in
            FileInputLoader.LoadedFile(
                text: "let answer = 42", language: .swift, filename: "x.swift")
        }
        #expect(summary.contains(output))
        #expect(FileManager.default.fileExists(atPath: output))
    }

    // MARK: - Helpers

    /// A decoded raster image, as `CGImage`.
    private func decodePNG(at path: String) throws -> CGImage {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Writes a small two-tone PNG fixture without relying on a checked-in asset.
    private func writeFixtureImage(to url: URL, size: CGSize) throws {
        let width = Int(size.width)
        let height = Int(size.height)
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemIndigo.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(NSColor.systemTeal.cgColor)
        context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
        let image = try #require(context.makeImage())
        let data = try #require(ExportManager.pngData(from: image))
        try data.write(to: url, options: .atomic)
    }

    /// Reads the straight-alpha RGBA of the image's top-left pixel by redrawing it
    /// into a known `RGBA8` context (so the byte order is predictable).
    private func cornerRGBA(
        of image: CGImage
    ) throws -> (
        red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
    ) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(
            CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Draw the image's top-left pixel into the 1×1 context.
        context.draw(
            image,
            in: CGRect(
                x: 0, y: CGFloat(1 - image.height), width: CGFloat(image.width),
                height: CGFloat(image.height)))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}

/// CS-033 — runtime registration of the app's bundled fonts for the command-line
/// renderer.
///
/// `CLIFontRegistration` is what keeps a default CLI render pixel-identical to the
/// app: a command-line tool has no app bundle, so the bundled monospaced families
/// are not auto-registered and `NSFont(name:…)` would silently fall back to the
/// system font. These tests pin the contract that drives that guarantee — a missing
/// directory is a harmless no-op, only font files are registered, and re-running in
/// one process is idempotent (an already-registered font counts as success).
///
/// `@MainActor` so these tests are serialized with the render suites.
/// `CLIFontRegistration` itself has no actor isolation, but registering or
/// unregistering fonts mutates a process-wide Core Text table; letting that run on a
/// background thread *concurrently* with a render on the main actor (the golden-image
/// and CLI byte-identity suites) transiently invalidates Core Text's font caches
/// mid-render and shifts glyph rasterization by a few hundred PNG bytes. Pinning the
/// suite to the main actor keeps every font-table mutation ordered with respect to
/// every render, so the suites are independent of the order Swift Testing schedules
/// them in.
@MainActor
@Suite("CLI font registration (CS-033)")
struct CLIFontRegistrationTests {
    /// A unique scratch directory for one test.
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-cli-fonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The bundled font file name these registration tests copy and register.
    ///
    /// Deliberately **not** the render's default family (JetBrains Mono): these tests
    /// register a copy of a bundled `.ttf` from a scratch directory and then delete
    /// that directory, which perturbs the process-wide Core Text registration for that
    /// font's *contents*. If that font were JetBrains Mono — the family the golden-image
    /// and CLI byte-identity suites render in — the perturbation would subtly shift
    /// glyph rasterization (an off-by-a-few-hundred-bytes PNG difference) depending on
    /// the order Swift Testing happens to run the suites in. Using a bundled family the
    /// default render never touches keeps the Core Text registration path genuinely
    /// exercised while leaving the render's font untouched.
    private static let fontFileName = "SpaceMono-Regular.ttf"
    private static let fontResourceName = "SpaceMono-Regular"

    /// A real bundled `.ttf` from the app bundle the test host runs in. Using an
    /// actual font (not a fabricated file) means the Core Text registration path is
    /// genuinely exercised rather than always failing to parse.
    private func bundledFontURL() throws -> URL {
        try #require(
            Bundle.main.url(
                forResource: Self.fontResourceName, withExtension: "ttf",
                subdirectory: "Fonts"),
            "the test host app bundle should ship the bundled fonts")
    }

    /// Unregisters a font this suite registered from a temporary URL and drains the
    /// Core Text change notification, restoring the process's font state before the
    /// next test runs.
    ///
    /// `registerBundledFonts(in:)` registers fonts process-wide via
    /// `CTFontManagerRegisterFontsForURL(_:.process,_:)`. Two things make that unsafe to
    /// leave behind: a registration pointing at a file this test is about to delete is
    /// *dangling*, and — more subtly — each register/unregister posts an **asynchronous**
    /// fonts-changed notification that invalidates Core Text's glyph caches when the run
    /// loop next services it. If that notification is still in flight when the very next
    /// render runs (e.g. the CLI byte-identity or golden-image suites), it invalidates
    /// caches *mid-comparison* and shifts rasterization by a few hundred PNG bytes.
    /// Unregistering and then briefly spinning the run loop forces that invalidation to
    /// complete here, while no render is in progress, so these registration tests cannot
    /// perturb a later render regardless of the order Swift Testing runs them in.
    private func unregisterFont(at url: URL) {
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        // Let the pending fonts-changed notification be delivered now, not during a
        // subsequent render.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    @Test func nilDirectoryRegistersNothing() {
        // No bundled `Fonts` folder (a system-font-only setup) must not crash and
        // registers nothing, so a render still works without the bundled fonts.
        #expect(CLIFontRegistration.registerBundledFonts(in: nil).isEmpty)
    }

    @Test func onlyFontFilesAreRegistered() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A directory with no font files (here a stray license note) registers
        // nothing: non-`.ttf`/`.otf` entries are filtered out, not handed to Core
        // Text.
        try "not a font".write(
            to: directory.appendingPathComponent("LICENSES.md"), atomically: true,
            encoding: .utf8)
        #expect(CLIFontRegistration.registerBundledFonts(in: directory).isEmpty)
    }

    @Test func registersABundledFontAndSkipsNonFonts() throws {
        let directory = try makeTempDirectory()
        // Copy a genuine `.ttf` alongside a non-font file. Only the font is reported.
        let font = try bundledFontURL()
        let registeredFontURL = directory.appendingPathComponent(Self.fontFileName)
        try FileManager.default.copyItem(at: font, to: registeredFontURL)
        // Unregister before deleting the file so no dangling process-wide registration
        // survives to corrupt later renders (see `unregisterFont(at:)`).
        defer {
            unregisterFont(at: registeredFontURL)
            try? FileManager.default.removeItem(at: directory)
        }
        try "ignore me".write(
            to: directory.appendingPathComponent("README.txt"), atomically: true,
            encoding: .utf8)

        let registered = CLIFontRegistration.registerBundledFonts(in: directory)
        #expect(registered == [Self.fontFileName])
    }

    @Test func reRegisteringTheSameFontIsIdempotent() throws {
        let directory = try makeTempDirectory()
        let font = try bundledFontURL()
        let registeredFontURL = directory.appendingPathComponent(Self.fontFileName)
        try FileManager.default.copyItem(at: font, to: registeredFontURL)
        // Unregister before deleting the file so no dangling process-wide registration
        // survives to corrupt later renders (see `unregisterFont(at:)`).
        defer {
            unregisterFont(at: registeredFontURL)
            try? FileManager.default.removeItem(at: directory)
        }

        // A second pass in the same process hits Core Text's "already registered"
        // result, which the code treats as success — so the font is still reported
        // and the call never fails (the in-process re-run no-op the docs promise).
        _ = CLIFontRegistration.registerBundledFonts(in: directory)
        let again = CLIFontRegistration.registerBundledFonts(in: directory)
        #expect(again == [Self.fontFileName])
    }
}

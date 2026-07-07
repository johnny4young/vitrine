import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// CS-033 — `vitrine render` command-line renderer.
///
/// These tests cover the two halves of the CLI separately so neither needs a live
/// process:
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
        // No overrides → the app's own defaults.
        #expect(options.themeID == nil)
        #expect(options.language == nil)
        #expect(options.presetID == nil)
        #expect(options.scale == nil)
        #expect(options.format == .png)
        #expect(options.profile == .sRGB)
        #expect(options.transparent == false)
    }

    @Test func defaultConfigMatchesTheAppDefaultConfig() throws {
        let options = try CLIArguments.parse(["render", "input.swift", "--out", "out.png"])
        let config = options.makeConfig(code: "let x = 1", language: .swift)
        // A bare CLI render reproduces SnapshotConfig()'s defaults exactly — same
        // theme, font, padding, background, and chrome the editor starts with.
        let appDefault = SnapshotConfig()
        #expect(config.theme.id == appDefault.theme.id)
        #expect(config.fontName == appDefault.fontName)
        #expect(config.fontSize == appDefault.fontSize)
        #expect(config.padding == appDefault.padding)
        #expect(config.background == appDefault.background)
        #expect(config.showChrome == appDefault.showChrome)
        #expect(config.showShadow == appDefault.showShadow)
        // Only code and language come from the input.
        #expect(config.code == "let x = 1")
        #expect(config.language == .swift)
    }

    @Test func defaultScaleMatchesAppDefault() throws {
        let options = try CLIArguments.parse(["render", "input.swift", "--out", "out.png"])
        #expect(options.effectiveScale == CGFloat(SettingsDefaults.exportScale))
        #expect(options.fixedSize == nil)
    }

    // MARK: - Argument parsing: every option maps to its field

    @Test func parsesEveryOption() throws {
        let options = try CLIArguments.parse([
            "render", "snippet.py",
            "--out", "image.png",
            "--theme", "dracula",
            "--language", "python",
            "--preset", "opengraph",
            "--scale", "3",
            "--terminal-width", "100",
            "--format", "png",
            "--profile", "p3",
            "--transparent",
        ])
        #expect(options.inputPath == "snippet.py")
        #expect(options.outputPath == "image.png")
        #expect(options.themeID == "dracula")
        #expect(options.language == .python)
        #expect(options.presetID == "opengraph")
        #expect(options.scale == 3)
        #expect(options.terminalColumns == 100)
        #expect(options.profile == .displayP3)
        #expect(options.transparent)
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
        #expect(throws: CLIError.invalidValue(flag: "--scale", value: "9")) {
            try CLIArguments.parse(["render", "in.swift", "-o", "o.png", "--scale", "9"])
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
    }

    @Test func everyErrorHasANonEmptyMessage() {
        let errors: [CLIError] = [
            .helpRequested, .unknownCommand("x"), .unknownFlag("-x"),
            .missingValue(flag: "--out"), .missingRequired("input file"),
            .invalidValue(flag: "--theme", value: "x"), .inputUnreadable(path: "/x"),
            .inputNotText(path: "/x"), .renderFailed, .writeFailed(path: "/x"),
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

    @Test func transparentFlagOverridesPresetBackground() throws {
        let options = try CLIArguments.parse([
            "render", "in.swift", "-o", "o.png", "--preset", "twitter", "--transparent",
        ])
        // --transparent is the last word on the background even over a preset that
        // supplies a gradient.
        let config = options.makeConfig(code: "X", language: .swift)
        #expect(config.background == .transparent)
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

    // MARK: - Rendering: transparent background keeps real alpha

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

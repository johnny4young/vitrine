import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Failure contracts for malformed values and incompatible CLI options.
@MainActor
@Suite("CLI option validation")
struct CLIValidationTests: CLITestSupport {
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
            data: Data("export const Button = => <button>Save</button>\n".utf8),
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
            .inputNotText(path: "/x"), .gitDiffFailed, .gitDiffEmpty, .gitDiffTooLarge,
            .renderFailed, .outputExists(path: "/x"),
            .writeFailed(path: "/x"), .batchSkipped(rendered: 1, skipped: 1),
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
        }
    }

}

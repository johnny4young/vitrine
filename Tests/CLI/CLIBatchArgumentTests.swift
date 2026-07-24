import Foundation
import Testing

@testable import Vitrine

/// Batch option parsing, cross-command validation, and user-facing failure contracts.
@Suite("CLI batch arguments")
struct CLIBatchArgumentTests: CLITestSupport {
    @Test func parsesTheBatchCommandAndItsStyleFlags() throws {
        let options = try CLIArguments.parse(
            [
                "batch", "in-dir", "--out", "out-dir", "--quiet", "--theme", "dracula",
                "--font", "Hack", "--font-ligatures", "--background", "night",
                "--corner-radius", "14",
                "--shadow-radius", "22", "--format-code", "--highlight-lines", "3, 7-9",
                "--focus-lines",
                "--watermark", "@jane · vitrine", "--watermark-color", "#7DD3FC",
                "--watermark-position", "bottom-left",
                "--redact-lines", "4-5", "--redact-secrets", "--diff-bands", "--recursive",
                "--fail-on-skipped", "--skipped-report", "skipped.json", "--dry-run", "--manifest",
                "manifest.json", "--include-ext", ".swift,md", "--exclude-ext", "tmp",
                "--fail-on-empty", "--no-overwrite",
            ])
        #expect(options.command == .batch)
        #expect(options.quiet)
        #expect(options.inputPath == "in-dir")
        #expect(options.outputPath == "out-dir")
        #expect(options.themeID == "dracula")
        #expect(options.recursiveBatch)
        #expect(options.failOnSkipped)
        #expect(options.skippedReportPath == "skipped.json")
        #expect(options.batchManifestPath == "manifest.json")
        #expect(options.dryRunBatch)
        #expect(options.batchIncludeExtensions == Set(["swift", "md"]))
        #expect(options.batchExcludeExtensions == Set(["tmp"]))
        #expect(options.fontName == "Hack")
        #expect(options.fontLigatures == true)
        #expect(options.background == .gradient(.night))
        #expect(options.cornerRadius == 14)
        #expect(options.shadowRadius == 22)
        #expect(options.formatCode)
        #expect(options.watermarkText == "@jane · vitrine")
        #expect(options.watermarkColor == RGBAColor(hex: "#7DD3FC"))
        #expect(options.watermarkPosition == .bottomLeft)
        #expect(options.highlightedLineRanges == [3...3, 7...9])
        #expect(options.redactedLineRanges == [4...5])
        #expect(options.redactSecrets)
        #expect(options.focusHighlightedLines == true)
        #expect(options.diffDecorations == true)
        #expect(options.failOnEmpty)
        #expect(options.noOverwrite)
        #expect(!options.jsonOutput)
    }

    @Test func recursiveIsBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --recursive.")) {
            try CLIArguments.parse(["render", "in.swift", "--out", "out.png", "--recursive"])
        }
    }

    @Test func failOnSkippedIsBatchOnly() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine render with --fail-on-skipped.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--fail-on-skipped",
            ])
        }
    }

    @Test func failOnEmptyIsBatchOnly() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine render with --fail-on-empty.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--fail-on-empty",
            ])
        }
    }

    @Test func skippedReportIsBatchOnly() {
        #expect(
            throws: CLIError.incompatibleOptions("Cannot combine render with --skipped-report.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--skipped-report", "skipped.json",
            ])
        }
    }

    @Test func manifestIsBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --manifest.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--manifest", "manifest.json",
            ])
        }
    }

    @Test func quietParsesForRenderAndBatch() throws {
        let render = try CLIArguments.parse([
            "render", "in.swift", "--out", "out.png", "--quiet",
        ])
        #expect(render.quiet)

        let batch = try CLIArguments.parse([
            "batch", "in-dir", "--out", "out-dir", "-q",
        ])
        #expect(batch.quiet)
    }

    @Test func dryRunIsBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --dry-run.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--dry-run",
            ])
        }
    }

    @Test func batchExtensionFiltersAreBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --include-ext.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--include-ext", "swift",
            ])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --exclude-ext.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--exclude-ext", "tmp",
            ])
        }
    }

    @Test func batchExtensionFiltersRejectInvalidValues() {
        #expect(throws: CLIError.invalidValue(flag: "--include-ext", value: ",")) {
            try CLIArguments.parse([
                "batch", "in-dir", "--out", "out-dir", "--include-ext", ",",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--exclude-ext", value: "swift/evil")) {
            try CLIArguments.parse([
                "batch", "in-dir", "--out", "out-dir", "--exclude-ext", "swift/evil",
            ])
        }
    }

    @Test func batchEmptyReportsAClearMessageAndFailureExitCode() {
        #expect(CLIError.batchEmpty(skipped: 0).message == "Batch found no renderable input files.")
        #expect(
            CLIError.batchEmpty(skipped: 2).message
                == "Batch found no renderable input files (skipped 2 files).")
        #expect(CLIError.batchEmpty(skipped: 0).exitCode == 1)
    }
}

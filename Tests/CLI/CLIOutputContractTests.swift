import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// File, sidecar, sizing, format, identity, and loader output contracts.
@MainActor
@Suite("CLI output contracts")
struct CLIOutputContractTests: CLITestSupport {
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
        let contents = CLIOutputWriter.markdownSidecarContents(for: config, imageName: "snip.png")
        #expect(contents.contains("````swift\n"))
        #expect(contents.hasSuffix("````\n"))
        #expect(contents.hasPrefix("![Code rendered with Vitrine](snip.png)\n\n"))
    }

    @Test func markdownSidecarEscapesUserControlledImageSyntax() {
        var config = SnapshotConfig()
        config.language = .swift
        config.code = "print(\"hi\")\n"
        config.metadata = SnapshotMetadata(filename: "evil] name [draft")

        let contents = CLIOutputWriter.markdownSidecarContents(
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

        let contents = CLIOutputWriter.htmlSidecarContents(
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
            #expect(try String(contentsOf: sidecar, encoding: .utf8) == CLITestFixtures.sampleCode)
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

    @Test func multiSizeWriteFailureNamesTheArtifactThatFailed() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = try writeInput(named: "Sample.swift", in: directory)
        let output = directory.appendingPathComponent("cards", isDirectory: true)
        let blockedArtifact = output.appendingPathComponent(
            "vitrine-twitter.png", isDirectory: true)
        try FileManager.default.createDirectory(
            at: blockedArtifact, withIntermediateDirectories: true)
        let options = try CLIArguments.parse([
            "multi-size", input, "--out", output.path, "--presets", "twitter",
        ])

        #expect(throws: CLIError.writeFailed(path: blockedArtifact.path)) {
            try CLIRenderer.runMultiSize(options)
        }
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

    // MARK: - Pixel-identity with the app render path (core promise)

    @Test func cliOutputMatchesTheAppRendererPixelDimensions() throws {
        // Pin the input with an injected loader so both sides render from the exact
        // same code/language: this isolates the *pipeline*, proving the CLI runs the
        // unchanged `ExportManager` path rather than testing file-round-trip details.
        let loaded = FileInputLoader.LoadedFile(
            text: CLITestFixtures.sampleCode, language: .swift, filename: "Sample.swift")
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

}

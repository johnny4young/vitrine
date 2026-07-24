import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Raster rendering coverage for overlays, watermarks, and local backgrounds.
@MainActor
@Suite("CLI rendering")
struct CLIRenderingTests: CLITestSupport {
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

}

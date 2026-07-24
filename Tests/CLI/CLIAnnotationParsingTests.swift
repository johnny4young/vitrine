import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// Parsing and model-mapping coverage for watermark and annotation options.
@MainActor
@Suite("CLI annotation parsing")
struct CLIAnnotationParsingTests: CLITestSupport {
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
}

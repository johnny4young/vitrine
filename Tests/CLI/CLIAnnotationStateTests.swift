import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

@MainActor
@Suite("CLI annotation state compatibility")
struct CLIAnnotationStateTests {
    @Test func interleavedMarksUseFinalPerKindStyleAndKeepWithinKindOrder() throws {
        let options = try CLIArguments.parse([
            "render", "input.swift", "-o", "output.png",
            "--arrow-color", "#FF0000", "--arrow", "0.1,0.2,0.3,0.4",
            "--line", "0.2,0.6,0.8,0.6", "--arrow-color", "#0000FF",
            "--arrow", "0.5,0.6,0.7,0.8", "--arrow-size", "3", "--arrow-size", "9",
            "--line-color", "#00FF00", "--line-size", "5",
            "--highlighter-color", "#FFFFFF", "--highlighter", "0.1,0.1,0.2,0.2",
            "--blur-box", "0.2,0.2,0.3,0.3", "--rectangle", "0.3,0.3,0.4,0.4",
        ])
        #expect(options.arrows.map(\.start) == [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.6)])
        #expect(options.arrows.allSatisfy { $0.color == RGBAColor(hex: "#0000FF") && $0.size == 9 })
        #expect(options.lines.first?.color == RGBAColor(hex: "#00FF00"))
        #expect(options.lines.first?.size == 5)
        #expect(options.highlighters.first?.size == nil)
        #expect(options.blurBoxes.first?.color == nil)
        #expect(options.blurBoxes.first?.size == nil)
        #expect(
            options.makeConfig(code: "x", language: .swift).annotations.map(\.kind)
                == [.arrow, .arrow, .line, .rectangle, .highlighter, .blur])
    }

    @Test func repeatedPointValuesKeepLastAssignmentAndCanonicalModelOrder() throws {
        let options = try CLIArguments.parse([
            "render", "input.swift", "-o", "output.png", "--counter", "2",
            "--callout-y", "0.4", "--callout", "Earlier", "--counter-y", "0.8",
            "--callout-x", "0.3", "--counter-x", "0.7", "--counter", "8",
            "--callout", "Final", "--callout-x", "0.2",
        ])
        #expect(options.calloutText == "Final")
        #expect(options.calloutPosition == CGPoint(x: 0.2, y: 0.4))
        #expect(options.counterNumber == 8)
        #expect(options.counterPosition == CGPoint(x: 0.7, y: 0.8))
        #expect(
            options.makeConfig(code: "x", language: .swift).annotations.map(\.kind)
                == [.text, .counter])
    }

    @Test func semanticErrorsKeepKindPrecedenceRegardlessOfFlagOrder() {
        for modifiers in [
            ["--line-size", "5", "--arrow-size", "7"],
            ["--arrow-size", "7", "--line-size", "5"],
        ] {
            #expect(
                throws: CLIError.incompatibleOptions(
                    "--arrow-color and --arrow-size require --arrow.")
            ) {
                try CLIArguments.parse(["render", "input.swift", "-o", "output.png"] + modifiers)
            }
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "--callout-x and --callout-y must be provided together.")
        ) {
            try CLIArguments.parse([
                "render", "input.swift", "-o", "output.png", "--counter-size", "5",
                "--callout", "Note", "--callout-x", "0.2",
            ])
        }
    }

    @Test func syntaxAndCrossFeatureErrorsKeepTheirExistingPrecedence() {
        #expect(throws: CLIError.invalidValue(flag: "--line", value: "invalid")) {
            try CLIArguments.parse([
                "render", "input.swift", "-o", "output.png", "--arrow-size", "7",
                "--line", "invalid",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions("--arrow-color and --arrow-size require --arrow.")
        ) {
            try CLIArguments.parse([
                "render", "input.swift", "-o", "output.png", "--frame", "browser",
                "--arrow-size", "7",
            ])
        }
    }

    @Test func annotationStateDoesNotSurviveAnotherInvocation() throws {
        let styled = try CLIArguments.parse([
            "render", "input.swift", "-o", "output.png", "--arrow", "0.1,0.1,0.9,0.9",
            "--arrow-color", "#0000FF", "--arrow-size", "9",
        ])
        let fresh = try CLIArguments.parse([
            "render", "input.swift", "-o", "output.png", "--arrow", "0.1,0.1,0.9,0.9",
        ])
        #expect(styled.arrows.first?.size == 9)
        #expect(fresh.arrows.first?.color == nil)
        #expect(fresh.arrows.first?.size == nil)
        #expect(fresh.calloutText == nil)
        #expect(fresh.counterNumber == nil)
    }
}

import AppKit
import SwiftUI
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@MainActor
@Suite("Code steps")
struct CodeStepsTests {
    private let step1 = "func greet(_ name: String) -> String {\n    return \"Hello, \" + name\n}"
    private let step2 =
        "func greet(_ name: String) -> String {\n    let trimmed = name\n    return \"Hello, \\(trimmed)!\"\n}"

    @Test func stepsAreRefusedWhereTheyCouldShowHiddenContent() {
        var style = SnapshotConfig()
        #expect(CodeStepRules.isAvailable(for: style))
        style.redactedLineRanges = [1...1]
        #expect(!CodeStepRules.isAvailable(for: style))
        style.redactedLineRanges = []
        style.annotations = [
            Annotation(kind: .blur, start: .zero, end: CGPoint(x: 0.5, y: 0.5))
        ]
        #expect(!CodeStepRules.isAvailable(for: style))
        style.annotations = [Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))]
        #expect(CodeStepRules.isAvailable(for: style))
        style.language = .terminal
        #expect(!CodeStepRules.isAvailable(for: style))
        style.language = .swift
        style.foregroundImage = ImageReference(fileName: "shot.png")
        #expect(!CodeStepRules.isAvailable(for: style))
    }

    @Test func addingStoresTheCodeInOrder() {
        var style = SnapshotConfig()
        #expect(CodeStepRules.adding(step1, to: &style) == 0)
        #expect(CodeStepRules.adding(step2, to: &style) == 1)
        #expect(style.codeSteps == [step1, step2])
        #expect(CodeStepRules.adding("", to: &style) == nil)
    }

    @Test func aStepNeverHoldsADetectedSecret() {
        var style = SnapshotConfig()
        // Assembled at runtime so the repository holds no secret-shaped literal.
        let key = "AKIA" + String(repeating: "Q", count: 16)
        #expect(CodeStepRules.adding("let key = \"\(key)\"", to: &style) == nil)
        #expect(style.codeSteps.isEmpty)
    }

    @Test func addingStopsAtTheLimit() {
        var style = SnapshotConfig()
        style.codeSteps = Array(repeating: "x", count: CodeStepRules.limit)
        #expect(CodeStepRules.adding("y", to: &style) == nil)
        #expect(style.codeSteps.count == CodeStepRules.limit)
    }

    @Test func newContentDropsTheSteps() {
        var config = SnapshotConfig(code: step1, language: .swift)
        config.codeSteps = [step1, step2]
        #expect(config.hasContentMarks)
        let replaced = config.replacingContent(with: "other")
        #expect(replaced.codeSteps.isEmpty)
        #expect(!replaced.hasContentMarks)
    }

    @Test func aStaticExportIgnoresTheSteps() throws {
        let plain = SnapshotConfig(code: step2, language: .swift)
        var stepped = plain
        stepped.codeSteps = [step1, step2]
        var plainPNG = Data()
        var steppedPNG = Data()
        for _ in 0..<RenderSettling.strictRenderAttempts {
            plainPNG = try png(SnapshotCanvas(config: plain))
            steppedPNG = try png(SnapshotCanvas(config: stepped))
            if plainPNG == steppedPNG { break }
            RenderSettling.settleFontCaches()
        }
        #expect(plainPNG == steppedPNG)
    }

    @Test func anAnimationForOtherCodeIsNotDrawn() throws {
        let config = SnapshotConfig(code: step2, language: .swift)
        let stale = try #require(CodeStepAnimation(id: 1, from: step2, to: step1, moves: true))
        var plainPNG = Data()
        var staleRender = Data()
        for _ in 0..<RenderSettling.strictRenderAttempts {
            plainPNG = try png(SnapshotCanvas(config: config))
            staleRender = try png(SnapshotCanvas(config: config, codeStepAnimation: stale))
            if plainPNG == staleRender { break }
            RenderSettling.settleFontCaches()
        }
        #expect(plainPNG == staleRender)
    }

    @Test func tabsAndOversizedStepsDoNotAnimate() {
        #expect(CodeStepAnimation(id: 1, from: "\tx", to: "x", moves: true) == nil)
        #expect(CodeStepAnimation(id: 1, from: "", to: "x", moves: true) == nil)
        #expect(CodeStepAnimation(id: 1, from: "a", to: "b", moves: true) != nil)
    }

    @Test(arguments: [
        ("JetBrains Mono", 14.0), ("Fira Code", 20.0), ("SF Mono", 11.0), ("Menlo", 15.0),
    ])
    func rowsLandWhereThePlainTextPutsThem(family: String, size: Double) throws {
        let font = Font(CodeFont.resolved(family: family, size: size, ligatures: false))
        final class Probe { var lineHeight: CGFloat = 0 }
        let probe = Probe()
        let canvas = Canvas { context, _ in
            probe.lineHeight = CodeStepMorphLayout.lineHeight(of: font, in: context)
        }
        .frame(width: 8, height: 8)
        _ = ImageRenderer(content: canvas).cgImage
        let threeLines = NSHostingController(
            rootView: Text(verbatim: "0\n0\n0").font(font).lineSpacing(4)
        ).sizeThatFits(in: CGSize(width: 4000, height: 4000))
        #expect(abs(threeLines.height - (3 * probe.lineHeight + 2 * 4)) <= 0.5)
    }

    @Test func theCardEasesBetweenTheTwoStepsSizes() {
        let short = Text(verbatim: "a")
        let tall = Text(verbatim: "abc\nd")
        func size(at progress: Double) -> CGSize {
            NSHostingController(
                rootView: CodeStepMorphFrame(progress: progress) {
                    short
                    tall
                    Color.clear
                }
            ).sizeThatFits(in: CGSize(width: 4000, height: 4000))
        }
        let from = NSHostingController(rootView: short).sizeThatFits(
            in: CGSize(width: 4000, height: 4000))
        let to = NSHostingController(rootView: tall).sizeThatFits(
            in: CGSize(width: 4000, height: 4000))
        #expect(size(at: 0) == from)
        #expect(size(at: 1) == to)
        #expect(size(at: 0.5).height == (from.height + to.height) / 2)
    }

    @Test func tokensGlideFadeOutAndFadeIn() throws {
        let font = CodeFont.resolved(family: "JetBrains Mono", size: 14, ligatures: false)
        let animation = try #require(CodeStepAnimation(id: 1, from: "a b", to: "b c", moves: true))
        let layout = CodeStepMorphLayout(
            animation, language: .swift, theme: .oneDark, font: font)
        let glyph = { (text: String) in try #require(layout.glyphs.first { $0.text == text }) }

        let moved = try glyph("b")
        #expect(moved.state(at: 0)?.cell == CGPoint(x: 2, y: 0))
        #expect(moved.state(at: 0.5)?.cell == CGPoint(x: 1, y: 0))
        #expect(moved.state(at: 1)?.cell == .zero)
        #expect(moved.state(at: 0.5)?.opacity == 1)

        let leaving = try glyph("a")
        #expect(leaving.state(at: 0)?.opacity == 1)
        #expect(leaving.state(at: 0.5)?.opacity == 0)

        let entering = try glyph("c")
        #expect(entering.state(at: 0.5)?.opacity == 0)
        #expect(entering.state(at: 1)?.opacity == 1)
        #expect(entering.state(at: 1)?.cell == CGPoint(x: 2, y: 0))
    }

    @Test func reduceMotionCrossFadesInsteadOfMoving() throws {
        let font = CodeFont.resolved(family: "JetBrains Mono", size: 14, ligatures: false)
        let animation = try #require(
            CodeStepAnimation(id: 1, from: "a b", to: "b c", moves: false))
        let layout = CodeStepMorphLayout(
            animation, language: .swift, theme: .oneDark, font: font)
        #expect(layout.glyphs.allSatisfy { $0.from == nil || $0.to == nil || $0.from == $0.to })
        #expect(layout.glyphs.filter { $0.text == "b" }.count == 2)

        let still = try #require(
            CodeStepAnimation(id: 2, from: "a b", to: "a c", moves: false))
        let stillLayout = CodeStepMorphLayout(
            still, language: .swift, theme: .oneDark, font: font)
        let a = try #require(stillLayout.glyphs.first { $0.text == "a" })
        #expect(a.state(at: 0.5)?.opacity == 1)
    }

    private func png(_ canvas: SnapshotCanvas) throws -> Data {
        let image = try ExportManager.renderCGImageChecked(
            canvas, proposedSize: nil, scale: 1, profile: .sRGB)
        return try #require(ExportManager.pngData(from: image))
    }
}

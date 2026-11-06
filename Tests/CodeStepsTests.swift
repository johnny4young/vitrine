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
    private let font = CodeFont.resolved(family: "JetBrains Mono", size: 14, ligatures: false)

    private func stepped(_ steps: [String], active: Int?) -> SnapshotConfig {
        var style = SnapshotConfig()
        style.codeSteps = steps
        style.activeCodeStep = active
        return style
    }

    @Test func stepsAreRefusedWhereTheyCouldShowHiddenContent() {
        var style = SnapshotConfig()
        #expect(CodeStepRules.isAvailable(for: style))
        style.redactedLineRanges = [1...1]
        #expect(!CodeStepRules.isAvailable(for: style))
        style.redactedLineRanges = []
        style.annotations = [Annotation(kind: .blur, start: .zero, end: CGPoint(x: 0.5, y: 0.5))]
        #expect(!CodeStepRules.isAvailable(for: style))
        style.annotations = [Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))]
        #expect(CodeStepRules.isAvailable(for: style))
        style.language = .terminal
        #expect(!CodeStepRules.isAvailable(for: style))
        style.language = .swift
        style.foregroundImage = ImageReference(fileName: "shot.png")
        #expect(!CodeStepRules.isAvailable(for: style))
    }

    @Test func addingAppendsTheActiveStep() {
        var style = SnapshotConfig()
        #expect(CodeStepRules.adding(step1, to: &style))
        #expect(CodeStepRules.adding(step2, to: &style))
        #expect(style.codeSteps == [step1, step2])
        #expect(style.activeCodeStep == 1)
        #expect(!CodeStepRules.adding("", to: &style))
        style.codeSteps = Array(repeating: "x", count: CodeStepRules.limit)
        #expect(!CodeStepRules.adding("y", to: &style))
    }

    @Test func aStepNeverHoldsADetectedSecret() {
        // Assembled at runtime so the repository holds no secret-shaped literal.
        let secret = "let key = \"" + "AKIA" + String(repeating: "Q", count: 16) + "\""
        var style = SnapshotConfig()
        #expect(!CodeStepRules.adding(secret, to: &style))
        style = stepped([step1, step2], active: 0)
        #expect(CodeStepRules.showing(1, draft: secret, in: &style) == nil)
        #expect(style.codeSteps == [step1, step2])
    }

    @Test func showingSavesTheEditsIntoTheStepTheyWereMadeIn() {
        var style = stepped([step1, step2], active: 0)
        #expect(CodeStepRules.showing(1, draft: step1 + "\n// edited", in: &style) == step2)
        #expect(style.activeCodeStep == 1)
        #expect(CodeStepRules.showing(0, draft: step2, in: &style) == step1 + "\n// edited")
    }

    @Test func removingLoadsTheStepThatTakesItsPlace() {
        var style = stepped(["a", "b", "c"], active: 1)
        #expect(CodeStepRules.removing(from: &style) == "c")
        #expect(style.codeSteps == ["a", "c"])
        #expect(style.activeCodeStep == 1)

        style.activeCodeStep = nil
        #expect(CodeStepRules.removing(from: &style) == "a")
        #expect(style.codeSteps == ["a"])

        style.redactedLineRanges = [1...1]
        style.codeSteps = ["a", "b"]
        style.activeCodeStep = 0
        #expect(CodeStepRules.removing(from: &style) == nil)
        #expect(style.codeSteps == ["b"])
        #expect(style.activeCodeStep == nil)
    }

    @Test func aPastedDocumentKeepsTheSteps() {
        var style = stepped([step1, step2], active: 1)
        style.redactedLineRanges = [2...2]
        style.annotations = [Annotation(kind: .arrow, start: .zero, end: CGPoint(x: 1, y: 1))]
        let pasted = CodeStepRules.pastingDocument(over: style, language: .python)
        #expect(pasted.codeSteps == [step1, step2])
        #expect(pasted.activeCodeStep == 1)
        #expect(pasted.redactedLineRanges.isEmpty)
        #expect(pasted.annotations.isEmpty)
        #expect(pasted.language == .python)
    }

    @Test func aNewDocumentDropsTheSteps() {
        var config = stepped([step1, step2], active: 0)
        config.code = step1
        #expect(config.hasContentMarks)
        let replaced = config.replacingContent(with: "other")
        #expect(replaced.codeSteps.isEmpty)
        #expect(replaced.activeCodeStep == nil)
    }

    @Test func stepChangesAreUndoableAndKeepTypingUndo() throws {
        let settings = AppSettings(defaults: testDefaults())
        let textView = NSTextView()
        textView.allowsUndo = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        defer { window.close() }
        let undo = try #require(textView.undoManager)
        // No run loop turns here, so each user action is grouped by hand.
        undo.groupsByEvent = false
        func action(_ body: () -> Void) {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
        }
        let editor = CodeStepEditor(settings: settings, textView: textView, undoManager: undo)
        textView.string = step1
        settings.documentCode = step1

        var style = settings.style
        #expect(CodeStepRules.adding(step1, to: &style))
        #expect(CodeStepRules.adding(step2, to: &style))
        action { editor.commit(style, text: nil, actionName: "Add Step") }
        undo.undo()
        #expect(settings.style.codeSteps.isEmpty)
        undo.redo()
        #expect(settings.style.codeSteps == [step1, step2])

        action {
            textView.insertText(
                "\n// edited",
                replacementRange: NSRange(location: (step1 as NSString).length, length: 0))
        }
        settings.documentCode = textView.string
        let edited = textView.string
        style = settings.style
        let target = try #require(CodeStepRules.showing(0, draft: edited, in: &style))
        action { editor.commit(style, text: target, actionName: "Show Step") }
        #expect(textView.string == step1)
        #expect(settings.documentCode == step1)

        undo.undo()
        #expect(textView.string == edited)
        #expect(settings.style.activeCodeStep == 1)
        #expect(settings.style.codeSteps == [step1, step2])
        undo.undo()
        #expect(textView.string == step1, "Typing undo survives the step change")

        style = settings.style
        let next = CodeStepRules.removing(from: &style)
        action { editor.commit(style, text: next, actionName: "Remove Step") }
        #expect(settings.style.codeSteps == [step1])
        undo.undo()
        #expect(settings.style.codeSteps == [step1, step2])
    }

    @Test func aStaticExportIgnoresTheSteps() throws {
        let plain = SnapshotConfig(code: step2, language: .swift)
        var withSteps = plain
        withSteps.codeSteps = [step1, step2]
        withSteps.activeCodeStep = 1
        try expectSameRender(SnapshotCanvas(config: plain), SnapshotCanvas(config: withSteps))
    }

    @Test func anAnimationForOtherCodeIsNotDrawn() throws {
        let config = SnapshotConfig(code: step2, language: .swift)
        let stale = try #require(
            CodeStepAnimation(
                id: 1, from: step2, to: step1, language: .swift, theme: .oneDark, font: font))
        try expectSameRender(
            SnapshotCanvas(config: config), SnapshotCanvas(config: config, codeStepAnimation: stale)
        )
    }

    @Test func tabsAndOversizedStepsCrossFadeInstead() {
        func animation(_ from: String, _ to: String) -> CodeStepAnimation? {
            CodeStepAnimation(
                id: 1, from: from, to: to, language: .swift, theme: .oneDark, font: font)
        }
        #expect(animation("\tx", "x") == nil)
        #expect(animation("", "x") == nil)
        #expect(
            animation("a", String(repeating: "a ", count: CodeStepTransition.tokenLimit + 1)) == nil
        )
        #expect(animation("a", "b") != nil)
    }

    @Test func aForcedFadeCrossFadesDifferentCode() {
        let old = SnapshotCanvas(config: SnapshotConfig(code: step1, language: .swift))
        let new = SnapshotCanvas(config: SnapshotConfig(code: step2, language: .swift))
        let fade = PreviewThemeFade(canvas: old)
        #expect(fade.applying(new, animated: true).outgoing == nil)
        #expect(fade.applying(new, animated: true, forced: true).outgoing?.canvas == old)
        #expect(fade.applying(new, animated: false, forced: true).outgoing == nil)
    }

    @Test(arguments: [
        ("JetBrains Mono", 14.0), ("Fira Code", 20.0), ("SF Mono", 11.0), ("Menlo", 15.0),
    ])
    func rowsLandWhereThePlainTextPutsThem(family: String, size: Double) {
        let font = Font(CodeFont.resolved(family: family, size: size, ligatures: false))
        final class Probe { var lineHeight: CGFloat = 0 }
        let probe = Probe()
        let canvas = Canvas { context, _ in
            probe.lineHeight = CodeStepAnimation.lineHeight(of: font, in: context)
        }
        .frame(width: 8, height: 8)
        _ = ImageRenderer(content: canvas).cgImage
        let threeLines = NSHostingController(
            rootView: Text(verbatim: "0\n0\n0").font(font).lineSpacing(4)
        ).sizeThatFits(in: CGSize(width: 4000, height: 4000))
        #expect(abs(threeLines.height - (3 * probe.lineHeight + 2 * 4)) <= 0.5)
    }

    @Test func tokensGlideFadeOutAndFadeIn() throws {
        let animation = try #require(
            CodeStepAnimation(
                id: 1, from: "a b", to: "b c", language: .swift, theme: .oneDark, font: font))
        let glyph = { (text: String) in try #require(animation.glyphs.first { $0.text == text }) }

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

    private func expectSameRender(_ lhs: SnapshotCanvas, _ rhs: SnapshotCanvas) throws {
        var left = Data()
        var right = Data()
        for _ in 0..<RenderSettling.strictRenderAttempts {
            left = try png(lhs)
            right = try png(rhs)
            if left == right { break }
            RenderSettling.settleFontCaches()
        }
        #expect(left == right)
    }

    private func png(_ canvas: SnapshotCanvas) throws -> Data {
        let image = try ExportManager.renderCGImageChecked(
            canvas, proposedSize: nil, scale: 1, profile: .sRGB)
        return try #require(ExportManager.pngData(from: image))
    }
}

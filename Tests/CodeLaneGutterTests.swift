import AppKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Code editor focus lanes")
struct CodeLaneGutterTests {
    @Test func laneActionsEditTheConfigMarks() {
        var config = SnapshotConfig()
        config.apply(.toggle(.highlight, 4...5))
        config.apply(.toggle(.redact, 5...6))
        #expect(config.highlightedLineRanges == [4...5])
        #expect(config.redactedLineRanges == [5...6])
        config.apply(.clear(5...5))
        #expect(config.lineMarks == LineMarks(highlighted: [4...4], redacted: [6...6]))
        config.apply(.toggleFocus)
        #expect(config.focusHighlightedLines)
    }

    @Test func selectionMapsToTheLinesItTouches() {
        let text = "one\ntwo\r\nthree\nfour" as NSString
        #expect(CodeLines.lines(of: NSRange(location: 1, length: 0), in: text) == nil)
        #expect(CodeLines.lines(of: NSRange(location: 0, length: 3), in: text) == 1...1)
        // A whole-line selection ends on its newline and stays on that line.
        #expect(CodeLines.lines(of: NSRange(location: 4, length: 5), in: text) == 2...2)
        #expect(CodeLines.lines(of: NSRange(location: 2, length: 12), in: text) == 1...3)
        #expect(CodeLines.line(atUTF16Offset: text.length, in: text) == 4)
        #expect(CodeLines.line(atUTF16Offset: -3, in: text) == 1)
    }

    /// A text view in a window, laid out, with the editor's gutter showing.
    private func hostedTextView(
        _ text: String, width: CGFloat = 400, gutter: CodeLaneGutter = CodeLaneGutter()
    ) throws -> (NSWindow, CodeTextView) {
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        textView.textContainerInset = NSSize(width: CodeTextView.baseInset, height: 12)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        textView.laneGutter = gutter
        textView.showsGutter = true
        textView.string = text
        textView.recountLines()
        let manager = try #require(textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        return (window, textView)
    }

    private func editor(language: Language) -> CodeEditorView.Coordinator {
        CodeEditorView.Coordinator(
            CodeEditorView(
                text: .constant(""), language: language, theme: .oneDark, fontName: "SF Mono",
                fontSize: 13, fontLigatures: false, reindentOnPaste: false))
    }

    @Test func terminalCapturesShowNoLanesOrSelectionActions() throws {
        let settings = AppSettings(defaults: testDefaults())
        for (language, expectsLanes) in [(Language.swift, true), (.terminal, false)] {
            let coordinator = editor(language: language)
            let (window, textView) = try hostedTextView("one\ntwo", gutter: coordinator.gutter)
            defer { window.close() }
            coordinator.applySurface(to: textView)
            coordinator.syncLanes(textView, settings: settings)
            #expect(textView.showsGutter == expectsLanes)
            #expect(textView.laneActionsEnabled == expectsLanes)
            textView.setSelectedRange(NSRange(location: 0, length: 5))
            let command = NSMenuItem(
                title: "", action: #selector(CodeTextView.redactSelectedLines(_:)),
                keyEquivalent: "")
            #expect(textView.validateMenuItem(command) == expectsLanes)
        }
    }

    @Test func markEditsAreOneUndoableStep() {
        let settings = AppSettings(defaults: testDefaults())
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        CodeEditorView.Coordinator.apply(
            .toggle(.redact, 2...3), to: settings, undoManager: undoManager)
        undoManager.endUndoGrouping()
        #expect(settings.style.redactedLineRanges == [2...3])
        #expect(undoManager.undoActionName == String(localized: "Mark Lines"))

        undoManager.undo()
        #expect(settings.style.redactedLineRanges.isEmpty)
        undoManager.redo()
        #expect(settings.style.redactedLineRanges == [2...3])
    }

    @Test func editsTellTheMarksHowLinesMoved() throws {
        let (window, textView) = try hostedTextView("one\ntwo\nthree")
        defer { window.close() }
        var edits: [LineEdit] = []
        textView.onLineEdit = { edits.append($0) }
        // Return at the end of line 1, as typed.
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("\n", replacementRange: textView.selectedRange())
        #expect(
            edits.last
                == LineEdit(
                    line: 1, removedBreaks: 0, insertedBreaks: 1, startsAtLineStart: false,
                    endsAtLineEnd: true))
        #expect(textView.lineCount == 4)
        // Deleting from the start of the new empty line 2 into line 3.
        textView.setSelectedRange(NSRange(location: 4, length: 4))
        textView.insertText("", replacementRange: textView.selectedRange())
        #expect(edits.last?.removedBreaks == 1)
        #expect(edits.last?.startsAtLineStart == true)
        #expect(textView.lineCount == 3)
        // Typing without a line break moves nothing.
        let count = edits.count
        textView.insertText("x", replacementRange: textView.selectedRange())
        #expect(edits.count == count)
        // Replacing the whole document is a new capture: no shift, and no ⇧-click anchor.
        let gutter = try #require(textView.laneGutter)
        _ = gutter.lines(at: NSPoint(x: 4, y: 14), extending: false, in: textView)
        #expect(gutter.anchorLine != nil)
        textView.selectAll(nil)
        textView.insertText("new\ncapture", replacementRange: textView.selectedRange())
        #expect(edits.count == count)
        #expect(gutter.anchorLine == nil)
        #expect(textView.lineCount == 2)
    }

    @Test func selectionCommandsMarkTheSelectedLines() throws {
        let gutter = CodeLaneGutter()
        var received: [CodeLaneAction] = []
        gutter.onAction = { received.append($0) }
        let (window, textView) = try hostedTextView("one\ntwo\nthree", gutter: gutter)
        defer { window.close() }
        textView.setSelectedRange(NSRange(location: 2, length: 4))
        textView.highlightSelectedLines(nil)
        textView.redactSelectedLines(nil)
        #expect(received == [.toggle(.highlight, 1...2), .toggle(.redact, 1...2)])
        let names = textView.accessibilityCustomActions()?.map(\.name) ?? []
        #expect(names.contains(CodeTextView.selectionCommands[0].title))
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(textView.accessibilityCustomActions()?.map(\.name).contains(names[0]) != true)
    }

    @Test func aClickOnAWrappedLineChoosesThatLine() throws {
        let long = String(repeating: "wrapped ", count: 30)
        let gutter = CodeLaneGutter()
        let (window, textView) = try hostedTextView(
            "short\n\(long)\nend", width: 200, gutter: gutter)
        defer { window.close() }
        let lanes = gutter.visibleLanes(of: textView)
        let wrapped = try #require(lanes.first { $0.line == 2 })
        #expect(wrapped.paragraph.height > wrapped.row.height * 2)
        let lowerRow = NSPoint(x: 4, y: wrapped.paragraph.maxY - 2)
        #expect(gutter.lines(at: lowerRow, extending: false, in: textView) == 2...2)
        let below = try #require(lanes.first { $0.line == 3 })
        #expect(
            gutter.lines(at: NSPoint(x: 4, y: below.row.midY), extending: true, in: textView)
                == 2...3)
    }

    @Test func aClickInTheCodeLandsOnTheCharacterUnderIt() throws {
        let (window, textView) = try hostedTextView("abcdef")
        defer { window.close() }
        let font = try #require(textView.font)
        let advance = CodeFont.advance(of: "a", in: font)
        let origin = textView.textContainerOrigin
        #expect(origin.x > CodeTextView.baseInset)
        let point = NSPoint(x: origin.x + advance * 3 + 1, y: origin.y + font.pointSize / 2)
        #expect(textView.characterIndexForInsertion(at: point) == 3)
    }

    @Test func gutterTakesRoomFromTheLeadingEdgeOnly() throws {
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.textContainerInset = NSSize(width: CodeTextView.baseInset, height: 12)
        let gutter = CodeLaneGutter()
        #expect(gutter.fit(codeFontSize: 14, lineCount: 120))
        #expect(!gutter.fit(codeFontSize: 14, lineCount: 130))
        textView.laneGutter = gutter
        #expect(textView.textContainerOrigin.x == CodeTextView.baseInset)
        textView.showsGutter = true
        let expected = CodeTextView.baseInset + gutter.width - CodeTextView.gutterOverlap
        #expect(abs(textView.textContainerOrigin.x - expected) <= 1)
        #expect(textView.textContainerOrigin.x > gutter.width)
        textView.string = "let a = 1\nlet b = 2"
        textView.display()
        #expect(textView.textLayoutManager != nil)
        textView.showsGutter = false
        #expect(textView.textContainerOrigin.x == CodeTextView.baseInset)
    }

    /// TextKit starts a paragraph at a lone `\r`, U+2028 or U+2029; the renderer does not, so
    /// the gutter must number those paragraphs with the line they render on.
    @Test func gutterNumbersTheLinesTheRendererDraws() throws {
        let text = "a\rb\u{2028}c\u{2029}d\ne\r\nf"
        let rendered = LineSplitter.lineCount(of: text)
        #expect(rendered == 3)
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        textView.string = text
        let manager = try #require(textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)

        let lines = CodeLaneGutter().visibleLanes(of: textView).map(\.line)
        #expect(lines.count > rendered, "TextKit splits more paragraphs than the renderer")
        #expect(lines == lines.sorted())
        #expect(Set(lines) == Set(1...rendered))
        #expect(lines.filter { $0 == 1 }.count >= 3)
        let text16 = text as NSString
        #expect(CodeLines.line(atUTF16Offset: text16.range(of: "d").location, in: text16) == 1)
        #expect(CodeLines.line(atUTF16Offset: text16.range(of: "f").location, in: text16) == 3)
    }

    @Test func gutterMenuReflectsAndEditsTheRangeMarks() throws {
        let gutter = CodeLaneGutter()
        gutter.marks = LineMarks(highlighted: [2...4])
        var received: [CodeLaneAction] = []
        gutter.onAction = { received.append($0) }

        let menu = gutter.menu(for: 3...4)
        let item = { (id: String) in
            menu.items.first { $0.accessibilityIdentifier() == id }
        }
        let highlight = try #require(item("code-lane-highlight"))
        let redact = try #require(item("code-lane-redact"))
        let clear = try #require(item("code-lane-clear"))
        let focus = try #require(item("code-lane-focus"))
        #expect(menu.items.first?.title.hasSuffix(" 3–4") == true)
        #expect(highlight.state == .on)
        #expect(redact.state == .off)
        #expect(clear.isEnabled)
        #expect(focus.isEnabled)

        menu.performActionForItem(at: try #require(menu.items.firstIndex(of: redact)))
        menu.performActionForItem(at: try #require(menu.items.firstIndex(of: focus)))
        #expect(received == [.toggle(.redact, 3...4), .toggleFocus])

        gutter.marks = LineMarks()
        let empty = gutter.menu(for: 7...7)
        #expect(empty.items.first?.title.hasSuffix(" 7") == true)
        #expect(
            empty.items.first { $0.accessibilityIdentifier() == "code-lane-clear" }?.isEnabled
                == false)
        #expect(
            empty.items.first { $0.accessibilityIdentifier() == "code-lane-focus" }?.isEnabled
                == false)
    }
}

import AppKit
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

import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// An edit the code pane's gutter or selection bar makes to the line marks.
enum CodeLaneAction: Equatable {
    case toggle(LineMark, ClosedRange<Int>)
    case clear(ClosedRange<Int>)
    case toggleFocus
}

extension SnapshotConfig {
    var lineMarks: LineMarks {
        LineMarks(highlighted: highlightedLineRanges, redacted: redactedLineRanges)
    }

    mutating func apply(_ action: CodeLaneAction) {
        var marks = lineMarks
        switch action {
        case .toggle(let mark, let range): marks.toggle(mark, on: range)
        case .clear(let range): marks.clear(range)
        case .toggleFocus: focusHighlightedLines.toggle()
        }
        highlightedLineRanges = marks.highlighted
        redactedLineRanges = marks.redacted
    }

    /// Moves the marks with the text an edit moved.
    mutating func shiftLineMarks(for edit: LineEdit) {
        let shifted = lineMarks.adjusted(for: edit)
        highlightedLineRanges = shifted.highlighted
        redactedLineRanges = shifted.redacted
    }
}

/// Maps UTF-16 offsets in the editor text to the 1-based lines the stage numbers.
enum CodeLines {
    /// Only `\n` starts a line, as in `LineSplitter`: a lone `\r`, U+2028 or U+2029 does not.
    /// Pass a known earlier position as `start` to count from there.
    static func line(
        atUTF16Offset offset: Int, in text: NSString, from start: (offset: Int, line: Int) = (0, 1)
    ) -> Int {
        let end = min(max(offset, 0), text.length)
        let begin = min(max(start.offset, 0), end)
        var line = start.line
        var search = NSRange(location: begin, length: end - begin)
        while true {
            let found = text.range(of: "\n", options: .literal, range: search)
            guard found.location != NSNotFound else { return line }
            line += 1
            search = NSRange(location: found.location + 1, length: end - found.location - 1)
        }
    }

    /// The `\n`s in `range`.
    static func breaks(in text: NSString, range: NSRange) -> Int {
        var count = 0
        var search = range
        while search.length > 0 {
            let found = text.range(of: "\n", options: .literal, range: search)
            guard found.location != NSNotFound else { break }
            count += 1
            search = NSRange(
                location: found.location + 1, length: NSMaxRange(search) - found.location - 1)
        }
        return count
    }

    /// The lines a non-empty selection touches; a trailing newline stays on its own line.
    static func lines(of selection: NSRange, in text: NSString) -> ClosedRange<Int>? {
        guard selection.length > 0, selection.location != NSNotFound else { return nil }
        let first = line(atUTF16Offset: selection.location, in: text)
        let last = line(atUTF16Offset: NSMaxRange(selection) - 1, in: text)
        return first...max(first, last)
    }
}

/// The code pane's gutter: line numbers with each line's mark, drawn by the text view in its
/// left inset, and a click target that edits them. ⇧-click extends from the last clicked line.
final class CodeLaneGutter {
    var marks = LineMarks()
    var focusesHighlighted = false
    var ink: NSColor = .secondaryLabelColor
    var highlightTint: NSColor = .selectedTextBackgroundColor
    var onAction: ((CodeLaneAction) -> Void)?
    private(set) var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private var digits = 2
    /// The line a plain click chose, which a ⇧-click extends from.
    private(set) var anchorLine: Int?
    /// The first visible paragraph's offset and line, so a redraw counts breaks from there
    /// instead of from the top of the document.
    private var visibleStart: (offset: Int, line: Int)?

    /// A replaced document has no line to extend a range from.
    func documentReplaced() {
        anchorLine = nil
        visibleStart = nil
    }

    /// Keeps `visibleStart` valid across an edit, or drops it when the edit reaches past it.
    func noteEdit(in range: NSRange, replacementLength: Int, breakDelta: Int) {
        guard let start = visibleStart else { return }
        if NSMaxRange(range) <= start.offset {
            visibleStart = (
                start.offset - range.length + replacementLength, start.line + breakDelta
            )
        } else if range.location < start.offset {
            visibleStart = nil
        }
    }

    var width: CGFloat {
        let digitWidth = CodeFont.advance(of: "0", in: numberFont)
        return (Self.markWidth + CGFloat(digits) * digitWidth + 8).rounded(.up)
    }

    private static let markWidth: CGFloat = 16

    /// Sizes the gutter to the code font and the widest line number.
    /// - Returns: Whether the width changed.
    @discardableResult
    func fit(codeFontSize: CGFloat, lineCount: Int) -> Bool {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: max(9, (codeFontSize * 0.78).rounded()), weight: .regular)
        let neededDigits = max(2, String(max(lineCount, 1)).count)
        guard font != numberFont || neededDigits != digits else { return false }
        let before = width
        numberFont = font
        digits = neededDigits
        return width != before
    }

    func draw(in textView: NSTextView, dirtyRect: NSRect) {
        var previousLine: Int?
        for lane in visibleLanes(of: textView) {
            defer { previousLine = lane.line }
            guard lane.paragraph.intersects(dirtyRect) else { continue }
            drawCell(lane, showsNumber: lane.line != previousLine)
        }
    }

    /// One text paragraph: its first visual row, and every row it wraps to. TextKit also breaks
    /// paragraphs at characters the renderer keeps inside a line, so two lanes can share one.
    struct Lane {
        let line: Int
        let row: NSRect
        let paragraph: NSRect
    }

    /// Asks only the fragments in the viewport, so the cost follows the window's height.
    func visibleLanes(of textView: NSTextView) -> [Lane] {
        guard let manager = textView.textLayoutManager,
            let content = manager.textContentManager
        else { return [] }
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect
        let top = CGPoint(x: 0, y: max(0, visible.minY - origin.y))
        guard let first = manager.textLayoutFragment(for: top) else { return [] }
        let text = textView.textStorage?.mutableString ?? (textView.string as NSString)
        let documentStart = content.documentRange.location
        let firstOffset = content.offset(from: documentStart, to: first.rangeInElement.location)
        var previous = (offset: 0, line: 1)
        if let visibleStart, visibleStart.offset <= firstOffset { previous = visibleStart }
        previous = (
            firstOffset, CodeLines.line(atUTF16Offset: firstOffset, in: text, from: previous)
        )
        visibleStart = previous
        let width = width
        var result: [Lane] = []
        manager.enumerateTextLayoutFragments(from: first.rangeInElement.location) { fragment in
            let frame = fragment.layoutFragmentFrame
            let y = frame.minY + origin.y
            guard y <= visible.maxY else { return false }
            // Each lane counts `\n`s up to its own start, so it numbers the renderer's line.
            let offset = content.offset(from: documentStart, to: fragment.rangeInElement.location)
            let line = CodeLines.line(atUTF16Offset: offset, in: text, from: previous)
            previous = (offset, line)
            let rowHeight = fragment.textLineFragments.first?.typographicBounds.height
            result.append(
                Lane(
                    line: line,
                    row: NSRect(x: 0, y: y, width: width, height: rowHeight ?? frame.height),
                    paragraph: NSRect(x: 0, y: y, width: width, height: frame.height)))
            return true
        }
        return result
    }

    private func drawCell(_ lane: Lane, showsNumber: Bool) {
        let line = lane.line
        let cell = lane.row
        let isHighlighted = marks.contains(.highlight, line: line)
        if isHighlighted {
            // Every row a wrapped line takes, as the stage bands it.
            highlightTint.setFill()
            NSBezierPath(
                roundedRect: lane.paragraph.insetBy(dx: 3, dy: 0), xRadius: 3, yRadius: 3
            ).fill()
        }
        guard showsNumber else { return }
        let dimmed = focusesHighlighted && !marks.highlighted.isEmpty && !isHighlighted
        let number = NSAttributedString(
            string: "\(line)",
            attributes: [
                .font: numberFont,
                .foregroundColor: ink.withAlphaComponent(
                    isHighlighted ? 0.95 : dimmed ? 0.22 : 0.45),
            ])
        let size = number.size()
        number.draw(at: NSPoint(x: cell.maxX - 6 - size.width, y: cell.midY - size.height / 2))
        if marks.contains(.redact, line: line), let glyph = Self.redactGlyph(color: ink) {
            let side = min(cell.height, 11)
            glyph.draw(in: NSRect(x: 4, y: cell.midY - side / 2, width: side, height: side))
        }
    }

    private static func redactGlyph(color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(.init(paletteColors: [color.withAlphaComponent(0.8)]))
        return NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    // MARK: - Editing

    /// Opens the lane menu for the clicked line; `point` is in text view coordinates.
    func click(at point: NSPoint, with event: NSEvent, in textView: NSTextView) {
        guard
            let range = lines(
                at: point, extending: event.modifierFlags.contains(.shift),
                in: textView)
        else { return }
        menu(for: range).popUp(positioning: nil, at: point, in: textView)
    }

    /// The line under `point`, or the run from the last plain click when `extending`.
    func lines(at point: NSPoint, extending: Bool, in textView: NSTextView) -> ClosedRange<Int>? {
        guard
            let line = visibleLanes(of: textView).first(where: {
                $0.paragraph.minY <= point.y && point.y < $0.paragraph.maxY
            })?.line
        else { return nil }
        if extending, let anchorLine {
            return min(anchorLine, line)...max(anchorLine, line)
        }
        anchorLine = line
        return line...line
    }

    func menu(for range: ClosedRange<Int>) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(
            .sectionHeader(
                title: range.count == 1
                    ? String(localized: "Line \(range.lowerBound)")
                    : String(localized: "Lines \(LineHighlight.label(range))")))
        menu.addItem(
            item(
                String(localized: "Highlight"), id: "code-lane-highlight",
                isOn: marks.covers(range, with: .highlight), action: .toggle(.highlight, range)))
        menu.addItem(
            item(
                String(localized: "Redact"), id: "code-lane-redact",
                isOn: marks.covers(range, with: .redact), action: .toggle(.redact, range)))
        menu.addItem(
            item(
                String(
                    localized: "line-mark.none", defaultValue: "None",
                    comment: "Line-mark menu item that removes every mark from the line"),
                id: "code-lane-clear",
                isEnabled: marks.touches(range), action: .clear(range)))
        menu.addItem(.separator())
        menu.addItem(
            item(
                String(localized: "Focus highlighted"), id: "code-lane-focus",
                isOn: focusesHighlighted, isEnabled: !marks.highlighted.isEmpty,
                action: .toggleFocus))
        return menu
    }

    private func item(
        _ title: String, id: String, isOn: Bool = false, isEnabled: Bool = true,
        action: CodeLaneAction
    ) -> NSMenuItem {
        let handler = MenuHandler { [weak self] in self?.onAction?(action) }
        let item = NSMenuItem(
            title: title, action: #selector(MenuHandler.runAction), keyEquivalent: "")
        // The target is weak, so the item keeps its handler alive.
        item.representedObject = handler
        item.target = handler
        item.state = isOn ? NSControl.StateValue.on : .off
        item.isEnabled = isEnabled
        item.setAccessibilityIdentifier(id)
        return item
    }

    private final class MenuHandler: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func runAction() { run() }
    }
}

/// The actions a text selection offers: highlight or redact the lines it touches.
struct CodeSelectionActions: View {
    let lines: ClosedRange<Int>
    let marks: LineMarks
    let perform: (CodeLaneAction) -> Void

    var body: some View {
        HStack(spacing: VitrineTokens.Spacing.xs) {
            Button(highlightTitle) { perform(.toggle(.highlight, lines)) }
                .accessibilityIdentifier("code-selection-highlight")
            Divider().frame(height: 14)
            Button(
                marks.covers(lines, with: .redact)
                    ? String(localized: "Remove redaction") : String(localized: "Redact")
            ) { perform(.toggle(.redact, lines)) }
            .accessibilityIdentifier("code-selection-redact")
        }
        .buttonStyle(.borderless)
        .font(.system(size: VitrineTokens.FontSize.caption, weight: .medium))
        .padding(.horizontal, VitrineTokens.Spacing.sm)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(VitrineTokens.Line.border, lineWidth: Brand.Stroke.hairline)
                .allowsHitTesting(false)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("code-selection-actions")
    }

    private var highlightTitle: String {
        if marks.covers(lines, with: .highlight) { return String(localized: "Remove highlight") }
        return lines.count == 1
            ? String(localized: "Highlight line \(lines.lowerBound)")
            : String(localized: "Highlight lines \(LineHighlight.label(lines))")
    }
}

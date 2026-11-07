import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// Code text editor backed by `NSTextView` with live syntax highlighting:
/// adaptive debounced recolor (100–250 ms), monospaced font, Tab = 4 spaces, no autocorrect.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: Language
    var theme: Theme
    var fontName: String
    var fontSize: Double
    var fontLigatures: Bool
    var reindentOnPaste: Bool
    /// Called when a paste replaced the *entire* document (a select-all paste or a
    /// paste into an empty editor) — i.e. a new capture. It receives the pasted text and
    /// returns how to interpret it, so the document is tidied with the pasted language
    /// rather than the previous one. A mid-edit insert does not fire it.
    var onReplaceAllPaste: (String) -> LanguageDetector.Interpretation = {
        LanguageDetector.interpret($0)
    }
    /// Called on each user edit, so a draw tool or selected mark stops owning ⌘Z.
    var onUserEdit: () -> Void = {}
    var slideDividers = SlideDividerLayout()
    /// Hidden rather than removed, so it leaves the key-view loop and VoiceOver while
    /// keeping its text, undo stack and width.
    var isHidden = false
    /// The line marks the gutter and selection actions edit; absent outside an editor window.
    @Environment(AppSettings.self) private var settings: AppSettings?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // A `CodeTextView` (an `NSTextView` subclass) so a native ⌘V paste can be
        // intercepted for auto re-indent; the rest mirrors the standard
        // `NSTextView.scrollableTextView()` setup.
        let textView = CodeTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        // Empty documents retain the panel's glass and onboarding overlay.
        // Highlighting pairs nonempty syntax with its own theme background.
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: CodeTextView.baseInset, height: 12)
        textView.string = text
        textView.setAccessibilityIdentifier("code-editor-text-view")
        textView.setAccessibilityLabel("Code editor")
        scrollView.setAccessibilityIdentifier("code-editor-scroll-view")

        // After a native ⌘V paste, re-indent through the coordinator; the
        // coordinator checks the user's preference and uses the undo-aware edit cycle.
        textView.onPaste = { [weak textView] replacedEntireDocument in
            guard let textView else { return }
            let coordinator = context.coordinator
            if replacedEntireDocument {
                let intake = coordinator.parent.onReplaceAllPaste(textView.string)
                coordinator.replaceAfterPaste(
                    textView, with: intake.code, language: intake.language)
            } else {
                coordinator.reindentAfterPaste(textView)
            }
        }

        textView.laneGutter = context.coordinator.gutter

        context.coordinator.configureIfFontChanged(textView)
        context.coordinator.applyHighlight(to: textView)
        context.coordinator.syncLanes(textView, settings: settings)
        context.coordinator.refreshLanes(textView, recount: true)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.configureIfFontChanged(textView)
        if nsView.isHidden != isHidden { nsView.isHidden = isHidden }

        if textView.string != text {
            // External change (e.g. reopening a recent capture): sync + recolor now.
            // Typing undo recorded against the previous text would edit the new one.
            textView.string = text
            textView.undoManager?.removeAllActions()
            coordinator.gutter.documentReplaced()
            coordinator.applyHighlight(to: textView)
            coordinator.refreshLanes(textView, recount: true)
        } else if coordinator.styleChanged {
            // Theme/language/font changed: recolor now (text edits are debounced).
            coordinator.applyHighlight(to: textView)
        }
        if coordinator.appliedDividerRevision != slideDividers.revision {
            coordinator.appliedDividerRevision = slideDividers.revision
            (textView as? CodeTextView)?.install(slideDividers)
        }
        coordinator.syncLanes(textView, settings: settings)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.dismantle()
        guard let textView = nsView.documentView as? CodeTextView else { return }
        textView.delegate = nil
        textView.onPaste = nil
        coordinator.gutter.onAction = nil
        textView.onLineEdit = nil
        textView.undoManager?.removeAllActions()
        nsView.documentView = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        private let debouncer = Debouncer(interval: .milliseconds(100))
        private var isHighlighting = false

        private var appliedLanguage: Language?
        private var appliedTheme: Theme?
        private var appliedFontName: String?
        private var appliedFontSize: Double?
        private var appliedFontLigatures: Bool?
        private var appliedMode: HighlightMode?
        var appliedDividerRevision = 0
        let gutter = CodeLaneGutter()
        private var selectionBar: NSHostingView<CodeSelectionActions>?
        private var selectionBarContent: (lines: ClosedRange<Int>, marks: LineMarks)?
        private var performLaneAction: (CodeLaneAction) -> Void = { _ in }

        /// The inputs that decide the text view's font and tab stops.
        struct FontInputs: Equatable {
            let name: String
            let size: Double
            let ligatures: Bool
        }

        /// The font inputs ``configure(_:)`` last applied through
        /// ``configureIfFontChanged(_:)``.
        private var configuredFont: FontInputs?

        init(_ parent: CodeEditorView) { self.parent = parent }

        func dismantle() {
            debouncer.cancel()
        }

        private var font: NSFont {
            CodeFont.resolved(
                family: parent.fontName, size: parent.fontSize, ligatures: parent.fontLigatures)
        }

        /// True when the style (language/theme/font, including ligatures) differs
        /// from what was last applied.
        var styleChanged: Bool {
            appliedLanguage != parent.language
                || appliedTheme != parent.theme
                || appliedFontName != parent.fontName
                || appliedFontSize != parent.fontSize
                || appliedFontLigatures != parent.fontLigatures
        }

        /// Applies the font and tab stops when their inputs changed since the last time.
        ///
        /// Setting `NSTextView.font` applies the font across the whole text storage and lays
        /// the document out again, even when the font is the one already there. SwiftUI
        /// updates the representable on every keystroke and every style change, so
        /// configuring each time made every keystroke pay for the whole document. On 300
        /// lines in a Debug build that was 14 ms a keystroke; skipping it is 10 ms.
        /// - Returns: Whether the text view was configured.
        @discardableResult
        func configureIfFontChanged(_ textView: NSTextView) -> Bool {
            let inputs = FontInputs(
                name: parent.fontName, size: parent.fontSize, ligatures: parent.fontLigatures)
            guard inputs != configuredFont else { return false }
            configure(textView)
            configuredFont = inputs
            return true
        }

        /// Applies the monospaced font and 4-space tab stops.
        func configure(_ textView: NSTextView) {
            let font = self.font
            textView.font = font
            let spaceWidth = CodeFont.advance(of: " ", in: font)
            let style = NSMutableParagraphStyle()
            style.tabStops = []
            style.defaultTabInterval = max(spaceWidth * 4, 1)
            textView.defaultParagraphStyle = style
            textView.typingAttributes[.paragraphStyle] = style
            textView.typingAttributes[.font] = font
        }

        /// Recolors the whole document via Highlightr, preserving the selection.
        ///
        /// Highlighting never changes the *characters* — only their colors — so when the
        /// rendered text matches the storage's text (the normal case), the new attributes
        /// are applied **in place** over the existing characters rather than replacing the
        /// whole string. A full `setAttributedString` re-seats every character and forces
        /// the layout manager to regenerate all glyphs, which is what spiked on a 1–2k-line
        /// document; an attribute-only pass (`beginEditing`/`endEditing`) reuses the glyphs
        /// and only re-processes the changed attributes . The rare case where the
        /// rendered text differs (e.g. a custom theme trims a trailing newline) falls back
        /// to the selection-preserving full replace.
        func applyHighlight(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isHighlighting = true
            defer { isHighlighting = false }

            applySurface(to: textView)

            let mode = HighlightPolicy.mode(for: textView.string, language: parent.language)
            let attributed = HighlightManager.shared.attributedString(
                for: textView.string, language: parent.language, theme: parent.theme, font: font)
            let paragraph = textView.defaultParagraphStyle ?? NSParagraphStyle.default

            if attributed.string == storage.string {
                // Same characters: recolor in place. Selection is character-index based, so
                // it survives untouched; no save/restore needed.
                let full = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                attributed.enumerateAttributes(
                    in: NSRange(location: 0, length: attributed.length)
                ) { attributes, range, _ in
                    storage.setAttributes(attributes, range: range)
                }
                storage.addAttribute(.paragraphStyle, value: paragraph, range: full)
                storage.endEditing()
            } else {
                // Characters differ from the render: fall back to a full, selection-
                // preserving replace.
                let selection = textView.selectedRanges
                let mutable = NSMutableAttributedString(attributedString: attributed)
                mutable.addAttribute(
                    .paragraphStyle, value: paragraph,
                    range: NSRange(location: 0, length: mutable.length))
                storage.setAttributedString(mutable)
                textView.selectedRanges = selection
            }

            if mode.usesPlainTextFallback, attributed.length > 0,
                let foreground = attributed.attribute(
                    .foregroundColor, at: 0, effectiveRange: nil)
            {
                // New keystrokes in large-document mode must inherit the fallback color rather
                // than whichever syntax token happened to sit at the caret before the transition.
                textView.typingAttributes[.foregroundColor] = foreground
            }

            appliedLanguage = parent.language
            appliedTheme = parent.theme
            appliedFontName = parent.fontName
            appliedFontSize = parent.fontSize
            appliedFontLigatures = parent.fontLigatures
            appliedMode = mode
        }

        /// Syntax colors belong to the selected theme, not the app's light/dark chrome.
        /// Keep their background paired, including custom palette updates.
        func applySurface(to textView: NSTextView) {
            let hasContent = !textView.string.isEmpty
            let background = HighlightManager.shared.backgroundColor(for: parent.theme)
            textView.drawsBackground = hasContent
            textView.backgroundColor = NSColor(background)
            textView.enclosingScrollView?.drawsBackground = hasContent
            textView.enclosingScrollView?.backgroundColor = NSColor(background)
            textView.insertionPointColor =
                hasContent
                ? NSColor(VitrineTokens.Text.readable(on: background)) : .textColor
            (textView as? CodeTextView)?.slideDividerColor = textView.insertionPointColor
            gutter.ink = textView.insertionPointColor
            gutter.highlightTint = NSColor(
                HighlightManager.shared.lineHighlightColor(for: parent.theme))
            (textView as? CodeTextView)?.showsGutter = hasContent && lanesApply
            textView.setNeedsDisplay(textView.visibleRect)
        }

        /// A terminal capture redacts rows of its reconstructed screen, not transcript lines,
        /// so a line number in the editor would point at a different row.
        private var lanesApply: Bool { parent.language != .terminal }

        /// Pushes the current marks into the gutter and the selection actions.
        func syncLanes(_ textView: NSTextView, settings: AppSettings?) {
            let codeView = textView as? CodeTextView
            let style = settings?.style
            let marks = style?.lineMarks ?? LineMarks()
            let focus = style?.focusHighlightedLines ?? false
            let enabled = settings != nil && lanesApply
            let changed =
                marks != gutter.marks || focus != gutter.focusesHighlighted
                || enabled != (gutter.onAction != nil)
            gutter.marks = marks
            gutter.focusesHighlighted = focus
            performLaneAction = { [weak settings, weak textView] action in
                guard let settings else { return }
                Self.apply(action, to: settings, undoManager: textView?.undoManager)
            }
            gutter.onAction = enabled ? { [weak self] in self?.performLaneAction($0) } : nil
            // Only while there are marks to move: the edit's line costs a count from the top.
            codeView?.onLineEdit =
                enabled && !marks.isEmpty
                ? { [weak settings] edit in settings?.style.shiftLineMarks(for: edit) } : nil
            let resized = gutter.fit(
                codeFontSize: parent.fontSize, lineCount: codeView?.lineCount ?? 1)
            if resized { codeView?.updateGutterInset() }
            if changed || resized {
                codeView?.setGutterNeedsDisplay()
                refreshSelectionBar(textView)
            }
        }

        /// Applies a gutter or selection edit as one undoable step.
        static func apply(
            _ action: CodeLaneAction, to settings: AppSettings, undoManager: UndoManager?
        ) {
            var updated = settings.style
            updated.apply(action)
            guard
                updated.lineMarks != settings.style.lineMarks
                    || updated.focusHighlightedLines != settings.style.focusHighlightedLines
            else { return }
            setLineMarks(from: updated, on: settings, undoManager: undoManager)
        }

        private static func setLineMarks(
            from source: SnapshotConfig, on settings: AppSettings, undoManager: UndoManager?
        ) {
            let previous = settings.style
            undoManager?.registerUndo(withTarget: settings) { settings in
                setLineMarks(from: previous, on: settings, undoManager: undoManager)
            }
            undoManager?.setActionName(String(localized: "Mark Lines"))
            var style = previous
            style.highlightedLineRanges = source.highlightedLineRanges
            style.redactedLineRanges = source.redactedLineRanges
            style.focusHighlightedLines = source.focusHighlightedLines
            settings.style = style
        }

        /// Runs per text change; the text view keeps the line count, so this never walks
        /// the document unless `recount` asks it to.
        func refreshLanes(_ textView: NSTextView, recount: Bool = false) {
            guard let codeView = textView as? CodeTextView else { return }
            if recount { codeView.recountLines() }
            if gutter.fit(codeFontSize: parent.fontSize, lineCount: codeView.lineCount) {
                codeView.updateGutterInset()
            }
            refreshSelectionBar(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            refreshSelectionBar(textView)
        }

        /// Shows the selection actions while a selection spans text, pinned to the
        /// pane's bottom edge.
        private func refreshSelectionBar(_ textView: NSTextView) {
            let selection = textView.selectedRange()
            guard let scrollView = textView.enclosingScrollView else { return }
            // An empty selection, the case on every keystroke, never reads the text.
            let lines =
                gutter.onAction == nil || selection.length == 0
                ? nil
                : textView.textStorage.flatMap {
                    CodeLines.lines(of: selection, in: $0.mutableString)
                }
            guard let lines else {
                selectionBar?.isHidden = true
                selectionBarContent = nil
                return
            }
            if let selectionBarContent, selectionBarContent == (lines, gutter.marks) {
                return
            }
            selectionBarContent = (lines, gutter.marks)
            let content = CodeSelectionActions(
                lines: lines, marks: gutter.marks,
                perform: { [weak self] in self?.performLaneAction($0) })
            let bar = selectionBar ?? NSHostingView(rootView: content)
            bar.rootView = content
            bar.isHidden = false
            if selectionBar == nil {
                // Framed by hand: the scroll view tiles its subviews itself.
                bar.sizingOptions = [.intrinsicContentSize]
                bar.autoresizingMask = [
                    .minXMargin, scrollView.isFlipped ? .minYMargin : .maxYMargin,
                ]
                scrollView.addSubview(bar)
                selectionBar = bar
            }
            let size = bar.intrinsicContentSize
            let bounds = scrollView.bounds
            bar.frame = NSRect(
                x: bounds.maxX - size.width - 10,
                y: scrollView.isFlipped ? bounds.maxY - size.height - 10 : bounds.minY + 10,
                width: size.width, height: size.height)
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onUserEdit()
            // Recoloring is debounced; the surface must not lag an empty/nonempty flip.
            if textView.drawsBackground == textView.string.isEmpty {
                applySurface(to: textView)
            }
            refreshLanes(textView)
            let mode = HighlightPolicy.mode(for: textView.string, language: parent.language)
            if mode.usesPlainTextFallback {
                debouncer.cancel()
                // Clear existing token colors exactly once when crossing into large-document
                // mode. Subsequent keystrokes inherit the configured plain typing attributes,
                // avoiding a whole-document attribute pass for every edit.
                if appliedMode?.usesPlainTextFallback != true {
                    applyHighlight(to: textView)
                }
                return
            }
            debouncer.schedule(after: HighlightPolicy.editorDebounce(for: textView.string)) {
                [weak self, weak textView] in
                guard let self, let textView else { return }
                self.applyHighlight(to: textView)
                self.refreshLanes(textView, recount: true)
            }
        }

        /// Re-indents the whole document after a paste, when the user's preference is on,
        /// through the text view's native edit cycle so the change lands on the undo stack
        /// (⌘Z reverts it) and `textDidChange` writes it back to the binding. A
        /// no-op (already tidy, or a `.leaveAlone` language) registers no edit.
        ///
        /// The parent view supplies the live app-wide preference from its composition
        /// root; tests can override it explicitly without touching shared defaults.
        func reindentAfterPaste(_ textView: NSTextView, isEnabled: Bool? = nil) {
            guard isEnabled ?? parent.reindentOnPaste else { return }
            replaceWholeText(
                textView, with: CodeFormatter.tidy(textView.string, language: parent.language))
        }

        /// A paste that replaced the whole document becomes `code` (a Markdown fence
        /// unwrapped), tidied with the pasted `language` when re-indent is on.
        func replaceAfterPaste(
            _ textView: NSTextView, with code: String, language: Language,
            isEnabled: Bool? = nil
        ) {
            let tidied =
                isEnabled ?? parent.reindentOnPaste
                ? CodeFormatter.tidy(code, language: language) : code
            replaceWholeText(textView, with: tidied)
        }

        private func replaceWholeText(_ textView: NSTextView, with replacement: String) {
            let original = textView.string
            guard replacement != original else { return }
            let whole = NSRange(location: 0, length: (original as NSString).length)
            guard textView.shouldChangeText(in: whole, replacementString: replacement) else {
                return
            }
            textView.textStorage?.replaceCharacters(in: whole, with: replacement)
            textView.didChangeText()  // fires the delegate → writes back to the binding
            textView.undoManager?.setActionName(String(localized: "Format Code"))
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }
    }
}

/// `NSTextView` subclass that notifies after a paste so the editor can re-indent the
/// result. Paste is the one mutation with no `NSTextViewDelegate` hook, so it
/// is overridden here; every other edit flows through the coordinator's delegate
/// callbacks. `super.paste` honors `isRichText = false`, so it inserts plain text.
final class CodeTextView: NSTextView {
    /// Invoked right after a paste lands so the coordinator can tidy the indentation
    /// when the user's preference is on. The flag reports whether the paste replaced
    /// the *entire* document (a select-all paste, or a paste into an empty editor),
    /// which the editor treats as a new capture.
    var onPaste: ((_ replacedEntireDocument: Bool) -> Void)?

    /// Painted under the text: the storage, the selection and undo never see them.
    var slideDividers: [SlideDivider] = [] {
        didSet {
            guard slideDividers != oldValue else { return }
            dividersByOffset = Dictionary(
                slideDividers.map { ($0.offset, $0) }, uniquingKeysWith: { first, _ in first })
            setNeedsDisplay(visibleRect)
        }
    }
    var slideDividerColor: NSColor = .tertiaryLabelColor
    private var dividersByOffset: [Int: SlideDivider] = [:]

    static let baseInset: CGFloat = 14
    /// How much of the base inset the gutter reuses, so the code sits a short gap after it.
    static let gutterOverlap: CGFloat = 6
    var laneGutter: CodeLaneGutter? { didSet { updateGutterInset() } }
    /// Set while there are marks to move, and told about each edit that adds or removes a
    /// line break, before the edit lands.
    var onLineEdit: ((LineEdit) -> Void)?
    /// Kept in step by each edit, so a keystroke never recounts the document.
    private(set) var lineCount = 1

    func recountLines() {
        let text = textStorage?.mutableString ?? (string as NSString)
        lineCount = CodeLines.breaks(in: text, range: NSRange(location: 0, length: text.length)) + 1
    }

    /// The visible slice of the gutter, which is all a keystroke or a mark change repaints.
    func setGutterNeedsDisplay() {
        guard showsGutter else { return }
        let visible = visibleRect
        setNeedsDisplay(
            NSRect(
                x: visible.minX, y: visible.minY, width: textContainerOrigin.x,
                height: visible.height))
    }

    /// The gutter and selection actions can edit marks: off for terminal captures.
    var laneActionsEnabled: Bool { showsGutter && laneGutter?.onAction != nil }

    private var selectedLines: ClosedRange<Int>? {
        guard laneActionsEnabled, let text = textStorage?.mutableString else { return nil }
        return CodeLines.lines(of: selectedRange(), in: text)
    }

    @objc func highlightSelectedLines(_ sender: Any?) { markSelectedLines(.highlight) }
    @objc func redactSelectedLines(_ sender: Any?) { markSelectedLines(.redact) }

    private func markSelectedLines(_ mark: LineMark) {
        guard let lines = selectedLines else { return }
        laneGutter?.onAction?(.toggle(mark, lines))
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let mark: LineMark
        switch menuItem.action {
        case #selector(highlightSelectedLines(_:)): mark = .highlight
        case #selector(redactSelectedLines(_:)): mark = .redact
        default: return super.validateMenuItem(menuItem)
        }
        guard let lines = selectedLines, let laneGutter else { return false }
        menuItem.state = laneGutter.marks.covers(lines, with: mark) ? .on : .off
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        guard laneActionsEnabled, let menu else { return menu }
        menu.insertItem(.separator(), at: 0)
        for (title, action, id) in Self.selectionCommands.reversed() {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.setAccessibilityIdentifier("code-context-\(id)")
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    /// The selection commands, shared by the context menu, the Edit menu and VoiceOver.
    static var selectionCommands: [(title: String, action: Selector, id: String)] {
        [
            (
                String(localized: "Highlight Selected Lines"),
                #selector(highlightSelectedLines(_:)), "highlight-selected-lines"
            ),
            (
                String(localized: "Redact Selected Lines"),
                #selector(redactSelectedLines(_:)), "redact-selected-lines"
            ),
        ]
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        let inherited = super.accessibilityCustomActions() ?? []
        guard selectedLines != nil else { return inherited }
        return inherited + [
            NSAccessibilityCustomAction(name: Self.selectionCommands[0].title) { [weak self] in
                self?.markSelectedLines(.highlight)
                return true
            },
            NSAccessibilityCustomAction(name: Self.selectionCommands[1].title) { [weak self] in
                self?.markSelectedLines(.redact)
                return true
            },
        ]
    }
    var showsGutter = false { didSet { if showsGutter != oldValue { updateGutterInset() } } }
    /// Half the gutter: the inset adds it on both sides and the origin once more on the left,
    /// so the gutter takes room from the code's left edge only.
    private var gutterShift: CGFloat = 0

    func updateGutterInset() {
        let gutter = showsGutter ? laneGutter?.width ?? 0 : 0
        // Whole points: the text view rounds a fractional origin.
        let shift = (max(0, gutter - Self.gutterOverlap) / 2).rounded(.up)
        guard shift != gutterShift else { return }
        gutterShift = shift
        textContainerInset = NSSize(
            width: Self.baseInset + shift, height: textContainerInset.height)
        invalidateTextContainerOrigin()
        setNeedsDisplay(visibleRect)
    }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x + gutterShift, y: origin.y)
    }

    private func isInGutter(_ event: NSEvent) -> Bool {
        showsGutter && convert(event.locationInWindow, from: nil).x < textContainerOrigin.x - 2
    }

    override func mouseDown(with event: NSEvent) {
        if isInGutter(event), let laneGutter, laneGutter.onAction != nil {
            laneGutter.click(
                at: convert(event.locationInWindow, from: nil), with: event, in: self)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isInGutter(event) else { return super.mouseMoved(with: event) }
        NSCursor.arrow.set()
    }

    /// A split that finished after further typing is older than the shifted copy, so the copy
    /// stays and the settle that typing already scheduled replaces it.
    func install(_ layout: SlideDividerLayout) {
        if let source = layout.source, source != string { return }
        slideDividers = layout.dividers
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if showsGutter { laneGutter?.draw(in: self, dirtyRect: rect) }
        guard !dividersByOffset.isEmpty else { return }
        drawSlideDividers()
    }

    /// Asks only the laid-out fragments in the viewport, so the cost follows the window's
    /// height and not the document's.
    private func drawSlideDividers() {
        guard let manager = textLayoutManager, let content = manager.textContentManager,
            let viewport = manager.textViewportLayoutController.viewportRange
        else { return }
        let top = textContainerOrigin.y
        let start = content.documentRange.location
        var found: [(divider: SlideDivider, y: CGFloat)] = []
        manager.enumerateTextLayoutFragments(from: viewport.location) { fragment in
            let location = fragment.rangeInElement.location
            guard location.compare(viewport.endLocation) == .orderedAscending else { return false }
            if let divider = dividersByOffset[content.offset(from: start, to: location)] {
                found.append((divider, (fragment.layoutFragmentFrame.minY + top).rounded()))
            }
            return true
        }
        // Outside the enumeration, so labels aren't measured while it walks the layout.
        for item in found { drawSlideDivider(item.divider, atY: item.y) }
    }

    private func drawSlideDivider(_ divider: SlideDivider, atY y: CGFloat) {
        let label = NSAttributedString(
            string: divider.isSingleLine
                ? String(localized: "slide \(divider.slideNumber) · line \(divider.lineRange)")
                : String(localized: "slide \(divider.slideNumber) · lines \(divider.lineRange)"),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: slideDividerColor.withAlphaComponent(0.75),
            ])
        let size = label.size()
        let leading = textContainerOrigin.x
        slideDividerColor.withAlphaComponent(0.45).setFill()
        NSRect(x: leading, y: y, width: bounds.width - leading - Self.baseInset, height: 1).fill()
        // Above the rule: the end of a slide's last line is the likeliest empty spot.
        label.draw(at: NSPoint(x: bounds.maxX - Self.baseInset - size.width, y: y - size.height))
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: range, replacementString: replacementString) else {
            return false
        }
        if !slideDividers.isEmpty, let replacementString {
            slideDividers = slideDividers.compactMap {
                $0.shifted(replacing: range, with: replacementString)
            }
        }
        if let replacementString { noteLineEdit(in: range, replacement: replacementString) }
        return true
    }

    /// Keeps the line count and the gutter's cached position in step with an edit, and
    /// tells `onLineEdit` how its line breaks moved.
    private func noteLineEdit(in range: NSRange, replacement: String) {
        guard let text = textStorage?.mutableString else { return }
        let inserted = replacement as NSString
        let removedBreaks = CodeLines.breaks(in: text, range: range)
        let insertedBreaks = CodeLines.breaks(
            in: inserted, range: NSRange(location: 0, length: inserted.length))
        lineCount += insertedBreaks - removedBreaks
        // A whole-document replacement is a new capture, whose marks stay as they are.
        if range.location == 0, range.length == text.length {
            laneGutter?.documentReplaced()
            return
        }
        laneGutter?.noteEdit(
            in: range, replacementLength: inserted.length,
            breakDelta: insertedBreaks - removedBreaks)
        guard removedBreaks + insertedBreaks > 0, let onLineEdit else { return }
        let end = NSMaxRange(range)
        let endsAtLineEnd =
            end == text.length || text.character(at: end) == 0x0A
            || (text.character(at: end) == 0x0D && end + 1 < text.length
                && text.character(at: end + 1) == 0x0A)
        onLineEdit(
            LineEdit(
                line: CodeLines.line(atUTF16Offset: range.location, in: text),
                removedBreaks: removedBreaks, insertedBreaks: insertedBreaks,
                startsAtLineStart: range.location == 0
                    || text.character(at: range.location - 1) == 0x0A,
                endsAtLineEnd: endsAtLineEnd))
    }

    override func didChangeText() {
        super.didChangeText()
        // A new line moves every divider and line number below it, past the rect the edit
        // redraws.
        if !slideDividers.isEmpty {
            setNeedsDisplay(visibleRect)
        } else {
            setGutterNeedsDisplay()
        }
    }

    override func paste(_ sender: Any?) {
        // Measure the replacement target *before* the paste mutates the text.
        let lengthBefore = (string as NSString).length
        let selection = selectedRange()
        let replacedEntireDocument =
            lengthBefore == 0 || (selection.location == 0 && selection.length == lengthBefore)
        super.paste(sender)
        onPaste?(replacedEntireDocument)
    }
}

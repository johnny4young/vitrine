import AppKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Carousel filmstrip and slide dividers")
struct CarouselFilmstripTests {
    private final class RenderLog {
        var configs: [SnapshotConfig] = []
    }

    private static func pixel() -> CGImage? {
        CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    private func model(
        _ log: RenderLog, quietWindow: Duration = .zero, frameGap: Duration = .zero
    ) -> CarouselFilmstripModel {
        CarouselFilmstripModel(quietWindow: quietWindow, frameGap: frameGap) { config, _, _ in
            log.configs.append(config)
            return Self.pixel()
        }
    }

    private func document(lines: Int) -> String {
        (1...lines).map { "let value\($0) = \($0)" }.joined(separator: "\n")
    }

    private func input(
        _ base: SnapshotConfig, split: CarouselSplit = CarouselSplit(linesPerSlide: 4),
        cues: CarouselPaginator.Cues = .none
    ) -> CarouselFilmstripModel.Input {
        CarouselFilmstripModel.Input(
            base: base, slides: split.slides(of: base.code), cues: cues, profile: .sRGB)
    }

    // MARK: - One split

    @Test func eachDividerOpensTheSlideTheExportWillWrite() {
        let split = CarouselSplit(linesPerSlide: 4)
        for code in [
            document(lines: 18),
            (1...18).map { "línea 👩‍💻 \($0)" }.joined(separator: "\r\n"),
            (1...18).map { $0 % 5 == 0 ? "" : "l\($0)" }.joined(separator: "\n"),
        ] {
            let slides = split.slides(of: code)
            let dividers = CarouselPaginator.dividers(for: slides, in: code)
            #expect(dividers.count == slides.count - 1)
            for (divider, (index, slide)) in zip(dividers, slides.enumerated().dropFirst()) {
                let opened = (code as NSString).substring(
                    with: NSRange(location: divider.offset, length: slide.text.utf16.count))
                #expect(opened == slide.text)
                #expect(divider.slideNumber == index + 1)
                #expect(divider.lineRange == slide.lineRange)
            }
        }
    }

    @Test func aLoneSlideHasNoDivider() {
        let code = document(lines: 3)
        #expect(CarouselPaginator.dividers(for: CarouselSplit().slides(of: code), in: code).isEmpty)
    }

    @Test func outcomeOffTheMainActorMatchesTheSplit() async {
        let code = document(lines: 40)
        let split = CarouselSplit(linesPerSlide: 7, prefersBlankLineBreaks: false)
        let outcome = await split.outcome(of: code)
        #expect(outcome.slides == split.slides(of: code))
        let dividers = await split.dividers(in: code)
        #expect(dividers == CarouselPaginator.dividers(for: outcome.slides, in: code))
    }

    // MARK: - Short tail

    @Test func aBalancedSplitHasNoShortTail() {
        #expect(!CarouselSplit(linesPerSlide: 8).outcome(document(lines: 27)).hasShortTail)
    }

    @Test func aTailOfMostlyBlankRowsIsShort() {
        // Two slides by count, and the second shows one line of its own.
        let code = document(lines: 8) + "\nlast\n\n\n\n\n\n\n"
        let outcome = CarouselSplit(linesPerSlide: 8, prefersBlankLineBreaks: false).outcome(code)
        #expect(outcome.slides.count == 2)
        #expect(outcome.hasShortTail)
    }

    @Test func aThinTailIsShortInACRLFDocumentToo() {
        let lines =
            (1...8).map { "let value\($0) = \($0)" } + ["last"] + Array(repeating: "", count: 6)
        let split = CarouselSplit(linesPerSlide: 8, prefersBlankLineBreaks: false)
        let outcome = split.outcome(lines.joined(separator: "\r\n"))
        #expect(outcome.slides.count == 2)
        #expect(outcome.hasShortTail)
        #expect(
            !split.outcome(document(lines: 16).replacingOccurrences(of: "\n", with: "\r\n"))
                .hasShortTail)
    }

    @Test func aLoneSlideIsNeverShort() {
        #expect(!CarouselPaginator.hasShortTail(CarouselSplit().slides(of: "only")))
    }

    // MARK: - Slide size

    @Test func theSizeLabelStatesThePixels() {
        #expect(
            CarouselPaginator.slideSizeLabel(CGSize(width: 1920, height: 1080)) == "1920 × 1080")
    }

    // MARK: - Tiles

    @Test func tilesRenderTheConfigTheExportRenders() async {
        let log = RenderLog()
        let model = model(log)
        var base = SnapshotConfig()
        base.code = document(lines: 12)
        base.redactedLineRanges = [6...6]
        base.highlightedLineRanges = [2...2]
        let cues = CarouselPaginator.Cues(
            lineNumbers: .continuing, showsPageBadge: true, showsContinuation: true,
            continuationLabel: "→")
        let input = input(base, cues: cues)
        model.visible = [0, 1]

        await model.refresh(input)

        let fontSize = CarouselPaginator.fittedFontSize(
            base, slides: input.slides, cues: cues, size: .linkedIn)
        #expect(
            log.configs
                == [0, 1].map {
                    CarouselPaginator.slideConfig(
                        base, slide: input.slides[$0], at: $0, of: input.slides.count, cues: cues,
                        fontSize: fontSize)
                })
        // Line 6 is the second row of the second slide, and only that slide hides it.
        #expect(log.configs[0].redactedLineRanges.isEmpty)
        #expect(log.configs[1].redactedLineRanges == [2...2])
        #expect(model.images.keys.sorted() == [0, 1])
    }

    @Test func aRedactedRowLeavesNoTraceInATile() throws {
        func tile(_ secret: String) throws -> Data {
            var base = SnapshotConfig()
            base.code = "let a = 1\nlet s = \"\(secret)\"\nlet b = 2\nlet c = 3"
            base.redactedLineRanges = [2...2]
            let slide = try #require(CarouselSplit(linesPerSlide: 4).slides(of: base.code).first)
            let config = CarouselPaginator.slideConfig(
                base, slide: slide, at: 0, of: 1, cues: .none)
            let image = try #require(CarouselFilmstripModel.renderTile(config, profile: .sRGB))
            let provider = try #require(image.dataProvider?.data)
            return provider as Data
        }
        #expect(try tile("hunter2-hunter2") == tile("swordfish-other"))
    }

    @Test func aTileIsTheSlideFrameAtTileScale() throws {
        var config = SnapshotConfig()
        config.code = "let a = 1"
        let image = try #require(CarouselFilmstripModel.renderTile(config, profile: .sRGB))
        #expect(abs(CGFloat(image.width) - 2 * CarouselFilmstripModel.tileSize.width) <= 1)
        #expect(abs(CGFloat(image.height) - 2 * CarouselFilmstripModel.tileSize.height) <= 1)
    }

    @Test func onlyVisibleTilesRenderHoweverLongTheDocument() async {
        let log = RenderLog()
        let model = model(log)
        var base = SnapshotConfig()
        base.code = document(lines: 8_000)
        model.visible = [100, 101, 102, 900_000]

        await model.refresh(input(base))

        #expect(log.configs.count == 3)
        #expect(model.images.keys.sorted() == [100, 101, 102])

        model.visible = Set(0..<500)
        await model.refresh(input(base))
        #expect(model.images.count == CarouselFilmstripModel.maximumLiveTiles)
    }

    @Test func aTileScrolledAwayIsReleased() async {
        let log = RenderLog()
        let model = model(log)
        var base = SnapshotConfig()
        base.code = document(lines: 40)
        model.visible = [0]
        await model.refresh(input(base))
        model.visible = [5]
        await model.refresh(input(base))
        #expect(model.images.keys.sorted() == [5])
    }

    @Test func anUnchangedInputRendersNothingNew() async {
        let log = RenderLog()
        let model = model(log)
        var base = SnapshotConfig()
        base.code = document(lines: 12)
        model.visible = [0, 1, 2]
        await model.refresh(input(base))
        let first = log.configs.count
        await model.refresh(input(base))
        #expect(log.configs.count == first)
    }

    @Test func aSettingChangeRendersAgain() async {
        let log = RenderLog()
        let model = model(log)
        var base = SnapshotConfig()
        base.code = document(lines: 12)
        model.visible = [0]
        await model.refresh(input(base))
        base.showLineNumbers.toggle()
        await model.refresh(input(base))
        #expect(
            log.configs.map(\.showLineNumbers) == [!base.showLineNumbers, base.showLineNumbers])
    }

    @Test func aPassCancelledInTheQuietWindowRendersNothing() async {
        let log = RenderLog()
        let model = model(log, quietWindow: .seconds(30))
        var base = SnapshotConfig()
        base.code = document(lines: 12)
        model.visible = [0]
        let next = input(base)
        let pass = Task { await model.refresh(next) }
        await Task.yield()
        pass.cancel()
        await pass.value
        #expect(log.configs.isEmpty)
    }

    @Test func aHiddenRowDropsTheOldTileAtOnce() async {
        let log = RenderLog()
        let model = model(log, quietWindow: .milliseconds(150))
        var base = SnapshotConfig()
        base.code = document(lines: 12)
        model.visible = [0]
        await model.refresh(input(base))
        #expect(model.images[0] != nil)

        base.redactedLineRanges = [1...1]
        let next = input(base)
        let pass = Task { await model.refresh(next) }
        await Task.yield()
        #expect(model.images[0] == nil, "An old image can't outlast the row hidden from it")
        await pass.value
        #expect(model.images[0] != nil)
    }

    @Test func cancellingStopsThePass() async {
        let log = RenderLog()
        let model = model(log, quietWindow: .zero, frameGap: .seconds(30))
        var base = SnapshotConfig()
        base.code = document(lines: 40)
        model.visible = [0, 1, 2, 3]
        let next = input(base)
        let pass = Task { await model.refresh(next) }
        while log.configs.isEmpty { await Task.yield() }
        pass.cancel()
        await pass.value
        #expect(log.configs.count == 1)
    }

    @Test func aSlideOverTheLimitIsNotRendered() async {
        let log = RenderLog()
        let model = model(log)
        var base = SnapshotConfig()
        base.code = String(repeating: "x", count: CarouselPaginator.Slide.maximumPreviewBytes + 1)
        model.visible = [0]
        await model.refresh(input(base))
        #expect(log.configs.isEmpty)
        #expect(model.images.isEmpty)
    }

    @Test func theEstimateSamplesTheFirstSlideItCanRender() async {
        let long = CarouselPaginator.Slide(
            text: String(repeating: "x", count: CarouselPaginator.Slide.maximumPreviewBytes + 1),
            firstLine: 1, lineCount: 1)
        let short = CarouselPaginator.Slide(text: "let a = 1", firstLine: 2, lineCount: 1)
        let estimate = await ExportManager.estimatedCarouselBytes(
            SnapshotConfig(), slides: [long, short], cues: .none)
        #expect(estimate != nil)
    }

    @Test func theEstimateSkipsASlideTheFilmstripWouldNotRender() async {
        let slide = CarouselPaginator.Slide(
            text: String(repeating: "x", count: CarouselPaginator.Slide.maximumPreviewBytes + 1),
            firstLine: 1, lineCount: 1)
        let estimate = await ExportManager.estimatedCarouselBytes(
            SnapshotConfig(), slides: [slide], cues: .none)
        #expect(estimate == nil)
    }

    // MARK: - Live reload

    @Test func slidesOfAnOlderDocumentNeverMeetTheNewMarks() async {
        let old = "let a = 1\nlet secret = \"hunter2\"\nlet b = 2\nlet c = 3\nlet d = 4"
        let new = "// header\n" + old
        let outcome = CarouselPaginator.Outcome(split: CarouselSplit(linesPerSlide: 4), code: old)

        // The reload hides the secret on its new row, while the split still holds the old text.
        var base = SnapshotConfig()
        base.code = new
        base.redactedLineRanges = [3...3]
        let log = RenderLog()
        let model = model(log)
        model.visible = [0, 1]
        await model.refresh(
            CarouselFilmstripModel.Input(
                base: base, slides: outcome.slides(for: base.code), cues: .none, profile: .sRGB))
        #expect(log.configs.isEmpty)

        let settled = CarouselPaginator.Outcome(split: outcome.split, code: new)
        await model.refresh(
            CarouselFilmstripModel.Input(
                base: base, slides: settled.slides(for: base.code), cues: .none, profile: .sRGB))
        #expect(log.configs.first?.redactedLineRanges == [3...3])
    }

    // MARK: - The rule

    @Test func aRefusedCaptureHasNothingToSplit() {
        var style = SnapshotConfig()
        style.code = "let a = 1"
        #expect(CarouselPaginator.splittableCode(of: style) == style.code)
        style.language = .terminal
        #expect(CarouselPaginator.splittableCode(of: style).isEmpty)
        style.language = .swift
        style.annotations = [Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))]
        #expect(CarouselPaginator.splittableCode(of: style).isEmpty)
    }

    @Test func theRuleNamesTerminalAndBlurCaptures() {
        var style = SnapshotConfig()
        #expect(EditorView.carouselRule(for: style) == nil)
        style.language = .terminal
        let terminal = EditorView.carouselRule(for: style)
        #expect(terminal != nil)
        style.language = .swift
        style.annotations = [Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))]
        let blur = EditorView.carouselRule(for: style)
        #expect(blur != nil)
        #expect(blur != terminal)
    }

    @Test func onlyPROOpensTheSheetOnARefusedCapture() {
        func opens(_ style: SnapshotConfig, content: Bool = true, unlocked: Bool) -> Bool {
            EditorView.carouselCanOpen(style, hasRenderableContent: content, isUnlocked: unlocked)
        }
        var style = SnapshotConfig()
        #expect(opens(style, unlocked: false))
        #expect(opens(style, unlocked: true))
        #expect(!opens(style, content: false, unlocked: true))
        style.language = .terminal
        #expect(!opens(style, unlocked: false))
        #expect(opens(style, unlocked: true))
        style.language = .swift
        style.foregroundImage = ImageReference(fileName: "image.png")
        #expect(!opens(style, unlocked: true))
    }

    // MARK: - Divider source

    @Test func dividersFollowOnlySettledTextOfAnAcceptedCapture() {
        let model = CarouselSplitModel()
        let thumbnails = PresetThumbnailModel()
        thumbnails.stagedCode = "code"
        thumbnails.stagedGeneration = 3
        func source(
            _ style: SnapshotConfig = SnapshotConfig(), unlocked: Bool = true, generation: Int = 3
        ) -> String? {
            model.dividerSource(
                style: style, isUnlocked: unlocked, thumbnails: thumbnails,
                documentGeneration: generation)
        }

        #expect(source() == nil, "Off by default")
        model.showsDividers = true
        #expect(source() == "code")
        #expect(source(unlocked: false) == nil)
        #expect(source(generation: 4) == nil, "Text of a replaced document")
        var style = SnapshotConfig()
        style.language = .terminal
        #expect(source(style) == nil)
        style.language = .swift
        style.annotations = [Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))]
        #expect(source(style) == nil)
        style.annotations = []
        style.foregroundImage = ImageReference(fileName: "image.png")
        #expect(source(style) == nil)
    }

    @Test func refreshingWithoutASourceClearsTheDividers() async {
        let model = CarouselSplitModel()
        model.split.linesPerSlide = 4
        await model.refreshDividers(code: document(lines: 12))
        #expect(model.dividerLayout.dividers.map(\.slideNumber) == [2, 3])
        #expect(model.dividerLayout.source == document(lines: 12))
        await model.refreshDividers(code: nil)
        #expect(model.dividerLayout.dividers.isEmpty)
        #expect(model.dividerLayout.source == nil)
    }

    // MARK: - Dividers in the text view

    private func divider(at offset: Int) -> SlideDivider {
        SlideDivider(offset: offset, slideNumber: 2, lineRange: "5–8")
    }

    @Test func anEditMovesADividerWithItsLine() {
        let divider = divider(at: 10)
        #expect(
            divider.shifted(replacing: NSRange(location: 2, length: 0), with: "abc")?.offset == 13)
        #expect(divider.shifted(replacing: NSRange(location: 2, length: 3), with: "")?.offset == 7)
        #expect(
            divider.shifted(replacing: NSRange(location: 20, length: 1), with: "x")?.offset == 10)
    }

    @Test func textTypedAtASlidesStartStaysOnItsLine() {
        let divider = divider(at: 10)
        #expect(
            divider.shifted(replacing: NSRange(location: 10, length: 0), with: "x")?.offset == 10)
        #expect(
            divider.shifted(replacing: NSRange(location: 10, length: 0), with: "\n")?.offset == 11)
    }

    @Test func removingADividersPositionRemovesIt() {
        #expect(
            divider(at: 10).shifted(replacing: NSRange(location: 8, length: 5), with: "") == nil)
    }

    private func dividers(in code: String, linesPerSlide: Int = 4) -> [SlideDivider] {
        CarouselPaginator.dividers(
            for: CarouselSplit(linesPerSlide: linesPerSlide, prefersBlankLineBreaks: false)
                .slides(of: code), in: code)
    }

    private func snapshot(_ textView: NSTextView) throws -> Data? {
        let bitmap = try #require(
            textView.bitmapImageRepForCachingDisplay(in: textView.visibleRect))
        textView.cacheDisplay(in: textView.visibleRect, to: bitmap)
        return bitmap.tiffRepresentation
    }

    /// In a window, the only way a text view has an undo manager.
    private func hostedTextView(_ code: String) throws -> (NSWindow, CodeTextView) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let textView = CodeTextView(frame: scrollView.bounds)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        textView.string = code
        window.layoutIfNeeded()
        return (window, textView)
    }

    @Test func drawingDividersLeavesTextAndUndoAloneAndTheViewOnTextKit2() throws {
        let code = document(lines: 12)
        let (window, textView) = try hostedTextView(code)
        let undoManager = try #require(textView.undoManager)
        #expect(window.undoManager === undoManager)
        let storage = try #require(textView.textStorage?.copy() as? NSAttributedString)

        let plain = try snapshot(textView)
        textView.slideDividers = dividers(in: code)
        #expect(textView.slideDividers.count == 2)
        let lined = try snapshot(textView)

        #expect(textView.string == code)
        #expect(textView.textStorage?.isEqual(to: storage) == true)
        #expect(!undoManager.canUndo, "Installing and drawing dividers must not be undoable")
        // Asking the old layout manager would have flipped the view out of TextKit 2 for good.
        #expect(textView.textLayoutManager != nil)
        #expect(plain != lined, "They actually drew")
    }

    @Test func dividersDrawAndClearAfterScrollingALongDocument() throws {
        let code = document(lines: 2_000)
        let (_, textView) = try hostedTextView(code)
        textView.scrollRangeToVisible(NSRange(location: (code as NSString).length, length: 0))
        textView.window?.layoutIfNeeded()
        #expect(textView.visibleRect.minY > 1_000, "The view must have scrolled")

        let plain = try snapshot(textView)
        textView.slideDividers = dividers(in: code, linesPerSlide: 8)
        #expect(try snapshot(textView) != plain, "A divider in the scrolled-to viewport draws")
        textView.slideDividers = []
        #expect(try snapshot(textView) == plain, "The difference was the dividers")
    }

    // MARK: - Settling

    @Test func aSplitOlderThanTheTextLeavesTheShiftedCopyInPlace() {
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.isRichText = false
        let settled = document(lines: 12)
        textView.string = settled
        let layout = SlideDividerLayout(
            revision: 1, source: settled, dividers: dividers(in: settled))
        textView.install(layout)
        let offsets = layout.dividers.map(\.offset)

        // Typing moves on while the split of `settled` is still on its way.
        textView.insertText("ab", replacementRange: NSRange(location: 0, length: 0))
        let shifted = offsets.map { $0 + 2 }
        #expect(textView.slideDividers.map(\.offset) == shifted)
        textView.install(
            SlideDividerLayout(revision: 2, source: settled, dividers: layout.dividers))
        #expect(textView.slideDividers.map(\.offset) == shifted)

        // The split of the current text replaces it, and clearing never waits for a match.
        let current = textView.string
        textView.install(
            SlideDividerLayout(revision: 3, source: current, dividers: dividers(in: current)))
        #expect(textView.slideDividers == dividers(in: current))
        textView.install(SlideDividerLayout(revision: 4))
        #expect(textView.slideDividers.isEmpty)
    }

    /// Delete across a divider and undo inside the debounce: the text settles back to what the
    /// last split saw, so only the handoff count can bring the divider back.
    @Test func textSettlingBackRestoresADividerAnEditRemoved() async throws {
        let environment = AppEnvironment(
            defaults: testDefaults(), entitlements: Entitlements(provider: DebugUnlockProvider()))
        let settings = environment.appSettings
        let model = CarouselSplitModel()
        model.split = CarouselSplit(linesPerSlide: 4, prefersBlankLineBreaks: false)
        model.showsDividers = true
        let thumbnails = PresetThumbnailModel()
        let code = document(lines: 12)
        thumbnails.stage(code, generation: settings.documentGeneration)

        let (window, textView) = try hostedTextView(code)
        let hosting = NSHostingView(
            rootView: SlideDividerRefresher(
                settings: settings, model: model, thumbnails: thumbnails,
                entitlements: environment.entitlements))
        hosting.frame = NSRect(x: 0, y: 0, width: 10, height: 10)
        window.contentView?.addSubview(hosting)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        func settle() async throws {
            for _ in 0..<5 {
                hosting.needsLayout = true
                hosting.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        try await settle()
        textView.install(model.dividerLayout)
        let full = textView.slideDividers
        #expect(full.count == 2)
        let first = model.dividerLayout.revision

        let around = NSRange(location: full[0].offset - 1, length: 2)
        let removed = (code as NSString).substring(with: around)
        textView.insertText("", replacementRange: around)
        #expect(textView.slideDividers.count == 1)
        textView.insertText(
            removed, replacementRange: NSRange(location: around.location, length: 0))
        #expect(textView.string == code)
        #expect(textView.slideDividers.count == 1, "Shifting alone can't bring it back")

        thumbnails.stage(code, generation: settings.documentGeneration)
        try await settle()
        #expect(model.dividerLayout.revision > first)
        textView.install(model.dividerLayout)
        #expect(textView.slideDividers == full)
    }

    @Test func typingShiftsTheTextViewsDividers() {
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.isRichText = false
        textView.string = "one\ntwo\nthree"
        textView.slideDividers = [divider(at: 4)]
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("ab", replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.slideDividers.map(\.offset) == [6])
    }

    // MARK: - Keyboard

    private struct Strip: View {
        let input: CarouselFilmstripModel.Input
        let model: CarouselFilmstripModel
        var interactions: FocusInteractions
        var body: some View {
            CarouselFilmstrip(
                input: input, hasShortTail: false, model: model, focusInteractions: interactions)
        }
    }

    private func hostStrip(
        _ model: CarouselFilmstripModel, interactions: FocusInteractions, above: NSButton
    ) -> NSWindow {
        var base = SnapshotConfig()
        base.code = document(lines: 40)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 260), styleMask: [.titled],
            backing: .buffered, defer: false)
        above.frame = NSRect(x: 0, y: 200, width: 300, height: 40)
        let hosting = NSHostingView(
            rootView: Strip(input: input(base), model: model, interactions: interactions))
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 190)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 260))
        container.addSubview(above)
        container.addSubview(hosting)
        window.contentView = container
        window.orderFrontRegardless()
        return window
    }

    /// `.edit` is always in the key loop, so this runs with keyboard navigation on or off.
    @Test func theArrowKeysMoveThroughTilesAndScrollThemIn() async throws {
        let model = CarouselFilmstripModel(quietWindow: .seconds(30))
        let before = NSButton(title: "Before", target: nil, action: nil)
        let window = hostStrip(model, interactions: .edit, above: before)
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(before))
        try await Task.sleep(for: .milliseconds(200))
        window.selectNextKeyView(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(window.firstResponder !== before)

        let arrow = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        for _ in 0..<6 {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                window.sendEvent(
                    try #require(
                        NSEvent.keyEvent(
                            with: type, location: .zero, modifierFlags: [.numericPad, .function],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil, characters: arrow,
                            charactersIgnoringModifiers: arrow, isARepeat: false, keyCode: 124)))
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.current == 6)
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.visible.contains(6), "The tile the keys reached must have scrolled in")
    }

    /// Like native controls, the shipped strip joins the key loop only with navigation on.
    @Test func theStripFollowsTheSystemsKeyboardNavigation() async throws {
        let before = NSButton(title: "Before", target: nil, action: nil)
        let window = hostStrip(
            CarouselFilmstripModel(quietWindow: .seconds(30)), interactions: .activate,
            above: before)
        defer { window.orderOut(nil) }
        #expect(window.makeFirstResponder(before))
        try await Task.sleep(for: .milliseconds(200))
        window.selectNextKeyView(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect((window.firstResponder !== before) == NSApp.isFullKeyboardAccessEnabled)
    }

    @Test func theCurrentTileStaysInBounds() {
        let model = CarouselFilmstripModel()
        model.moveCurrent(by: -1, count: 3)
        #expect(model.current == 0)
        model.moveCurrent(by: 5, count: 3)
        #expect(model.current == 2)
        model.moveCurrent(by: 0, count: 1)
        #expect(model.current == 0)
    }
}

extension CarouselSplit {
    fileprivate func outcome(_ code: String) -> CarouselPaginator.Outcome {
        CarouselPaginator.Outcome(split: self, code: code)
    }
}

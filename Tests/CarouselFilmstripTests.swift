import AppKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Carousel filmstrip")
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
        CarouselFilmstripModel(quietWindow: quietWindow, frameGap: frameGap) { config, _ in
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

    @Test func outcomeOffTheMainActorMatchesTheSplit() async {
        let code = document(lines: 40)
        let split = CarouselSplit(linesPerSlide: 7, prefersBlankLineBreaks: false)
        let outcome = await split.outcome(of: code)
        #expect(outcome.slides == split.slides(of: code))
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

        #expect(
            log.configs
                == [0, 1].map {
                    CarouselPaginator.slideConfig(
                        base, slide: input.slides[$0], at: $0, of: input.slides.count, cues: cues)
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
        let estimate = await ExportManager.estimatedCarouselSlideBytes(
            SnapshotConfig(), slides: [long, short], cues: .none)
        #expect(estimate != nil)
    }

    @Test func theEstimateSkipsASlideTheFilmstripWouldNotRender() async {
        let slide = CarouselPaginator.Slide(
            text: String(repeating: "x", count: CarouselPaginator.Slide.maximumPreviewBytes + 1),
            firstLine: 1, lineCount: 1)
        let estimate = await ExportManager.estimatedCarouselSlideBytes(
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

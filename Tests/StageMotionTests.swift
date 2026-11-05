import AppKit
import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Stage motion")
struct StageMotionTests {
    private static let oneDark = Theme.builtIns.first { $0.id == "one-dark" }!
    private static let oneLight = Theme.builtIns.first { $0.id == "one-light" }!

    private func canvas(
        code: String = "let answer = 42", theme: Theme = oneDark,
        background: VitrineDomain.BackgroundStyle = .gradient(.aurora), padding: CGFloat = 32,
        fixedSize: CGSize? = nil
    ) -> SnapshotCanvas {
        var config = SnapshotConfig()
        config.code = code
        config.language = .swift
        config.theme = theme
        config.background = background
        config.padding = padding
        return SnapshotCanvas(config: config, fixedSize: fixedSize)
    }

    // MARK: - Theme fade

    @Test func aThemeChangeKeepsTheOldCanvasUnderANewLayer() throws {
        let old = canvas()
        let new = canvas(theme: Self.oneLight)
        let fade = PreviewThemeFade(canvas: old).applying(new, animated: true)
        let outgoing = try #require(fade.outgoing)
        #expect(outgoing.canvas == old)
        #expect(fade.live.canvas == new)
        #expect(outgoing.id != fade.live.id, "the old layer keeps its identity")
        #expect(fade.layers.last == fade.live, "the new layer is on top")
    }

    @Test func applyingTheSameCanvasChangesNothing() {
        let fade = PreviewThemeFade(canvas: canvas()).applying(
            canvas(theme: Self.oneLight), animated: true)
        #expect(fade.applying(canvas(theme: Self.oneLight), animated: true) == fade)
    }

    @Test func reduceMotionSwapsInPlace() {
        let fade = PreviewThemeFade(canvas: canvas())
        let next = fade.applying(canvas(theme: Self.oneLight), animated: false)
        #expect(next.outgoing == nil)
        #expect(next.live.id == fade.live.id, "same identity, as an ordinary update")
        #expect(next.live.canvas.config.theme.id == "one-light")
    }

    @Test func aThemeChangeWithAnythingElseDoesNotFade() {
        let start = PreviewThemeFade(canvas: canvas())
        for other in [
            canvas(code: "let answer = 43", theme: Self.oneLight),
            canvas(theme: Self.oneLight, padding: 64),
            canvas(theme: Self.oneLight, background: .transparent),
        ] {
            #expect(start.applying(other, animated: true).outgoing == nil)
        }
    }

    @Test func aDestinationChangeWithTheThemeDoesNotFade() {
        let next = PreviewThemeFade(canvas: canvas()).applying(
            canvas(theme: Self.oneLight, fixedSize: CGSize(width: 1200, height: 630)),
            animated: true)
        #expect(next.outgoing == nil)
    }

    @Test func editingACustomThemesColorsDoesNotFade() throws {
        let palette = try ThemePalette(
            background: #require(HexColor("#101010")), foreground: #require(HexColor("#FAFAFA")))
        var edited = palette
        edited.keyword = try #require(HexColor("#FF00FF"))
        let before = canvas(theme: Theme(id: "mine", displayName: "Mine", palette: palette))
        let after = canvas(theme: Theme(id: "mine", displayName: "Mine", palette: edited))
        #expect(PreviewThemeFade(canvas: before).applying(after, animated: true).outgoing == nil)
    }

    /// The old layer would show the old text beside the new while the fade runs.
    @Test func newCodeDuringAFadeEndsItWithoutAGhost() {
        let fading = PreviewThemeFade(canvas: canvas()).applying(
            canvas(theme: Self.oneLight), animated: true)
        let typed = canvas(code: "let answer = 43", theme: Self.oneLight)
        let next = fading.applying(typed, animated: true)
        #expect(next.outgoing == nil)
        #expect(next.layers == [next.live])
        #expect(next.live.canvas == typed)
        #expect(next.live.id != fading.live.id, "not the identity whose fade is still running")
    }

    @Test func anotherThemeDuringAFadeLandsAtOnce() {
        let fading = PreviewThemeFade(canvas: canvas()).applying(
            canvas(theme: Self.oneLight), animated: true)
        let third = Theme.builtIns.first { $0.id == "dracula" }!
        let next = fading.applying(canvas(theme: third), animated: true)
        #expect(next.outgoing == nil)
        #expect(next.live.id != fading.live.id)
    }

    @Test func onlyTheLatestFadeMayFinish() {
        let fading = PreviewThemeFade(canvas: canvas()).applying(
            canvas(theme: Self.oneLight), animated: true)
        #expect(fading.finishing(fading.live.id - 1) == fading)
        let finished = fading.finishing(fading.live.id)
        #expect(finished.outgoing == nil)
        #expect(finished.live == fading.live)
    }

    @Test func atRestTheLayersDrawExactlyTheCanvas() throws {
        let plain = canvas(background: .transparent)
        let layers = ThemeFadeLayers(fade: PreviewThemeFade(canvas: plain), progress: 1)
        #expect(try rgba(layers) == rgba(plain))
    }

    /// Mid-fade, everything the two themes share stays put, including the transparent
    /// capture's soft shadow, and only what differs blends.
    @Test func midFadeLeavesSharedPixelsAloneAndBlendsTheRest() throws {
        let old = canvas(background: .transparent)
        let new = canvas(theme: Self.oneLight, background: .transparent)
        let fade = PreviewThemeFade(canvas: old).applying(new, animated: true)
        let before = try rgba(old)
        let after = try rgba(new)
        let middle = try rgba(ThemeFadeLayers(fade: fade, progress: 0.5))
        #expect(middle.count == before.count)

        var worstShared = 0
        var worstBlend = 0
        var softShared = 0
        var blended = 0
        for index in stride(from: 0, to: before.count, by: 4) {
            let oldPixel = before[index..<index + 4].map(Int.init)
            let newPixel = after[index..<index + 4].map(Int.init)
            let midPixel = middle[index..<index + 4].map(Int.init)
            if oldPixel == newPixel {
                if oldPixel[3] > 0, oldPixel[3] < 255 { softShared += 1 }
                let drift = zip(oldPixel, midPixel).map { abs($0 - $1) }.max() ?? 0
                worstShared = max(worstShared, drift)
            } else if abs(oldPixel[0] - newPixel[0]) > 100 {
                blended += 1
                let midpoint = (oldPixel[0] + newPixel[0]) / 2
                worstBlend = max(worstBlend, abs(midPixel[0] - midpoint))
            }
        }
        // Rounding and dithering only. Unflattened layers put a chrome dot 150 steps off.
        #expect(worstShared <= 3)
        #expect(worstBlend <= 4)
        #expect(softShared > 100, "the capture must have soft edges to check")
        #expect(blended > 100, "the themes must differ to blend")
    }

    private func rgba(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    // MARK: - Stage fit

    private func measurement(
        _ width: CGFloat, _ height: CGFloat, destination: CGSize? = nil, document: Int = 0
    ) -> PreviewCardGeometry.Measurement {
        .init(
            size: CGSize(width: width, height: height), destination: destination,
            document: document)
    }

    @Test func aDestinationThatMovesTheCardStartsAMorphFromTheOldCard() {
        let geometry = PreviewCardGeometry()
        geometry.record(measurement(540, 456))
        geometry.record(measurement(1600, 900, destination: CGSize(width: 1600, height: 900)))
        #expect(geometry.morph.generation == 1)
        #expect(geometry.morph.previousCard == CGSize(width: 540, height: 456))
        #expect(geometry.size == CGSize(width: 1600, height: 900))

        geometry.record(measurement(540, 456))
        #expect(geometry.morph.generation == 2, "back to Custom")
        #expect(geometry.morph.previousCard == CGSize(width: 1600, height: 900))
    }

    @Test func theFirstMeasurementAndTypingDoNotMorph() {
        let geometry = PreviewCardGeometry()
        let destination = CGSize(width: 1600, height: 900)
        geometry.record(measurement(1600, 900, destination: destination))
        #expect(geometry.morph.generation == 0, "nothing was on the stage yet")

        let custom = PreviewCardGeometry()
        custom.record(measurement(540, 456))
        custom.record(measurement(540, 480))
        custom.record(measurement(560, 480))
        #expect(custom.morph.generation == 0, "the card growing with the document")
    }

    @Test func aDestinationOfTheSameSizeLeavesNothingArmedForLaterTyping() {
        let geometry = PreviewCardGeometry()
        let same = CGSize(width: 540, height: 456)
        geometry.record(measurement(540, 456))
        geometry.record(measurement(540, 456, destination: same))
        #expect(geometry.morph.generation == 0)

        geometry.record(measurement(540, 456))
        geometry.record(measurement(540, 480))
        #expect(geometry.morph.generation == 0)
    }

    @Test func aLoadedDocumentThatMovesTheDestinationDoesNotMorph() {
        let geometry = PreviewCardGeometry()
        geometry.record(measurement(1600, 900, destination: CGSize(width: 1600, height: 900)))
        geometry.record(measurement(540, 456, document: 1))
        #expect(geometry.morph.generation == 0)
        #expect(geometry.size == CGSize(width: 540, height: 456))

        geometry.record(
            measurement(1600, 900, destination: CGSize(width: 1600, height: 900), document: 1))
        #expect(geometry.morph.generation == 1, "the next destination change still morphs")
    }

    @Test func theStartingScalePutsTheNewCardWhereTheOldOneWasDrawn() {
        let stage = CGSize(width: 800, height: 700)
        let old = CGSize(width: 540, height: 456)
        let new = CGSize(width: 1600, height: 900)
        let start = StageFitMorph(generation: 1, previousCard: old)
            .startingScale(to: new, in: stage)
        let fit = EditorView.fitScale(card: new, in: stage)
        #expect(abs(new.width * fit * start.width - old.width) < 0.001)
        #expect(abs(new.height * fit * start.height - old.height) < 0.001)
    }

    @Test func anUnmeasuredStageHasNothingToMorphFrom() {
        let morph = StageFitMorph(generation: 1, previousCard: CGSize(width: 540, height: 456))
        #expect(
            morph.startingScale(to: CGSize(width: 800, height: 600), in: .zero)
                == CGSize(width: 1, height: 1))
    }

    @Test func theEffectRunsFromTheOldRectToIdentity() {
        var effect = StageFitMorphEffect(
            generation: 3, startingScale: CGSize(width: 0.5, height: 2))
        let size = CGSize(width: 100, height: 100)
        let center = CGPoint(x: 50, y: 50)
        let corner = CGPoint(x: 100, y: 100)
        func mapped(_ point: CGPoint) -> CGPoint {
            let value = effect.effectValue(size: size)
            return CGPoint(
                x: value.m11 * point.x + value.m21 * point.y + value.m31,
                y: value.m12 * point.x + value.m22 * point.y + value.m32)
        }

        #expect(mapped(corner) == corner, "at rest")

        effect.animatableData = 2
        #expect(mapped(corner) == CGPoint(x: 75, y: 150), "the first frame")
        #expect(mapped(center) == center, "about the card's center, which does not move")

        effect.animatableData = 0
        #expect(mapped(corner) == CGPoint(x: 75, y: 150), "interrupted: never past the start")
    }

    // MARK: - The real views

    @Observable final class FadeModel {
        var canvas: SnapshotCanvas
        var layerCounts: [Int] = []
        init(canvas: SnapshotCanvas) { self.canvas = canvas }
    }

    private struct FadeHost: View {
        let model: FadeModel
        let reduceMotion: Bool

        var body: some View {
            ThemeFadingCanvas(canvas: model.canvas)
                .environment(\.reduceMotionOverride, reduceMotion)
                .onPreferenceChange(ThemeFadeLayerCountKey.self) { model.layerCounts.append($0) }
        }
    }

    private func withFade(
        reduceMotion: Bool = false,
        _ body: (FadeModel, () -> Void) async throws -> Void
    ) async throws {
        let model = FadeModel(canvas: canvas())
        let hosting = NSHostingView(rootView: FadeHost(model: model, reduceMotion: reduceMotion))
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = showing(hosting)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        model.layerCounts = []
        try await body(model) {
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
        }
    }

    private func showing(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.alphaValue = 0
        window.orderFrontRegardless()
        return window
    }

    @Test func aFadeHoldsTwoLayersAndThenOne() async throws {
        try await withFade { model, flush in
            model.canvas = canvas(theme: Self.oneLight)
            flush()
            #expect(model.layerCounts.last == 2)
            try await Task.sleep(for: .milliseconds(500))
            #expect(model.layerCounts.last == 1)
        }
    }

    @Test func reduceMotionNeverHoldsTwoLayers() async throws {
        try await withFade(reduceMotion: true) { model, flush in
            model.canvas = canvas(theme: Self.oneLight)
            flush()
            try await Task.sleep(for: .milliseconds(300))
            #expect(!model.layerCounts.contains(2))
        }
    }

    @Test func aStyleChangeDoesNotHoldTwoLayers() async throws {
        try await withFade { model, flush in
            model.canvas = canvas(padding: 64)
            flush()
            try await Task.sleep(for: .milliseconds(300))
            #expect(!model.layerCounts.contains(2))
        }
    }

    @Test func typingDuringAFadeDropsTheOldLayerAtOnce() async throws {
        try await withFade { model, flush in
            model.canvas = canvas(theme: Self.oneLight)
            flush()
            #expect(model.layerCounts.last == 2)
            model.canvas = canvas(code: "let answer = 43", theme: Self.oneLight)
            flush()
            #expect(model.layerCounts.last == 1)
        }
    }

    /// Without the cooldown a burst alternates: fade, snap, fade, snap.
    @Test func aBurstOfThemesFadesOnceAndThenSnapsUntilItPauses() async throws {
        let dracula = Theme.builtIns.first { $0.id == "dracula" }!
        try await withFade { model, flush in
            for theme in [Self.oneLight, dracula, Self.oneDark, Self.oneLight, dracula] {
                model.canvas = canvas(theme: theme)
                flush()
            }
            #expect(model.layerCounts.filter { $0 == 2 }.count == 1)
            #expect(model.layerCounts.last == 1)

            try await Task.sleep(for: .milliseconds(500))
            model.canvas = canvas(theme: Self.oneDark)
            flush()
            #expect(model.layerCounts.last == 2, "fades again after the pause")
        }
    }

    private static let stage = CGSize(width: 600, height: 400)
    /// Long enough that a test reads the start of the animation whatever the machine is doing.
    private static let slowSpring = Spring(settlingDuration: 30, dampingRatio: 1)

    private final class TapLog { var count = 0 }

    private struct StageHost: View {
        let geometry: PreviewCardGeometry
        let fitAnimation: Animation
        let morphSpring: Spring
        let reduceMotion: Bool
        let taps: TapLog

        var body: some View {
            PreviewCardStage(
                geometry: geometry, stageSize: StageMotionTests.stage,
                fitAnimation: fitAnimation, morphSpring: morphSpring
            ) { _ in
                Color.red
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { _ in taps.count += 1 })
            }
            .environment(\.reduceMotionOverride, reduceMotion)
            .frame(width: StageMotionTests.stage.width, height: StageMotionTests.stage.height)
            .background(Color.white)
            .allowsWindowActivationEvents()
        }
    }

    private struct StageHarness {
        let window: NSWindow
        let hosting: NSView
        let geometry: PreviewCardGeometry
        let taps: TapLog

        /// The card's drawn rect, read from the rendered pixels.
        func drawnRect() throws -> CGRect {
            let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            var box = CGRect.null
            let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                    guard let color = rep.colorAt(x: x, y: y),
                        color.redComponent > 0.8, color.greenComponent < 0.5
                    else { continue }
                    box = box.union(
                        CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale, width: 1, height: 1))
                }
            }
            return box
        }

        func clickCenter() async throws {
            let point = hosting.convert(NSPoint(x: 300, y: 200), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(
                    try #require(
                        NSEvent.mouseEvent(
                            with: type, location: point, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                            clickCount: 1, pressure: 1)))
                try await Task.sleep(for: .milliseconds(30))
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func withStage(
        fitAnimation: Animation = .easeInOut(duration: 0.25),
        morphSpring: Spring = StageFitMorph.spring, reduceMotion: Bool = false,
        _ body: (StageHarness) async throws -> Void
    ) async throws {
        let geometry = PreviewCardGeometry()
        geometry.record(measurement(1000, 400))
        let taps = TapLog()
        let hosting = NSHostingView(
            rootView: StageHost(
                geometry: geometry, fitAnimation: fitAnimation, morphSpring: morphSpring,
                reduceMotion: reduceMotion, taps: taps))
        hosting.frame = NSRect(origin: .zero, size: Self.stage)
        let window = showing(hosting)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        try await body(
            StageHarness(window: window, hosting: hosting, geometry: geometry, taps: taps))
    }

    private func expectCentered(_ rect: CGRect, _ comment: Comment) {
        #expect(abs(rect.midX - 300) <= 2, comment)
        #expect(abs(rect.midY - 200) <= 2, comment)
    }

    private func expectSize(_ rect: CGRect, _ width: CGFloat, _ height: CGFloat, _ comment: Comment)
    {
        #expect(abs(rect.width - width) <= 4, comment)
        #expect(abs(rect.height - height) <= 4, comment)
    }

    private static let oldFit = (width: 528.0, height: 211.2)
    private static let newFit = (width: 365.0, height: 328.0)

    /// The card grows without a destination change, limited by the stage on both sides.
    @Test func aFitAnimationKeepsTheCardCentered() async throws {
        try await withStage(fitAnimation: .linear(duration: 30)) { stage in
            expectCentered(try stage.drawnRect(), "at rest")
            stage.geometry.record(measurement(1000, 900))
            try await Task.sleep(for: .milliseconds(100))
            let rect = try stage.drawnRect()
            expectCentered(rect, "during the fit animation")
            #expect(stage.geometry.morph.generation == 0)
        }
    }

    @Test func aMorphStartsOnTheOldRectAndStaysCentered() async throws {
        try await withStage(morphSpring: Self.slowSpring) { stage in
            stage.geometry.record(
                measurement(1000, 900, destination: CGSize(width: 1000, height: 900)))
            try await Task.sleep(for: .milliseconds(100))
            let rect = try stage.drawnRect()
            expectCentered(rect, "during the morph")
            expectSize(rect, Self.oldFit.width, Self.oldFit.height, "on the old rect")
        }
    }

    @Test func aMorphEndsOnTheNewRectAndThenTakesClicks() async throws {
        try await withStage { stage in
            stage.geometry.record(
                measurement(1000, 900, destination: CGSize(width: 1000, height: 900)))
            try await Task.sleep(for: .milliseconds(700))
            let rect = try stage.drawnRect()
            expectCentered(rect, "at rest")
            expectSize(rect, Self.newFit.width, Self.newFit.height, "on the new rect")
            try await stage.clickCenter()
            #expect(stage.taps.count == 1)
        }
    }

    @Test func aClickDuringAMorphReachesNothing() async throws {
        try await withStage(morphSpring: Self.slowSpring) { stage in
            try await stage.clickCenter()
            #expect(stage.taps.count == 1, "before the morph")

            stage.geometry.record(
                measurement(1000, 900, destination: CGSize(width: 1000, height: 900)))
            try await Task.sleep(for: .milliseconds(100))
            try await stage.clickCenter()
            #expect(stage.taps.count == 1, "during the morph")
        }
    }

    /// The slow animations show that nothing is interpolated at all.
    @Test func reduceMotionLandsOnTheNewRectAndTakesClicksAtOnce() async throws {
        try await withStage(
            fitAnimation: .linear(duration: 30), morphSpring: Self.slowSpring, reduceMotion: true
        ) { stage in
            stage.geometry.record(
                measurement(1000, 900, destination: CGSize(width: 1000, height: 900)))
            try await Task.sleep(for: .milliseconds(100))
            let rect = try stage.drawnRect()
            expectCentered(rect, "at once")
            expectSize(rect, Self.newFit.width, Self.newFit.height, "at once")
            try await stage.clickCenter()
            #expect(stage.taps.count == 1)
        }
    }

    // MARK: - Background kind

    @Test func theGradientKindReturnsToTheLastPreset() {
        let store = BackgroundImageStore.container
        let solid = VitrineDomain.BackgroundStyle.solid(RGBAColor(.black))
        #expect(
            BackgroundKind.gradient.makeDefault(from: solid, lastPreset: .sunset, imageStore: store)
                == .gradient(.sunset))
        #expect(
            BackgroundKind.gradient.makeDefault(from: solid, imageStore: store)
                == .gradient(.aurora))
    }
}

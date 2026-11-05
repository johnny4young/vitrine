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
        _ width: CGFloat, _ height: CGFloat, destination: CGSize? = nil
    ) -> PreviewCardGeometry.Measurement {
        .init(size: CGSize(width: width, height: height), destination: destination)
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
        let morph = StageFitMorph(generation: 3, previousCard: .zero)
        var effect = StageFitMorphEffect(morph: morph, startingScale: CGSize(width: 0.5, height: 2))
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

    // MARK: - Hit testing

    @Observable final class ProbeModel {
        var morph = StageFitMorph()
        var taps: [CGPoint] = []
    }

    private struct MorphProbe: View {
        let model: ProbeModel
        let animation: Animation?

        var body: some View {
            Color.red
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { model.taps.append($0.location) })
                .frame(width: 200, height: 200)
                .modifier(
                    StageFitMorphEffect(
                        morph: model.morph, startingScale: CGSize(width: 0.25, height: 0.25))
                )
                .animation(animation, value: model.morph.generation)
                .frame(width: 400, height: 400)
                .allowsWindowActivationEvents()
        }
    }

    /// Clicks `offset` points right of the probe's center and returns where it landed.
    private func click(
        _ window: NSWindow, _ hosting: NSView, _ model: ProbeModel, offset: CGFloat
    ) async throws -> CGPoint? {
        model.taps = []
        let point = hosting.convert(NSPoint(x: 200 + offset, y: 200), to: nil)
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
        return model.taps.first
    }

    private func withProbe(
        animation: Animation?, _ body: (NSWindow, NSView, ProbeModel) async throws -> Void
    ) async throws {
        let model = ProbeModel()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: MorphProbe(model: model, animation: animation))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        try await body(window, hosting, model)
    }

    /// A mark is hit where it is drawn during the morph, not where it will land.
    @Test func hitTestingFollowsTheCardDuringAMorph() async throws {
        try await withProbe(animation: .linear(duration: 30)) { window, hosting, model in
            model.morph = StageFitMorph(generation: 1, previousCard: .zero)
            try await Task.sleep(for: .milliseconds(100))

            // The drawn card is about 25 pt either side of center; the final one, 100.
            let outside = try await click(window, hosting, model, offset: 80)
            #expect(outside == nil, "inside the final rect but outside what is drawn")
            let inside = try await click(window, hosting, model, offset: 20)
            let location = try #require(inside, "inside what is drawn")
            #expect(location.x > 150, "mapped through the drawn scale, not the final one")
        }
    }

    /// With no animation, which is what Reduce Motion gives the effect, the card is final.
    @Test func withoutAnimationTheCardIsFinalAtOnce() async throws {
        try await withProbe(animation: nil) { window, hosting, model in
            model.morph = StageFitMorph(generation: 1, previousCard: .zero)
            try await Task.sleep(for: .milliseconds(100))
            let location = try await click(window, hosting, model, offset: 80)
            #expect(location == CGPoint(x: 180, y: 100))
        }
    }
}

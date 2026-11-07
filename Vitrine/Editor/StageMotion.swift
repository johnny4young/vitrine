import SwiftUI
import VitrineDomain
import VitrineRendering

// MARK: - Theme cross-fade

/// The canvases the stage draws: the live one, and the previous one while a theme change
/// fades in over it. The fade exists only when the theme is all that differs, or when the
/// stage asks for one to change code steps. Any other change during a fade ends it at once.
struct PreviewThemeFade: Equatable {
    struct Layer: Identifiable, Equatable {
        let id: Int
        var canvas: SnapshotCanvas
    }

    private(set) var live: Layer
    private(set) var outgoing: Layer?

    init(canvas: SnapshotCanvas) {
        live = Layer(id: 0, canvas: canvas)
    }

    init(live: Layer, outgoing: Layer?) {
        self.live = live
        self.outgoing = outgoing
    }

    var layers: [Layer] { [outgoing, live].compactMap(\.self) }

    func applying(
        _ canvas: SnapshotCanvas, animated: Bool, forced: Bool = false
    )
        -> PreviewThemeFade
    {
        guard canvas != live.canvas else { return self }
        var next = self
        if outgoing != nil {
            // A new identity, because the live layer's running fade cannot be stopped
            // in place and would otherwise show the stage through it.
            next.outgoing = nil
            next.live = Layer(id: live.id + 1, canvas: canvas)
        } else if animated, forced || Self.differsOnlyInTheme(live.canvas, canvas) {
            next.outgoing = live
            next.live = Layer(id: live.id + 1, canvas: canvas)
        } else {
            next.live.canvas = canvas
        }
        return next
    }

    /// The fade of `layerID` ended. A later change may already own the layers.
    func finishing(_ layerID: Int) -> PreviewThemeFade {
        guard live.id == layerID else { return self }
        var next = self
        next.outgoing = nil
        return next
    }

    private static func differsOnlyInTheme(_ old: SnapshotCanvas, _ new: SnapshotCanvas) -> Bool {
        guard old.fixedSize == new.fixedSize, old.config.theme.id != new.config.theme.id else {
            return false
        }
        var rethemed = new.config
        rethemed.theme = old.config.theme
        return rethemed == old.config
    }
}

/// The layers at a point in the fade. Additive blending keeps every pixel the two canvases
/// share exactly as it is, including a transparent capture's soft edges, which plain
/// source-over would darken and then release when the old layer goes.
struct ThemeFadeLayers: View {
    let fade: PreviewThemeFade
    /// The live layer's opacity. The outgoing layer takes the remainder.
    let progress: Double

    var body: some View {
        let isFading = fade.outgoing != nil
        ZStack {
            ForEach(fade.layers) { layer in
                let isLive = layer.id == fade.live.id
                layer.canvas
                    .equatable()
                    // Flattened first, or the opacity and blend apply to each of its leaves.
                    .compositingGroup()
                    .opacity(isFading ? (isLive ? progress : 1 - progress) : 1)
                    .blendMode(isFading ? .plusLighter : .normal)
                    .allowsHitTesting(isLive)
                    .accessibilityHidden(!isLive)
                    .transition(.identity)
            }
        }
        .compositingGroup()
        .preference(key: ThemeFadeLayerCountKey.self, value: fade.layers.count)
    }
}

/// How many canvases the stage is drawing, so a fade can be observed from outside it.
struct ThemeFadeLayerCountKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}

/// The stage's canvas. A layer keeps its identity across a fade, so the outgoing canvas is
/// not evaluated again and the incoming one highlights once.
struct ThemeFadingCanvas: View {
    let canvas: SnapshotCanvas
    /// A new value fades the next canvas in, even under Reduce Motion, which keeps dissolves.
    var fadeGeneration = 0

    /// What the canvas was, and whether a burst is cooling down. Not observed, because an
    /// ordinary style change must not cost this view a second pass.
    private final class Memory {
        var canvas: SnapshotCanvas
        var fadeGeneration = 0
        private(set) var isCoolingDown = false
        private var cooldown: Task<Void, Never>?

        init(canvas: SnapshotCanvas) { self.canvas = canvas }

        /// Long enough to outlast the gap between clicks in a burst, which would otherwise
        /// alternate a fade and a snap.
        func coolDown() {
            isCoolingDown = true
            cooldown?.cancel()
            cooldown = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.isCoolingDown = false
            }
        }
    }

    @ReducesMotion private var reduceMotion
    @State private var memory: Memory
    // These change only when a fade starts or ends.
    @State private var outgoing: PreviewThemeFade.Layer?
    @State private var liveLayer = 0
    @State private var revealedLayer = 0

    init(canvas: SnapshotCanvas, fadeGeneration: Int = 0) {
        self.canvas = canvas
        self.fadeGeneration = fadeGeneration
        let memory = Memory(canvas: canvas)
        memory.fadeGeneration = fadeGeneration
        _memory = State(initialValue: memory)
    }

    private var settled: PreviewThemeFade {
        PreviewThemeFade(
            live: PreviewThemeFade.Layer(id: liveLayer, canvas: memory.canvas), outgoing: outgoing)
    }

    private var fades: Bool { !reduceMotion && !memory.isCoolingDown }
    private var forced: Bool { fadeGeneration != memory.fadeGeneration }

    var body: some View {
        // Derived here too: `onChange` runs after this pass, which must already hold
        // the old canvas rather than draw the new theme over it.
        let current = settled.applying(
            canvas, animated: fades || (forced && !memory.isCoolingDown), forced: forced)
        ThemeFadeLayers(fade: current, progress: revealedLayer == current.live.id ? 1 : 0)
            .onChange(of: canvas) { _, canvas in record(canvas) }
            .onChange(of: fadeGeneration) { _, generation in memory.fadeGeneration = generation }
    }

    private func record(_ canvas: SnapshotCanvas) {
        let previous = settled
        let next = previous.applying(
            canvas, animated: fades || (forced && !memory.isCoolingDown), forced: forced)
        memory.canvas = canvas
        memory.fadeGeneration = fadeGeneration
        if previous.outgoing != nil || memory.isCoolingDown { memory.coolDown() }
        guard next.live.id != previous.live.id else { return }
        liveLayer = next.live.id
        outgoing = next.outgoing
        guard next.outgoing != nil else { return }
        let layer = next.live.id
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) {
            revealedLayer = layer
        } completion: {
            outgoing = settled.finishing(layer).outgoing
        }
    }
}

// MARK: - Stage fit

/// A destination change: the card size the stage was showing before it.
struct StageFitMorph: Equatable {
    static let spring = Spring(settlingDuration: 0.24, dampingRatio: 0.85)

    var generation = 0
    var previousCard = CGSize.zero

    /// The per-axis scale that puts a card of `card` where the previous card was drawn.
    func startingScale(to card: CGSize, in stage: CGSize) -> CGSize {
        let old = Self.visibleSize(of: previousCard, in: stage)
        let new = Self.visibleSize(of: card, in: stage)
        guard old.width > 0, old.height > 0, new.width > 0, new.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: old.width / new.width, height: old.height / new.height)
    }

    private static func visibleSize(of card: CGSize, in stage: CGSize) -> CGSize {
        let scale = EditorView.fitScale(card: card, in: stage)
        return CGSize(width: card.width * scale, height: card.height * scale)
    }
}

/// Eases the card's frame from the previous destination's rect to the new one. A transform
/// only, so layout is final from the first frame. A second destination during a morph starts
/// from the first one's rect, not from where the card was drawn, so the card jumps there.
nonisolated struct StageFitMorphEffect: GeometryEffect {
    /// Animates up to `generation`, so a morph never needs a second pass to reset itself.
    var progress: CGFloat
    let generation: Int
    let startingScale: CGSize

    init(generation: Int, startingScale: CGSize) {
        progress = CGFloat(generation)
        self.generation = generation
        self.startingScale = startingScale
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // 1 at the start of the morph, 0 at rest, and below 0 when the spring overshoots.
        let remaining = min(CGFloat(generation) - progress, 1)
        let scaleX = 1 + (startingScale.width - 1) * remaining
        let scaleY = 1 + (startingScale.height - 1) * remaining
        return ProjectionTransform(
            CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                .scaledBy(x: scaleX, y: scaleY)
                .translatedBy(x: -size.width / 2, y: -size.height / 2))
    }
}

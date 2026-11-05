import SwiftUI
import VitrineDomain
import VitrineRendering

/// The slide tiles shown before anything is written, each one the export's own config through
/// the export's own renderer at a smaller scale. Only tiles on screen render, one per frame,
/// after a quiet window, and any change cancels the pass.
@Observable
final class CarouselFilmstripModel {
    struct Input: Equatable {
        let base: SnapshotConfig
        let slides: [CarouselPaginator.Slide]
        let cues: CarouselPaginator.Cues
        let profile: ColorProfile
    }

    private struct Rendered: Equatable {
        let config: SnapshotConfig
        let profile: ColorProfile
    }

    static let tileSize = CGSize(
        width: 86,
        height: 86 * ExportManager.carouselSlideSize.height / ExportManager.carouselSlideSize.width)
    /// Lazy tiles leave the visible set on their own schedule; this holds regardless.
    static let maximumLiveTiles = 12
    /// Thirty ordinary lines stay well under this. A longer slide holds some enormous line,
    /// whose highlighting would hold the main actor past several frames.
    static let maximumSlideBytes = 8 * 1_024

    var visible: Set<Int> = []
    /// The tile the arrow keys are on.
    var current = 0
    private(set) var images: [Int: CGImage] = [:]

    @ObservationIgnored private var rendered: [Int: Rendered] = [:]
    private let quietWindow: Duration
    private let frameGap: Duration
    private let render: (SnapshotConfig, ColorProfile) -> CGImage?

    init(
        quietWindow: Duration = .milliseconds(200), frameGap: Duration = .milliseconds(16),
        render: @escaping (SnapshotConfig, ColorProfile) -> CGImage? = {
            CarouselFilmstripModel.renderTile($0, profile: $1)
        }
    ) {
        self.quietWindow = quietWindow
        self.frameGap = frameGap
        self.render = render
    }

    /// The export's frame, scale aside, so a tile lays out exactly as its slide will.
    static func renderTile(_ config: SnapshotConfig, profile: ColorProfile) -> CGImage? {
        try? ExportManager.renderCGImageChecked(
            config, scale: 2 * tileSize.width / ExportManager.carouselSlideSize.width,
            fixedSize: ExportManager.carouselSlideSize, profile: profile)
    }

    static func canPreview(_ slide: CarouselPaginator.Slide) -> Bool {
        slide.text.utf8.count <= maximumSlideBytes
    }

    func moveCurrent(by step: Int, count: Int) {
        current = min(max(current + step, 0), max(count - 1, 0))
    }

    func refresh(_ input: Input) async {
        let live = visible.filter { $0 < input.slides.count }.sorted().prefix(Self.maximumLiveTiles)
        var wanted: [Int: Rendered] = [:]
        for index in live {
            let config = CarouselPaginator.slideConfig(
                input.base, slide: input.slides[index], at: index, of: input.slides.count,
                cues: input.cues)
            wanted[index] = Rendered(config: config, profile: input.profile)
        }
        // A tile that no longer matches leaves now, so it can't show an old split or a row
        // hidden since. Tiles scrolled away go too, which is what bounds the images held.
        let stale = rendered.keys.filter { wanted[$0] != rendered[$0] }
        for index in stale {
            rendered[index] = nil
            images[index] = nil
        }

        try? await Task.sleep(for: quietWindow)
        for index in live where rendered[index] == nil {
            guard !Task.isCancelled, let tile = wanted[index] else { return }
            if Self.canPreview(input.slides[index]) {
                images[index] = render(tile.config, tile.profile)
            }
            rendered[index] = tile
            try? await Task.sleep(for: frameGap)
        }
    }
}

/// A fixed-height strip, so nothing moves as tiles arrive. One focusable container takes the
/// arrow keys, which also scroll tiles a keyboard could not reach otherwise.
struct CarouselFilmstrip: View {
    let input: CarouselFilmstripModel.Input
    let hasShortTail: Bool
    let model: CarouselFilmstripModel

    @FocusState private var isFocused: Bool

    private var count: Int { input.slides.count }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(input.slides.indices, id: \.self) { index in
                        CarouselSlideTile(
                            slide: input.slides[index], index: index, count: count,
                            isShort: hasShortTail && index == count - 1,
                            isCurrent: isFocused && index == model.current, model: model
                        )
                        .id(index)
                        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                            if isVisible {
                                model.visible.insert(index)
                            } else {
                                model.visible.remove(index)
                            }
                        }
                    }
                }
                .padding(2)
            }
            // Room below the tiles for a scroller that takes space, under a mouse.
            .frame(height: CarouselFilmstripModel.tileSize.height + 40)
            .focusable(interactions: .activate)
            .focused($isFocused)
            .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
                model.moveCurrent(by: press.key == .leftArrow ? -1 : 1, count: count)
                proxy.scrollTo(model.current)
                return .handled
            }
            .onChange(of: count) {
                model.moveCurrent(by: 0, count: count)
                // A removed tile reports no visibility change of its own.
                model.visible = model.visible.filter { $0 < count }
            }
        }
        .task(id: RefreshID(input: input, visible: model.visible)) { await model.refresh(input) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carousel-filmstrip")
    }

    private struct RefreshID: Equatable {
        let input: CarouselFilmstripModel.Input
        let visible: Set<Int>
    }
}

/// Reads the images itself, so a finished render doesn't re-evaluate the strip.
private struct CarouselSlideTile: View {
    let slide: CarouselPaginator.Slide
    let index: Int
    let count: Int
    let isShort: Bool
    let isCurrent: Bool
    let model: CarouselFilmstripModel

    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

    var body: some View {
        VStack(spacing: 4) {
            Color.clear
                .frame(
                    width: CarouselFilmstripModel.tileSize.width,
                    height: CarouselFilmstripModel.tileSize.height
                )
                .background(VitrineTokens.Surface.inset)
                .overlay {
                    if let image = model.images[index] {
                        Image(decorative: image, scale: 2).resizable()
                    } else if !CarouselFilmstripModel.canPreview(slide) {
                        Image(systemName: "text.alignleft")
                            .foregroundStyle(VitrineTokens.Text.tertiary)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    pill(Text(verbatim: "\(index + 1)/\(count)"))
                }
                .overlay(alignment: .topLeading) {
                    if isShort { pill(Text("short")) }
                }
                .clipShape(shape)
                .overlay(
                    shape.strokeBorder(
                        isCurrent ? VitrineTokens.Accent.system : VitrineTokens.Line.border,
                        lineWidth: isCurrent ? 2 : Brand.Stroke.hairline))
            Text(verbatim: slide.lineRange)
                .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: CarouselFilmstripModel.tileSize.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Slide \(index + 1) of \(count), lines \(slide.lineRange)")
        )
        .accessibilityValue(isShort ? Text("short") : Text(verbatim: ""))
        .accessibilityIdentifier("carousel-slide-tile-\(index)")
    }

    private func pill(_ label: Text) -> some View {
        label
            .font(.system(size: VitrineTokens.FontSize.caption, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(4)
    }
}

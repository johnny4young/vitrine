import CoreGraphics
import Observation
import VitrineDomain
import VitrineRendering

/// The multi-size sheet's tiles: each selected preset rendered as its export would be.
/// Renders run on the main actor like the export, one preset per turn after a quiet window,
/// and stop at the next preset once their task is cancelled. A tile is redrawn only when its
/// content or its crop changes, so moving the focal point skips every size it doesn't reframe.
@Observable
final class EverySizeBoardModel {
    struct Tile: Equatable {
        var image: CGImage
        var geometry: FocalTileGeometry
    }

    struct Renderer {
        /// The content with its padding at its ideal size.
        var measure: (SnapshotConfig) -> CGSize
        var draw: (SnapshotConfig, ExportPreset, FocalCrop?) -> CGImage?
    }

    /// A tile at this size takes about 60 ms in a Debug build, 75 ms with a crop; at 4 KB it is
    /// 170–250 ms, long enough to stall the sheet on every release of a drag.
    static let maximumRenderedBytes = 2 * 1024
    static let tilePixels: CGFloat = 320

    private(set) var tiles: [String: Tile] = [:]

    private struct Key: Equatable {
        var content: SnapshotConfig
        var crop: FocalCrop?
    }

    @ObservationIgnored private var naturals: [String: (content: SnapshotConfig, size: CGSize)] =
        [:]
    @ObservationIgnored private var renderedKeys: [String: Key] = [:]
    @ObservationIgnored private var currentRun = 0
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let renderer: Renderer

    init(debounce: Duration = .milliseconds(150), renderer: Renderer = .live) {
        self.debounce = debounce
        self.renderer = renderer
    }

    func render(_ presets: [ExportPreset], for config: SnapshotConfig) async {
        currentRun += 1
        let run = currentRun
        guard config.code.utf8.count <= Self.maximumRenderedBytes else { return }
        try? await Task.sleep(for: debounce)
        for preset in presets {
            guard !Task.isCancelled, run == currentRun else { return }
            var content = config
            content.focalPoint = nil
            preset.apply(to: &content)
            let natural: CGSize
            if let cached = naturals[preset.id], cached.content == content {
                natural = cached.size
            } else {
                natural = renderer.measure(content)
                naturals[preset.id] = (content, natural)
            }
            var focused = content
            focused.focalPoint = config.focalPoint
            let fixedSize = preset.sizing.fixedSize
            let crop = ExportManager.focalCrop(focused, fixedSize: fixedSize, natural: natural)
            let key = Key(content: content, crop: crop)
            guard renderedKeys[preset.id] != key else { continue }
            if let image = renderer.draw(focused, preset, crop) {
                tiles[preset.id] = Tile(
                    image: image,
                    geometry: FocalTileGeometry(
                        frame: fixedSize ?? natural, natural: natural, crop: crop,
                        wrapsToWidth: !content.usesImageContent))
                renderedKeys[preset.id] = key
            } else {
                tiles[preset.id] = nil
                renderedKeys[preset.id] = nil
            }
            await Task.yield()
        }
    }

    func stop() {
        currentRun += 1
    }
}

extension EverySizeBoardModel.Renderer {
    static let live = EverySizeBoardModel.Renderer(
        measure: { ExportManager.naturalCanvasSize($0) },
        draw: { config, preset, crop in
            guard let frame = preset.sizing.fixedSize, frame.width > 0, frame.height > 0 else {
                return nil
            }
            return try? ExportManager.renderCGImageChecked(
                config, scale: EverySizeBoardModel.tilePixels / max(frame.width, frame.height),
                fixedSize: frame, crop: crop, budget: .preview)
        })
}

/// Maps between a tile's frame and the focal point, normalized over the content and its
/// padding, using the crop the tile was rendered through.
struct FocalTileGeometry: Equatable {
    var frame: CGSize
    var natural: CGSize
    var crop: FocalCrop?
    var wrapsToWidth = true

    /// Code wider than its frame wraps, so the tile doesn't show the layout the point maps to.
    var acceptsFocalPoint: Bool {
        crop != nil || !wrapsToWidth || natural.width.rounded(.up) <= frame.width
    }

    private var contentOrigin: CGPoint {
        let canvas = crop?.canvasSize ?? frame
        let origin = crop?.origin ?? .zero
        return CGPoint(
            x: (canvas.width - natural.width) / 2 - origin.x,
            y: (canvas.height - natural.height) / 2 - origin.y)
    }

    func point(for focal: CGPoint) -> CGPoint {
        CGPoint(
            x: contentOrigin.x + focal.x * natural.width,
            y: contentOrigin.y + focal.y * natural.height)
    }

    func focal(at point: CGPoint) -> CGPoint {
        func unit(_ value: CGFloat, _ length: CGFloat) -> CGFloat {
            length > 0 ? min(max(value / length, 0), 1) : 0.5
        }
        return CGPoint(
            x: unit(point.x - contentOrigin.x, natural.width),
            y: unit(point.y - contentOrigin.y, natural.height))
    }
}

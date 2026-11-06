import CoreGraphics
import Observation
import VitrineDomain
import VitrineRendering

/// The multi-size sheet's tiles: each selected preset rendered as its export would be.
/// Renders run on the main actor like the export, one preset per turn after a quiet window,
/// and stop at the next preset once their task is cancelled. A tile is kept until its input
/// changes, and shown until its replacement is ready.
@Observable
final class EverySizeBoardModel {
    struct Tile: Equatable {
        var image: CGImage
        var geometry: FocalTileGeometry
    }

    /// Render cost grows with the document, so a long one shows sizes without pictures.
    static let maximumRenderedBytes = 16 * 1024
    static let tilePixels: CGFloat = 320

    private(set) var tiles: [String: Tile] = [:]

    @ObservationIgnored private var renderedInputs: [String: SnapshotConfig] = [:]
    @ObservationIgnored private var currentRun = 0
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let renderTile: (ExportPreset, SnapshotConfig) -> Tile?

    init(
        debounce: Duration = .milliseconds(150),
        renderTile: @escaping (ExportPreset, SnapshotConfig) -> Tile? = { preset, config in
            EverySizeBoardModel.tile(preset, config)
        }
    ) {
        self.debounce = debounce
        self.renderTile = renderTile
    }

    func render(_ presets: [ExportPreset], for config: SnapshotConfig) async {
        currentRun += 1
        let run = currentRun
        guard config.code.utf8.count <= Self.maximumRenderedBytes else { return }
        let missing = presets.filter { renderedInputs[$0.id] != config }
        guard !missing.isEmpty else { return }
        try? await Task.sleep(for: debounce)
        for preset in missing {
            guard !Task.isCancelled, run == currentRun else { return }
            if let tile = renderTile(preset, config) {
                tiles[preset.id] = tile
                renderedInputs[preset.id] = config
            }
            await Task.yield()
        }
    }

    func stop() {
        currentRun += 1
    }

    static func tile(_ preset: ExportPreset, _ base: SnapshotConfig) -> Tile? {
        var config = base
        preset.apply(to: &config)
        let natural = ExportManager.naturalCanvasSize(config)
        let frame = preset.sizing.fixedSize ?? natural
        guard frame.width > 0, frame.height > 0,
            let image = try? ExportManager.renderCGImageChecked(
                config, scale: tilePixels / max(frame.width, frame.height),
                fixedSize: preset.sizing.fixedSize, budget: .preview)
        else { return nil }
        let crop = config.focalPoint.flatMap { focal in
            FocalCrop.isBlocked(for: config)
                ? nil
                : FocalCrop.crop(
                    natural: natural, frame: frame, focal: focal,
                    wrapsToWidth: !config.usesImageContent)
        }
        return Tile(
            image: image, geometry: FocalTileGeometry(frame: frame, natural: natural, crop: crop))
    }
}

/// Maps between a tile's frame and the focal point, normalized over the content and its
/// padding, using the crop the tile was rendered through.
struct FocalTileGeometry: Equatable {
    var frame: CGSize
    var natural: CGSize
    var crop: FocalCrop?

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

import SwiftUI
import VitrineDomain

/// Where a fixed frame too small for its content looks: the content is laid out whole on a
/// canvas at least as large as the frame, and the frame shows the window around the focal
/// point. A frame the content fits is never reframed, so it renders as without a focal point.
public struct FocalCrop: Equatable, Sendable {
    /// The canvas the content is laid out on whole.
    public var canvasSize: CGSize
    /// The frame's top-left corner on that canvas.
    public var origin: CGPoint

    /// Annotations and slide badges sit at fixed canvas positions, so moving the window would
    /// slide the content out from under a blur box or an arrow.
    public static func isBlocked(for config: SnapshotConfig) -> Bool {
        !config.annotations.isEmpty || config.slideCue != nil
    }

    /// `natural` is the content with its padding at its ideal size. Code wraps to a narrower
    /// frame, and that height can't be known here, so code reframes only vertically.
    public static func crop(
        natural: CGSize, frame: CGSize, focal: CGPoint, wrapsToWidth: Bool
    ) -> FocalCrop? {
        let content = CGSize(width: natural.width.rounded(.up), height: natural.height.rounded(.up))
        guard content.width > frame.width || content.height > frame.height else { return nil }
        if wrapsToWidth, content.width > frame.width { return nil }
        let canvas = CGSize(
            width: max(frame.width, content.width), height: max(frame.height, content.height))
        func axis(
            _ canvas: CGFloat, _ content: CGFloat, _ frame: CGFloat, _ focal: CGFloat
        )
            -> CGFloat
        {
            let point = (canvas - content) / 2 + min(max(focal, 0), 1) * content
            return min(max(point - frame / 2, 0), canvas - frame).rounded()
        }
        return FocalCrop(
            canvasSize: canvas,
            origin: CGPoint(
                x: axis(canvas.width, content.width, frame.width, focal.x),
                y: axis(canvas.height, content.height, frame.height, focal.y)))
    }
}

/// The content laid out whole on the crop's canvas, seen through the frame. The background,
/// watermark and frame clip match the plain fixed-size canvas.
struct FocalCroppedCanvas: View {
    let config: SnapshotConfig
    let frame: CGSize
    let crop: FocalCrop

    var body: some View {
        SnapshotCanvas(config: Self.content(of: config), fixedSize: crop.canvasSize)
            .offset(x: -crop.origin.x, y: -crop.origin.y)
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .background(BackgroundView(style: config.background))
            .clipped()
            .modifier(WatermarkOverlay(watermark: config.watermark))
    }

    static func content(of config: SnapshotConfig) -> SnapshotConfig {
        var content = config
        content.background = .transparent
        content.watermark = nil
        content.focalPoint = nil
        return content
    }
}

extension ExportManager {
    /// The content and its padding at their ideal size, before any frame.
    public static func naturalCanvasSize(
        _ config: SnapshotConfig,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer
    ) -> CGSize {
        var natural = CGSize.zero
        ImageRenderer(
            content: SnapshotCanvas(config: FocalCroppedCanvas.content(of: config))
                .environment(\.backgroundImageStore, backgroundImageStore)
                .environment(\.foregroundImageStore, foregroundImageStore)
        ).render { size, _ in natural = size }
        return natural
    }

    /// The crop `config` renders through at `fixedSize`, or `nil` when it renders unchanged.
    public static func focalCrop(
        _ config: SnapshotConfig, fixedSize: CGSize?,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer
    ) -> FocalCrop? {
        guard let focal = config.focalPoint, let fixedSize, !FocalCrop.isBlocked(for: config)
        else { return nil }
        let natural = naturalCanvasSize(
            config, backgroundImageStore: backgroundImageStore,
            foregroundImageStore: foregroundImageStore)
        return FocalCrop.crop(
            natural: natural, frame: fixedSize, focal: focal,
            wrapsToWidth: !config.usesImageContent)
    }
}

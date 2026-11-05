import SwiftUI
import VitrineDomain

extension ExportManager {
    /// Renders `config` through the real canvas at exactly `pixels`' proportions. The canvas's
    /// background grows to fill them, so the whole card shows and nothing is cropped.
    public static func renderThumbnail(
        _ config: SnapshotConfig, pixels: CGSize,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer
    ) -> CGImage? {
        func canvas(_ fixedSize: CGSize?) -> some View {
            SnapshotCanvas(config: config, fixedSize: fixedSize)
                .environment(\.backgroundImageStore, backgroundImageStore)
                .environment(\.foregroundImageStore, foregroundImageStore)
        }
        var natural = CGSize.zero
        ImageRenderer(content: canvas(nil)).render { size, _ in natural = size }
        guard natural.width > 0, natural.height > 0 else { return nil }

        let aspect = pixels.width / pixels.height
        let width = max(natural.width, natural.height * aspect)
        let frame = CGSize(width: width, height: width / aspect)
        return try? renderCGImageChecked(
            canvas(frame), proposedSize: frame, scale: min(1, pixels.width / width),
            profile: .sRGB, budget: .preview)
    }
}

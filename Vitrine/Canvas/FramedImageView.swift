import SwiftUI

/// Renders a beautified **foreground image** (the "beautify any image" feature) wrapped
/// in an optional window/browser frame, sitting where the code card would.
///
/// The image is resolved by reference through `foregroundImageStore` (the same
/// default-real / inject-in-tests contract as image backgrounds), so an export resolves
/// it from the app container and a test resolves a fixture without touching it. A missing
/// file degrades to a neutral placeholder rather than blanking the canvas.
///
/// The enclosing `SnapshotCanvas.imageCard` applies the corner radius, border, and shadow,
/// so this view only produces the frame chrome + image content.
struct FramedImageView: View {
    let reference: ImageReference
    let frame: ImageFrame
    /// Reuses `SnapshotConfig.windowTitle` as the window title / browser address text.
    var title: String = ""

    @Environment(\.foregroundImageStore) private var store

    /// Cap the displayed width so an oversized screenshot doesn't blow up the canvas; the
    /// @2x export still captures ample detail. A smaller image is never upscaled.
    private static let maxImageWidth: CGFloat = 1100

    private static let barColor = Color(hex: "#E8E8EA")
    private static let pillColor = Color(hex: "#FDFDFF")
    private static let barTextColor = Color(hex: "#3C3C43")

    var body: some View {
        if let image = store.image(for: reference) {
            content(image)
        } else {
            missingPlaceholder
        }
    }

    @ViewBuilder
    private func content(_ image: NSImage) -> some View {
        let display = displaySize(for: image)
        switch frame {
        case .none:
            imageView(image, size: display)
        case .macOSWindow:
            VStack(spacing: 0) {
                windowBar
                imageView(image, size: display)
            }
            .frame(width: display.width)
        case .browser:
            VStack(spacing: 0) {
                browserBar
                imageView(image, size: display)
            }
            .frame(width: display.width)
        }
    }

    private func imageView(_ image: NSImage, size: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
    }

    /// A macOS title bar: traffic-light dots, with the optional title centered.
    private var windowBar: some View {
        ZStack {
            HStack(spacing: 0) {
                chromeDots
                Spacer(minLength: 0)
            }
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Self.barTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 44)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Self.barColor)
    }

    /// A browser toolbar: traffic-light dots plus a faux address pill carrying the title.
    private var browserBar: some View {
        HStack(spacing: 12) {
            chromeDots
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Self.barTextColor.opacity(0.45))
                Text(verbatim: title)
                    .font(.system(size: 11))
                    .foregroundStyle(Self.barTextColor.opacity(title.isEmpty ? 0 : 1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(Self.pillColor))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Self.barColor)
    }

    private var chromeDots: some View {
        HStack(spacing: Brand.Spacing.xs) {
            dot(Color(hex: "#FF5F56"))
            dot(Color(hex: "#FFBD2E"))
            dot(Color(hex: "#27C93F"))
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 12, height: 12)
    }

    /// Shown when the referenced file can't be resolved (missing/relocated), mirroring the
    /// background path's graceful degradation.
    private var missingPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(Self.barTextColor.opacity(0.5))
            Text("Image unavailable")
                .font(.system(size: 12))
                .foregroundStyle(Self.barTextColor.opacity(0.6))
        }
        .frame(width: 320, height: 200)
        .background(Self.barColor)
    }

    /// The logical display size: the image's own size, scaled down only if wider than
    /// `maxImageWidth` (aspect preserved). Falls back to a sane box for a zero-sized image.
    private func displaySize(for image: NSImage) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return CGSize(width: 320, height: 200) }
        guard size.width > Self.maxImageWidth else { return size }
        let scale = Self.maxImageWidth / size.width
        return CGSize(width: Self.maxImageWidth, height: (size.height * scale).rounded())
    }
}

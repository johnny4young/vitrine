import SwiftUI

/// Renders a beautified **foreground image** (the "beautify any image" feature) wrapped
/// in an optional window / browser / device frame, sitting where the code card would.
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
    /// Chrome tint: `.auto` samples the image's top edge so the bar blends with the
    /// screenshot; `.light`/`.dark` are fixed overrides.
    var appearance: FrameAppearance = .auto
    /// Reuses `SnapshotConfig.windowTitle` as the window title / browser address text.
    var title: String = ""

    @Environment(\.foregroundImageStore) private var store

    /// Cap the displayed width so an oversized screenshot doesn't blow up the canvas; the
    /// @2x export still captures ample detail. A smaller image is never upscaled.
    private static let maxImageWidth: CGFloat = 1100

    /// Resolves the chrome for an image — for `.auto`, sampled from that image's top edge.
    private func chrome(for image: NSImage) -> FrameChrome {
        // Fixed appearances resolve to a static `light`/`dark` without touching the
        // pixels, so there is nothing to cache.
        guard appearance == .auto else { return FrameChrome.of(appearance, image: image) }
        // `.auto` decodes the full bitmap to sample a 1×1 top-edge average
        // (`FrameChrome.topEdgeColor`) — otherwise re-run on every `body` pass (a slider
        // drag, typing). The foreground image's file name is the SHA-256 of its bytes
        // (content-addressed, immutable), so cache the resolved chrome by that name, the
        // same reasoning as `BackgroundImageStore`'s decoded-image cache (P1).
        let key = reference.fileName as NSString
        if let cached = Self.autoChromeCache.object(forKey: key) { return cached.chrome }
        let resolved = FrameChrome.of(.auto, image: image)
        Self.autoChromeCache.setObject(FrameChromeBox(resolved), forKey: key)
        return resolved
    }

    /// Process-wide cache of resolved `.auto` chrome, keyed by the content-addressed
    /// (SHA-256) foreground image file name, so a given name maps to one immutable
    /// sample. Mirrors `BackgroundImageStore.imageCache` (P1).
    @MainActor private static let autoChromeCache = NSCache<NSString, FrameChromeBox>()

    var body: some View {
        if let image = store.image(for: reference) {
            content(image)
        } else {
            missingPlaceholder
        }
    }

    @ViewBuilder
    private func content(_ image: NSImage) -> some View {
        let chrome = chrome(for: image)
        switch frame {
        case .none:
            imageView(image, size: displaySize(for: image))
        case .macOSWindow:
            let display = displaySize(for: image)
            VStack(spacing: 0) {
                windowBar(chrome)
                imageView(image, size: display)
            }
            .frame(width: display.width)
            // Fill behind the bar + image with the chrome color so a sub-pixel seam at the
            // rounded clip never lets the background bleed through as a thin line.
            .background(chrome.bar)
        case .browser:
            let display = displaySize(for: image)
            VStack(spacing: 0) {
                browserBar(chrome)
                imageView(image, size: display)
            }
            .frame(width: display.width)
            .background(chrome.bar)
        case .macBook:
            LaptopFrameView(image: image, chrome: chrome)
        case .iPhone:
            PhoneFrameView(image: image, chrome: chrome)
        }
    }

    private func imageView(_ image: NSImage, size: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
    }

    /// A macOS title bar: traffic-light dots, with the optional title centered.
    private func windowBar(_ chrome: FrameChrome) -> some View {
        ZStack {
            HStack(spacing: 0) {
                chromeDots
                Spacer(minLength: 0)
            }
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(chrome.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 44)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(chrome.bar)
    }

    /// A browser toolbar: traffic-light dots plus a faux address pill carrying the title.
    private func browserBar(_ chrome: FrameChrome) -> some View {
        HStack(spacing: 12) {
            chromeDots
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(chrome.text.opacity(0.45))
                Text(verbatim: title)
                    .font(.system(size: 11))
                    .foregroundStyle(chrome.text.opacity(title.isEmpty ? 0 : 1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(chrome.pill))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(chrome.bar)
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
    /// background path's graceful degradation. With no image to sample, Auto falls back to dark.
    private var missingPlaceholder: some View {
        // No image to sample, so resolve chrome directly (Auto falls back to dark); the
        // cache in `chrome(for:)` is only for the real-image path.
        let chrome = FrameChrome.of(appearance, image: nil)
        return VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(chrome.text.opacity(0.5))
            Text("Image unavailable")
                .font(.system(size: 12))
                .foregroundStyle(chrome.text.opacity(0.6))
        }
        .frame(width: 320, height: 200)
        .background(chrome.bar)
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

/// Boxes a `FrameChrome` value so it can be stored in an `NSCache`, which holds
/// objects. The box lives only inside the `@MainActor` `autoChromeCache` and is never
/// sent across an actor, so it needs no `Sendable` conformance.
private final class FrameChromeBox {
    let chrome: FrameChrome
    init(_ chrome: FrameChrome) { self.chrome = chrome }
}

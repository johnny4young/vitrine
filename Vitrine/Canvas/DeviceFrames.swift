import SwiftUI

/// The resolved chrome colors for a framed image, derived from `FrameAppearance`. Shared by
/// the window/browser bars (`FramedImageView`) and the vector device mockups below so light
/// and dark frames stay consistent.
struct FrameChrome {
    /// The window/browser title-bar fill.
    let bar: Color
    /// The browser address-pill fill.
    let pill: Color
    /// The bar text / icon color.
    let text: Color
    /// The device body (aluminum / titanium) tint.
    let deviceBody: Color
    /// The black border around a device screen (constant across appearances).
    let screenBezel: Color

    static let screenBezelColor = Color(hex: "#0A0A0C")

    static let light = FrameChrome(
        bar: Color(hex: "#E8E8EA"),
        pill: Color(hex: "#FDFDFF"),
        text: Color(hex: "#3C3C43"),
        deviceBody: Color(hex: "#D7D8DC"),
        screenBezel: screenBezelColor)

    static let dark = FrameChrome(
        bar: Color(hex: "#2B2B2E"),
        pill: Color(hex: "#3A3A3D"),
        text: Color(hex: "#E7E7EC"),
        deviceBody: Color(hex: "#48484B"),
        screenBezel: screenBezelColor)

    /// Resolves the chrome for an appearance. `.auto` samples `image`'s top edge so the bar
    /// blends with the screenshot; a nil image or a failed sample falls back to `dark`.
    static func of(_ appearance: FrameAppearance, image: NSImage? = nil) -> FrameChrome {
        switch appearance {
        case .light: light
        case .dark: dark
        case .auto:
            if let image, let color = topEdgeColor(of: image) { auto(from: color) } else { dark }
        }
    }

    /// Builds chrome from a sampled bar color: the text/pill/device tints are derived from
    /// the color's luminance so the bar stays legible whether the sample is light or dark.
    static func auto(from color: Color) -> FrameChrome {
        let light = luminance(color) > 0.6
        return FrameChrome(
            bar: color,
            pill: light ? Color.white.opacity(0.85) : Color.white.opacity(0.14),
            text: light ? Color(hex: "#2A2A30") : Color(hex: "#F2F2F6"),
            deviceBody: light ? Color(hex: "#D7D8DC") : Color(hex: "#48484B"),
            screenBezel: screenBezelColor)
    }

    /// Average color of the image's top strip, used to tint Auto chrome so the bar continues
    /// the screenshot. `nil` when the image can't be read. Pure (a function of the pixels), so
    /// the render stays deterministic and golden-friendly.
    static func topEdgeColor(of image: NSImage) -> Color? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let stripHeight = max(1, cg.height / 12)
        guard
            let strip = cg.cropping(
                to: CGRect(x: 0, y: 0, width: cg.width, height: stripHeight))
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard
            let ctx = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = CGFloat(pixel[3]) / 255
        guard alpha > 0 else { return nil }
        // Un-premultiply so a translucent edge still yields its true hue.
        return Color(
            .sRGB,
            red: Double(CGFloat(pixel[0]) / 255 / alpha),
            green: Double(CGFloat(pixel[1]) / 255 / alpha),
            blue: Double(CGFloat(pixel[2]) / 255 / alpha))
    }

    private static func luminance(_ color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return 0.2126 * Double(ns.redComponent) + 0.7152 * Double(ns.greenComponent)
            + 0.0722 * Double(ns.blueComponent)
    }
}

/// A vector iPhone mockup: the image fills a phone-shaped screen inside a rounded body with a
/// Dynamic Island. Pure SwiftUI shapes — no bundled artwork, so it stays crisp at any export
/// scale and carries no licensing. The device defines its own size (phone aspect); the image
/// is scaled to fill and clipped to the screen.
struct PhoneFrameView: View {
    let image: NSImage
    let chrome: FrameChrome

    var body: some View {
        let screenW: CGFloat = 280
        let screenH = (screenW * 852.0 / 393.0).rounded()
        let bezel: CGFloat = 13
        let bodyW = screenW + bezel * 2
        let bodyH = screenH + bezel * 2

        ZStack {
            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(chrome.deviceBody)
                .frame(width: bodyW, height: bodyH)
            RoundedRectangle(cornerRadius: 49, style: .continuous)
                .fill(chrome.screenBezel)
                .frame(width: screenW + 7, height: screenH + 7)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: 45, style: .continuous))
            Capsule()
                .fill(Color.black)
                .frame(width: 78, height: 24)
                .offset(y: -screenH / 2 + 20)
        }
        .frame(width: bodyW, height: bodyH)
    }
}

/// A vector MacBook mockup: the image as the screen inside an aluminum lid, over a hinge base
/// with the iconic opening notch. Pure SwiftUI shapes for the same reasons as `PhoneFrameView`.
struct LaptopFrameView: View {
    let image: NSImage
    let chrome: FrameChrome

    var body: some View {
        let screenW: CGFloat = 560
        let screenH = (screenW * 10.0 / 16.0).rounded()
        let bezel: CGFloat = 12
        let lidW = screenW + bezel * 2
        let lidH = screenH + bezel * 2
        let baseW = lidW + 86
        let baseH: CGFloat = 14

        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(chrome.deviceBody)
                    .frame(width: lidW, height: lidH)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chrome.screenBezel)
                    .frame(width: screenW + 8, height: screenH + 8)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: screenW, height: screenH)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 2, bottomLeadingRadius: 10, bottomTrailingRadius: 10,
                    topTrailingRadius: 2, style: .continuous
                )
                .fill(chrome.deviceBody)
                .frame(width: baseW, height: baseH)
                // The lid-opening notch: a shallow indent at the top-center of the base.
                Capsule()
                    .fill(chrome.screenBezel.opacity(0.22))
                    .frame(width: 96, height: 5)
                    .offset(y: -baseH / 2 + 3)
            }
        }
    }
}

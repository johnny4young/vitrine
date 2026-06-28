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

    static func of(_ appearance: FrameAppearance) -> FrameChrome {
        switch appearance {
        case .light:
            FrameChrome(
                bar: Color(hex: "#E8E8EA"),
                pill: Color(hex: "#FDFDFF"),
                text: Color(hex: "#3C3C43"),
                deviceBody: Color(hex: "#D7D8DC"),
                screenBezel: Color(hex: "#0A0A0C"))
        case .dark:
            FrameChrome(
                bar: Color(hex: "#2B2B2E"),
                pill: Color(hex: "#3A3A3D"),
                text: Color(hex: "#E7E7EC"),
                deviceBody: Color(hex: "#48484B"),
                screenBezel: Color(hex: "#0A0A0C"))
        }
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

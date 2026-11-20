import SwiftUI
import VitrineDomain

/// One page of a carousel export: a code slide, with an optional caption band under the
/// capture, or a cover or closing card drawn by the social card renderer.
public enum CarouselPage: Equatable {
    case slide(SnapshotConfig, caption: String?)
    case card(SocialCardModel)

    var background: VitrineDomain.BackgroundStyle {
        switch self {
        case .slide(let config, _): config.background
        case .card(let model): model.background
        }
    }

    public static let captionLines = 3

    public static func captionFontSize(for size: CGSize) -> CGFloat {
        (min(size.width, size.height) * 0.037).rounded()
    }

    /// Three lines of caption and a bottom margin, the same on every page of the carousel,
    /// so the fitted type and the card's place don't depend on any one caption.
    public static func captionBandHeight(for size: CGSize) -> CGFloat {
        (captionFontSize(for: size) * 1.25 * CGFloat(captionLines)
            + min(size.width, size.height) * 0.05).rounded()
    }
}

/// Draws a captioned slide or a card at the slide's frame. An uncaptioned slide never comes
/// here: the export draws it as a plain `SnapshotCanvas`, so its pixels don't change.
struct CarouselPageCanvas: View {
    let page: CarouselPage
    let size: CGSize

    var body: some View {
        switch page {
        case .slide(let config, let caption):
            captioned(config, caption: caption ?? "")
        case .card(let model):
            SocialCardCanvas(model: model, size: size)
        }
    }

    private func captioned(_ config: SnapshotConfig, caption: String) -> some View {
        let band = CarouselPage.captionBandHeight(for: size)
        let short = min(size.width, size.height)
        var capture = config
        capture.background = .transparent
        return VStack(spacing: 0) {
            SnapshotCanvas(
                config: capture, fixedSize: CGSize(width: size.width, height: size.height - band))
            Text(verbatim: caption)
                .font(.system(size: CarouselPage.captionFontSize(for: size), weight: .semibold))
                .foregroundStyle(isLight(config.background) ? Color.black.opacity(0.88) : .white)
                .brandShadow(
                    isLight(config.background)
                        ? Brand.ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
                        : Brand.ShadowStyle(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
                )
                .multilineTextAlignment(.center)
                .lineLimit(CarouselPage.captionLines)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, short * 0.08)
                .frame(width: size.width, height: band, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .background(BackgroundView(style: config.background))
        .clipped()
    }

    /// The social card's rule: dark copy only over a light solid color.
    private func isLight(_ background: VitrineDomain.BackgroundStyle) -> Bool {
        guard case .solid(let color) = background else { return false }
        return Brand.Contrast.relativeLuminance(color.color) > 0.55
    }
}

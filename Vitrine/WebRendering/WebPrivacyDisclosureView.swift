import SwiftUI
import VitrineRendering

/// The first-use privacy disclosure shown before Vitrine captures a webpage.
///
/// URL capture is the web-capture capability, and the moment the app reaches the
/// network it changes the product promise. This view is the user-facing half of
/// keeping that change honest and reviewable: before any page loads, it states the
/// two facts that matter — code capture still never leaves the Mac, and a URL capture
/// loads the requested webpage **locally in WebKit on this Mac**, with no remote
/// screenshot service and no analytics. The user then explicitly confirms or
/// cancels; nothing loads until they confirm.
///
/// ## Single source of words
///
/// The disclosure title, body, and button labels come from
/// `WebSnapshotConfig.firstUseDisclosure`, which builds them from the String
/// Catalog so the copy localizes and is asserted in tests. This view never
/// hard-codes that wording; it only adds the local rendering reminder line and lays the
/// pieces out, so the reviewable privacy sentence lives in exactly one place and is
/// reused wherever the disclosure appears.
///
/// ## Presentation
///
/// The Web Snapshot window hosts this in a modal `.sheet` on the first URL capture,
/// persists the confirmation in `AppSettings.webCapture.consentGiven`, and lets
/// `onConfirm` gate the load. It is presented only where URL capture is available
/// (`NetworkCapability`); a build without network client access fails the capture
/// with an explanation instead of offering a confirmation it cannot honor.
struct WebPrivacyDisclosureView: View {
    /// Called when the user confirms; the caller proceeds with the capture.
    let onConfirm: () -> Void

    /// Called when the user cancels; nothing is loaded.
    let onCancel: () -> Void

    /// The reviewable, localized copy. Sourced once from `WebSnapshotConfig` so the
    /// privacy sentence is identical everywhere it is shown.
    private var disclosure: WebSnapshotConfig.FirstUseDisclosure {
        WebSnapshotConfig.firstUseDisclosure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            header

            // The body paragraph is the one privacy fact that matters: the page is
            // loaded locally in WebKit and rasterized on-device, with no remote
            // screenshot service.
            Text(disclosure.message)
                .font(.body)
                .foregroundStyle(Brand.Palette.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)

            promiseRow

            actions
        }
        .padding(Brand.Spacing.xl)
        // A width *range* rather than a hard width: the body and promise lines are long,
        // the Spanish copy is materially longer, and larger Dynamic Type sizes widen the
        // text further, so a fixed 420 pt forced extra wrapping that could push content
        // past the card's rounded background. The range lets the card breathe to 460 pt
        // when it needs to while height grows freely with the content.
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)
        .background(Brand.Surface.raised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Radius.lg)
                .strokeBorder(Brand.Palette.border.color, lineWidth: Brand.Stroke.hairline)
        )
        .brandShadow(Brand.Shadow.card)
        // Expose the whole card as one labeled group so VoiceOver announces it as a
        // single disclosure (its presenter hosts it in a modal sheet, which adds the
        // "asking a question" framing and focus trapping).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(disclosure.title)
        .accessibilityIdentifier("web-privacy-disclosure")
    }

    /// The brand mark paired with the disclosure title, collapsed into one VoiceOver
    /// element so the user hears the question as a single announcement.
    private var header: some View {
        HStack(spacing: Brand.Spacing.sm) {
            BrandMark(size: 28)
            Text(disclosure.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.Palette.textPrimary.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The local rendering reminder: code capture stays entirely on the Mac. Phrasing it
    /// here keeps the promise visible the first time the network is ever used, so
    /// the user sees that URL capture is the deliberate exception, not a change to
    /// how their code is handled.
    private var promiseRow: some View {
        Label {
            Text(
                "Your code still never leaves your Mac — this only loads the webpage you asked for."
            )
            .font(.callout)
            .foregroundStyle(Brand.Palette.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(Brand.Palette.accent.color)
        }
        .accessibilityElement(children: .combine)
    }

    /// Cancel and the capture confirmation, the prominent default action.
    private var actions: some View {
        HStack(spacing: Brand.Spacing.sm) {
            Spacer()
            Button(disclosure.cancelTitle, role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
                .help("Don't capture; nothing is loaded.")
                .accessibilityIdentifier("web-privacy-cancel")

            Button(disclosure.confirmTitle, action: onConfirm)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Load this webpage locally in WebKit and capture it.")
                .accessibilityIdentifier("web-privacy-confirm")
        }
    }
}

#Preview("Privacy disclosure") {
    WebPrivacyDisclosureView(onConfirm: {}, onCancel: {})
        .padding(Brand.Spacing.xxl)
        .background(Brand.Palette.stage.color)
}

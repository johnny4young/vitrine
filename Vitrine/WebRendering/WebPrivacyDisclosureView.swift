import SwiftUI

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
/// ## Capability-aware
///
/// The confirm action is enabled only when the build can actually reach the network
/// (`NetworkCapability.isURLCaptureEnabled`). A network-free build shows the same
/// disclosure with the action disabled and an explicit direct-download note, so the
/// UI never implies a capability the build does not have.
///
/// ## Presentation
///
/// The Web Snapshot window hosts this in a modal `.sheet` on the first URL capture,
/// persists the confirmation in `AppSettings.webCapture.consentGiven`, and lets
/// `onConfirm` gate the load. URL capture itself stays gated on the network
/// entitlement (`NetworkCapability`): the App Store build ships without
/// `com.apple.security.network.client`, so there the confirm action is disabled and
/// the disclosure explains that capture is only available in the direct-download
/// build.
struct WebPrivacyDisclosureView: View {
    /// Called when the user confirms; the caller proceeds with the capture. Only
    /// reachable when the build can reach the network.
    let onConfirm: () -> Void

    /// Called when the user cancels; nothing is loaded.
    let onCancel: () -> Void

    /// Whether this build can actually reach the network for a capture. Injectable
    /// so the disclosure renders in both states for previews and tests; defaults to
    /// the running app's real entitlement, so production matches the build.
    var isURLCaptureEnabled: Bool = NetworkCapability.isURLCaptureEnabled

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

            // In a network-free build the action is disabled; say why, plainly,
            // rather than leaving a dead button unexplained.
            if !isURLCaptureEnabled {
                networkUnavailableNote
            }

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

    /// Shown only in a build without the network entitlement: the direct-download
    /// channel can capture webpages, while a network-free build refuses plainly so
    /// the disabled action is never a mystery.
    private var networkUnavailableNote: some View {
        Label {
            Text("Webpage capture requires the direct-download build with local network access.")
                .font(.callout)
                .foregroundStyle(Brand.Palette.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "network.slash")
                .foregroundStyle(Brand.Palette.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }

    /// Cancel (always available) and the capture confirmation (enabled only when the
    /// build can reach the network). The confirm button stays the prominent default
    /// action so a capable build reads as ready to proceed.
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
                .disabled(!isURLCaptureEnabled)
                .help(confirmHelp)
                .accessibilityIdentifier("web-privacy-confirm")
        }
    }

    /// The confirm button's tooltip, matching its state: in a capable build it names
    /// the action; in a network-free build (where the button is disabled) it gives the same
    /// reason as the inline note, so hovering the dead control is never a mystery.
    private var confirmHelp: LocalizedStringKey {
        isURLCaptureEnabled
            ? "Load this webpage locally in WebKit and capture it."
            : "Webpage capture requires the direct-download build with local network access."
    }
}

#Preview("Capture enabled") {
    WebPrivacyDisclosureView(onConfirm: {}, onCancel: {}, isURLCaptureEnabled: true)
        .padding(Brand.Spacing.xxl)
        .background(Brand.Palette.stage.color)
}

#Preview("local rendering (capture disabled)") {
    WebPrivacyDisclosureView(onConfirm: {}, onCancel: {}, isURLCaptureEnabled: false)
        .padding(Brand.Spacing.xxl)
        .background(Brand.Palette.stage.color)
}

import SwiftUI

/// PRO gating UI: a view modifier that lets a feature's call site stay clean —
/// when locked it intercepts the action and presents the paywall (and shows a discreet
/// "PRO" badge); when unlocked it passes straight through. Nothing here nags or interrupts
/// the free flow: the paywall appears only when the user reaches for a PRO action.
extension View {
    /// Gates `action` behind `feature`. Tapping runs `action` when unlocked, or opens the
    /// paywall for `feature` when locked. A small "PRO" badge marks the locked state.
    func proGated(_ feature: ProFeature, action: @escaping () -> Void) -> some View {
        modifier(ProGateModifier(feature: feature, action: action))
    }
}

private struct ProGateModifier: ViewModifier {
    let feature: ProFeature
    let action: () -> Void
    private let entitlements = Entitlements.shared
    @State private var showingPaywall = false

    func body(content: Content) -> some View {
        Button {
            if entitlements.isUnlocked(feature) {
                action()
            } else {
                showingPaywall = true
            }
        } label: {
            content.overlay(alignment: .topTrailing) {
                if !entitlements.isUnlocked(feature) { ProBadge() }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPaywall) { PaywallSheet(feature: feature) }
    }
}

/// A small "PRO" badge marking a locked affordance.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(VitrineTokens.Accent.contrast)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(VitrineTokens.Accent.base))
            .accessibilityLabel(Text("PRO feature"))
    }
}

/// The PRO upgrade sheet: reads the title and blurb from the `ProFeature` the user
/// reached for, then offers the per-build path to unlock — a StoreKit purchase + Restore on
/// the App Store build, or a license-key field on the direct-download build. Non-invasive:
/// it is only ever presented in response to a tap on a gated action, never on launch.
struct PaywallSheet: View {
    let feature: ProFeature
    private let entitlements = Entitlements.shared
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    #if VITRINE_DIRECT_DOWNLOAD
        @State private var licenseKey = ""
        @State private var activationFailed = false
    #else
        @State private var purchaseFailed = false
    #endif

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(VitrineTokens.Accent.base)
                Text(verbatim: "Vitrine PRO")
                    .font(.system(size: VitrineTokens.FontSize.headline, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
            }

            VStack(spacing: 6) {
                Text(feature.paywallTitle)
                    .font(.system(size: VitrineTokens.FontSize.subhead, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                Text(feature.paywallBlurb)
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            unlockControls

            Button(action: { dismiss() }) {
                Text("Not now")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Text("One-time purchase. The free version keeps every feature it has today.")
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 380)
        .background(VitrineTokens.Surface.window)
        .onChange(of: entitlements.isPro) {
            // Unlocked (a purchase or activation landed) → close the paywall.
            if entitlements.isPro { dismiss() }
        }
        // `.contain` keeps the children's identifiers reachable under the root id —
        // an id on a bare VStack propagates down and clobbers them (see
        // CarouselExportView; root-caused in the UI-test workflow notes).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro-paywall-sheet")
    }

    @ViewBuilder
    private var unlockControls: some View {
        #if VITRINE_DIRECT_DOWNLOAD
            VStack(spacing: 10) {
                // The buy path: open the Lemon Squeezy checkout. The license key arrives by
                // email; pasting it in the field below activates PRO (verified offline after).
                Link(destination: LemonSqueezyStore.checkoutURL) {
                    Text("Get Vitrine PRO").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("pro-get-license-button")

                TextField("Enter your license key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pro-license-field")
                Button {
                    Task {
                        working = true
                        let ok = await entitlements.activate(licenseKey: licenseKey)
                        activationFailed = !ok
                        working = false
                    }
                } label: {
                    Text("Activate").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(working || licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("pro-activate-button")
                .keyboardShortcut(.defaultAction)
                if activationFailed {
                    Text("That license key couldn't be activated. Check it and try again.")
                        .font(.system(size: VitrineTokens.FontSize.caption))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        #else
            VStack(spacing: 8) {
                Button {
                    Task {
                        working = true
                        purchaseFailed = false
                        purchaseFailed = await entitlements.purchase() == .failed
                        working = false
                    }
                } label: {
                    Text("Get Vitrine PRO").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(working)
                .accessibilityIdentifier("pro-buy-button")
                .keyboardShortcut(.defaultAction)
                Button {
                    Task {
                        working = true
                        await entitlements.restorePurchases()
                        working = false
                    }
                } label: {
                    Text("Restore Purchases")
                }
                .buttonStyle(.link)
                .disabled(working)
                .accessibilityIdentifier("pro-restore-button")
                if purchaseFailed {
                    Text("The purchase didn't complete. Please try again.")
                        .font(.system(size: VitrineTokens.FontSize.caption))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        #endif
    }
}

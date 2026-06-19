import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Brand Kit controls for the Style pane (CS-092).
///
/// Keeping the PRO-gated Brand Kit flow in its own section keeps the main Style pane
/// focused on layout and preview composition, while this view owns the paywall,
/// logo-import error, and Brand Kit bindings.
struct BrandKitSettingsSection: View {
    @ObservedObject var brandKit: BrandKitStore
    @ObservedObject var entitlements: Entitlements

    /// True while the Brand Kit upsell's paywall sheet is presented (CS-092).
    @State private var showingPaywall = false

    /// True when the last brand-kit logo pick failed to import (audit P1-UX-3).
    @State private var logoImportFailed = false

    var body: some View {
        if entitlements.isUnlocked(.brandKit) {
            controls
        } else {
            upsell
        }
    }

    private var controls: some View {
        TokenGroup(title: Text("Brand Kit")) {
            TokenRow(
                label: Text("Apply to captures"),
                caption: Text("Adds your mark to every exported image")
            ) {
                Toggle("Apply to captures", isOn: $brandKit.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("brand-kit-enabled-toggle")
            }
            TokenRow(label: Text("Logo"), caption: Text("Shown small in the chosen corner")) {
                logoControl
            }
            TokenRow(label: Text("Handle")) {
                TokenTextField(prompt: Text(verbatim: "@jane"), text: handle)
                    .accessibilityIdentifier("brand-kit-handle-field")
            }
            TokenRow(label: Text("Project")) {
                TokenTextField(prompt: Text(verbatim: "vitrine"), text: project)
                    .accessibilityIdentifier("brand-kit-project-field")
            }
            TokenRow(label: Text("Accent"), caption: Text("Tints the mark's text")) {
                HStack(spacing: 8) {
                    // A way back to the legible default — the model's `nil` accent
                    // (audit P1-UX-2).
                    if brandKit.brandKit.accent != nil {
                        Button("Reset") { brandKit.brandKit.accent = nil }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("brand-kit-accent-reset")
                    }
                    ColorPicker("Accent", selection: accent, supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityIdentifier("brand-kit-accent-picker")
                }
            }
            TokenRow(
                label: Text("Placement"),
                caption: brandKit.brandKit.placement == .free
                    ? Text("Drag the mark in the preview to place it anywhere.") : nil
            ) {
                Picker("Placement", selection: placement) {
                    ForEach(Watermark.Placement.allCases, id: \.self) { placement in
                        Text(placement.label).tag(placement)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("brand-kit-placement-picker")
            }
        }
        .accessibilityIdentifier("settings-brand-kit-controls")
    }

    /// The logo thumbnail (when set) plus Choose/Replace and Remove actions.
    @ViewBuilder private var logoControl: some View {
        HStack(spacing: 8) {
            if let logo = brandKit.logoImage {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Button("Remove") {
                    brandKit.removeLogo()
                    logoImportFailed = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(VitrineTokens.Text.secondary)
                .accessibilityIdentifier("brand-kit-remove-logo-button")
            }
            Button(brandKit.logoImage == nil ? "Choose…" : "Replace…") { pickLogo() }
                .accessibilityIdentifier("brand-kit-choose-logo-button")
            if logoImportFailed {
                Text("Couldn't load that image")
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(.red)
            }
        }
    }

    /// The locked state: a crown + PRO badge, the value blurb, and an unlock button
    /// that presents the shared `PaywallSheet` for the brand-kit feature (CS-091/092).
    private var upsell: some View {
        TokenGroup(title: Text("Brand Kit")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Brand Kit")
                        .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
                        .foregroundStyle(VitrineTokens.Text.primary)
                    ProBadge()
                }
                Text("Add your logo, handle, and accent color to every snapshot.")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showingPaywall = true
                } label: {
                    Text("Unlock Vitrine PRO")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("brand-kit-unlock-button")
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingPaywall) { PaywallSheet(feature: .brandKit) }
        .accessibilityIdentifier("settings-brand-kit-upsell")
    }

    /// Picks a logo image through an open panel and imports it into the container
    /// (CS-092), reusing the same content-addressed image store the backgrounds use.
    private func pickLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = String(localized: "Choose a logo image for your brand kit.")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        logoImportFailed = !brandKit.importLogo(from: url)
    }

    // Bindings into the app-global brand kit; mutating a field reassigns the whole
    // value, so the store persists and the preview refreshes (CS-092).
    private var handle: Binding<String> {
        Binding(get: { brandKit.brandKit.handle }, set: { brandKit.brandKit.handle = $0 })
    }

    private var project: Binding<String> {
        Binding(get: { brandKit.brandKit.project }, set: { brandKit.brandKit.project = $0 })
    }

    private var accent: Binding<Color> {
        Binding(
            get: { brandKit.brandKit.accent?.color ?? .white },
            set: { brandKit.brandKit.accent = RGBAColor($0) })
    }

    private var placement: Binding<Watermark.Placement> {
        Binding(get: { brandKit.brandKit.placement }, set: { brandKit.brandKit.placement = $0 })
    }
}

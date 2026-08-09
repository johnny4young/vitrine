import AppKit
import SwiftUI

/// About pane: version, links, copyright, and a privacy-safe diagnostics
/// export for bug reports.
struct AboutSettingsView: View {
    @Bindable var settings: AppSettings
    let entitlements: Entitlements

    #if VITRINE_DIRECT_DOWNLOAD
        @State private var showsDeactivationConfirmation = false
        @State private var deactivationRequestID: UUID?
        @State private var showsDeactivationResult = false
        @State private var deactivationResultMessage = ""
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                // Identity cluster: who/what the app is.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
                Text(verbatim: "Vitrine")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(VitrineTokens.Text.primary)
                    .padding(.top, 10)
                // The version line's template is localized through the catalog;
                // the version value itself is a semver, inserted verbatim.
                Text("Version \(appVersion) · MIT")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                Text("Turn code into beautiful images, from your menu bar.")
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VitrineTokens.Text.secondary)
                Link("GitHub", destination: VitrineLinks.githubRepository)
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Accent.system)
                    .padding(.top, 4)

                #if VITRINE_DIRECT_DOWNLOAD
                    if entitlements.directLicenseManagementState != .unavailable {
                        licenseManagement
                            .padding(.top, 14)
                    }
                #endif

                Button("Export Diagnostics…") {
                    DiagnosticsExporter.exportWithSavePanel(settings: settings)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("export-diagnostics-button")
                .help(
                    "Save a privacy-safe report (no code or clipboard contents) to a file you choose."
                )
                .padding(.top, 14)

                // A stable legal/brand string, shown verbatim like the "Vitrine"
                // wordmark above so it bypasses the String Catalog.
                Text(verbatim: "© 2026 johnny4young · MIT")
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30 + 22)
            .padding(.horizontal, 26)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("settings-about-pane")
        #if VITRINE_DIRECT_DOWNLOAD
            .confirmationDialog(
                "Deactivate Vitrine PRO on this Mac?",
                isPresented: $showsDeactivationConfirmation
            ) {
                Button("Deactivate This Mac", role: .destructive) {
                    deactivationRequestID = UUID()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This releases one license seat and removes PRO access from this Mac.")
            }
            .alert("License Deactivation", isPresented: $showsDeactivationResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deactivationResultMessage)
            }
            .task(id: deactivationRequestID) {
                guard deactivationRequestID != nil else { return }
                await deactivateLicense()
            }
        #endif
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    #if VITRINE_DIRECT_DOWNLOAD
        private var licenseManagement: some View {
            VStack(spacing: 8) {
                Divider()
                    .frame(width: 360)
                    .padding(.bottom, 6)
                Text("License")
                    .font(.system(size: VitrineTokens.FontSize.body, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.primary)

                switch entitlements.directLicenseManagementState {
                case .active:
                    Text("Vitrine PRO is active on this Mac.")
                        .foregroundStyle(VitrineTokens.Text.secondary)
                    Button("Deactivate This Mac…") {
                        showsDeactivationConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(deactivationRequestID != nil)
                    .accessibilityIdentifier("deactivate-license-button")
                case .legacy:
                    Text(
                        "Vitrine PRO is active. This activation predates in-app seat management; use your purchase portal or support to release it."
                    )
                    .foregroundStyle(VitrineTokens.Text.secondary)
                case .cleanupNeeded:
                    Text(
                        "This Mac has an incomplete license change. Release its recorded seat before activating again."
                    )
                    .foregroundStyle(VitrineTokens.Text.secondary)
                    Button("Release Recorded Seat…") {
                        showsDeactivationConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(deactivationRequestID != nil)
                    .accessibilityIdentifier("deactivate-license-button")
                case .unavailable:
                    EmptyView()
                }
            }
            .font(.system(size: VitrineTokens.FontSize.body))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 400)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("License management")
            .accessibilityIdentifier("license-management-section")
        }

        private func deactivateLicense() async {
            let outcome = await entitlements.deactivateLicense()
            guard !Task.isCancelled else { return }
            deactivationRequestID = nil
            deactivationResultMessage =
                switch outcome {
                case .deactivated:
                    String(localized: "Vitrine PRO was deactivated on this Mac.")
                case .alreadyInactive:
                    String(
                        localized:
                            "The provider had already released this seat. Local PRO access was removed."
                    )
                case .notActivated:
                    String(localized: "There is no recorded license seat to deactivate.")
                case .network:
                    String(
                        localized:
                            "Vitrine PRO remains active because the license service could not be reached. Try again."
                    )
                case .refused:
                    String(
                        localized:
                            "Vitrine PRO remains active because the provider did not confirm deactivation."
                    )
                case .superseded:
                    String(
                        localized:
                            "The license changed while deactivation was in progress. The newer activation was kept."
                    )
                case .localCleanupFailed:
                    String(
                        localized:
                            "The seat was released, but local license cleanup did not finish. Try again."
                    )
                }
            showsDeactivationResult = true
        }
    #endif
}

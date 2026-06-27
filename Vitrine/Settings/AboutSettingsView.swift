import AppKit
import SwiftUI

/// About pane: version, links, copyright (CS-010), and a privacy-safe diagnostics
/// export for bug reports (CS-048).
struct AboutSettingsView: View {
    @Bindable var settings: AppSettings

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
                // The version line's template is localized through the catalog
                // (CS-047); the version value itself is a semver, inserted verbatim.
                Text("Version \(appVersion) · MIT")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.secondary)
                Text("Turn code into beautiful images, from your menu bar.")
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(VitrineTokens.Text.secondary)
                Link("GitHub", destination: URL(string: "https://github.com/johnny4young/vitrine")!)
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .foregroundStyle(VitrineTokens.Accent.system)
                    .padding(.top, 4)

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
                // wordmark above so it bypasses the String Catalog (CS-047).
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
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

import AppKit
import KeyboardShortcuts
import SwiftUI

/// General pane: hotkey, what it triggers, launch at login (CS-002/010/014),
/// plus a "Reset all settings" action that restores defaults (CS-050).
struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var presets: PresetStore
    @ObservedObject var brandKit: BrandKitStore = .shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var showResetConfirmation = false

    /// Where the `vitrine` CLI is currently linked, if anywhere (CS-033).
    @State private var cliInstalledAt: URL?
    /// A failed install attempt's message; drives the fallback alert.
    @State private var cliInstallError: String?

    var body: some View {
        SettingsPaneScroll {
            TokenGroup(title: Text("Capture")) {
                TokenRow(label: Text("Global hotkey")) {
                    KeyboardShortcuts.Recorder(for: .quickCapture)
                        .accessibilityLabel("Global hotkey")
                }
                TokenRow(label: Text("Hotkey runs")) {
                    TokenSegmentedPicker(
                        options: [
                            (HotkeyAction.quickCapture, Text("Capture")),
                            (HotkeyAction.openEditor, Text("Editor")),
                        ],
                        selection: $settings.hotkeyAction
                    )
                    .accessibilityLabel("Hotkey runs")
                }
                TokenRow(label: Text("Launch at login")) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("launch-at-login-toggle")
                        .onChange(of: launchAtLogin) { _, newValue in
                            LaunchAtLogin.setEnabled(newValue)
                        }
                }
            }

            TokenGroup(title: Text("App")) {
                TokenRow(
                    label: Text("App language"),
                    caption: Text("Vitrine reopens in the selected language next launch")
                ) {
                    TokenSegmentedPicker(
                        options: AppLanguage.allCases.map {
                            ($0, Text(verbatim: $0.displayName))
                        },
                        selection: $settings.appLanguage
                    )
                    .accessibilityLabel("App language")
                    .accessibilityIdentifier("app-language-picker")
                }

                // Shown only once the choice differs from the language the app is
                // running in, so the user can apply it now instead of quitting and
                // reopening a Dock-less menu-bar agent by hand (CS-047).
                if settings.languageChangePendingRelaunch {
                    TokenRow {
                        Button("Relaunch to Apply") { AppRelauncher.relaunch() }
                            .accessibilityIdentifier("relaunch-to-apply-button")
                    }
                }

                // The DMG-install counterpart of the Homebrew cask's `binary`
                // stanza (CS-033): link the embedded CLI onto PATH from here.
                if let cli = CLIToolInstaller.embeddedCLI {
                    TokenRow(label: Text("Command-line tool"), caption: cliToolCaption) {
                        HStack(spacing: VitrineTokens.Spacing.xs) {
                            Button("Install…") { installCLITool(cli) }
                                .help(
                                    "Link the vitrine command onto your PATH so scripts can render images."
                                )
                                .accessibilityIdentifier("install-cli-button")
                            Button("Copy Command") {
                                copyToClipboard(CLIToolInstaller.terminalCommand(for: cli))
                            }
                            .help(
                                "Copy the equivalent Terminal command, for system folders that need sudo."
                            )
                            .accessibilityIdentifier("copy-cli-command-button")
                        }
                        .fixedSize()
                    }
                }

                TokenRow(
                    label: Text("Reset"),
                    caption: Text("Restores every preference to its default")
                ) {
                    Button("Reset All Settings…", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .accessibilityIdentifier("reset-all-settings-button")
                }
            }
        }
        .onAppear {
            if let cli = CLIToolInstaller.embeddedCLI {
                cliInstalledAt = CLIToolInstaller.installedLocation(of: cli)
            }
        }
        .alert(
            "Couldn't Install the Command",
            isPresented: Binding(
                get: { cliInstallError != nil }, set: { if !$0 { cliInstallError = nil } })
        ) {
            Button("Copy Command") {
                if let cli = CLIToolInstaller.embeddedCLI {
                    copyToClipboard(CLIToolInstaller.terminalCommand(for: cli))
                }
                cliInstallError = nil
            }
            Button("OK", role: .cancel) { cliInstallError = nil }
        } message: {
            Text(
                "\(cliInstallError ?? "") System folders need an administrator: run the copied command in Terminal instead."
            )
        }
        .accessibilityIdentifier("settings-general-pane")
        .confirmationDialog(
            "Reset all settings to their defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                // `resetToDefaults()` clears the persisted preset blob too (its key
                // is in `SettingsCodec.Keys.all`); reload stores with in-memory
                // caches so the UI reflects the cleared state immediately.
                presets.reload()
                brandKit.reload()
                launchAtLogin = LaunchAtLogin.isEnabled
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your recent languages and saved presets are also cleared.")
        }
    }

    // MARK: - Command-line tool (CS-033)

    /// The CLI row's caption: where the link lives once installed, otherwise
    /// what installing gets you.
    private var cliToolCaption: Text {
        if let cliInstalledAt {
            return Text("Linked at \(cliInstalledAt.path)")
        }
        return Text("Render images from scripts with the vitrine command")
    }

    /// Runs the sandbox-true install flow: the user picks the destination
    /// folder (the panel's grant is what authorizes the write), then the
    /// symlink is created inside it. A refusal (e.g. root-owned
    /// /usr/local/bin) surfaces the copyable Terminal fallback.
    private func installCLITool(_ cli: URL) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(
            localized:
                "Choose a folder on your PATH for the vitrine command — for example /opt/homebrew/bin."
        )
        panel.prompt = String(localized: "Install")
        panel.directoryURL = CLIToolInstaller.knownBinDirectories.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        switch CLIToolInstaller.install(cli, into: directory) {
        case .installed(let link):
            cliInstalledAt = link
            cliInstallError = nil
        case .failed(let message):
            cliInstallError = message
        }
    }

    /// Places `command` on the general pasteboard (the Copy Command actions).
    private func copyToClipboard(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

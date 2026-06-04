import AppKit
import KeyboardShortcuts
import SwiftUI

/// General pane: hotkey, what it triggers, launch at login (CS-002/010/014).
struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Global hotkey:", name: .quickCapture)

            Picker("Hotkey runs", selection: $settings.hotkeyAction) {
                ForEach(HotkeyAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .accessibilityIdentifier("launch-at-login-toggle")
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLogin.setEnabled(newValue)
                }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .accessibilityIdentifier("settings-general-pane")
    }
}

/// Style pane: theme, background, padding, font, chrome, shadow + live preview (CS-006/010).
struct StyleSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: themeBinding) {
                    ForEach(Theme.all) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
                Picker("Font", selection: $settings.config.fontName) {
                    ForEach(CodeFont.all, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                Picker("Background", selection: gradientBinding) {
                    ForEach(GradientPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                Slider(value: $settings.config.padding, in: 16...64, step: 4) { Text("Padding") }
                Slider(value: $settings.config.fontSize, in: 10...20, step: 1) { Text("Font size") }
                Toggle("Window chrome", isOn: $settings.config.showChrome)
                Toggle("Drop shadow", isOn: $settings.config.showShadow)
            }

            Section("Preview") {
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Live preview")
                        .accessibilityIdentifier("settings-style-preview")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
        .accessibilityIdentifier("settings-style-pane")
    }

    /// Config used for the preview — falls back to a sample snippet when the editor
    /// has no code yet, so the preview is always meaningful.
    private var previewConfig: SnapshotConfig {
        var config = settings.config
        if config.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.code = "func greet(_ name: String) {\n    print(\"Hello, \\(name)!\")\n}"
        }
        return config
    }

    private var previewImage: NSImage? {
        ExportManager.renderNSImage(previewConfig, scale: 2)
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { settings.config.theme.id },
            set: { settings.config.theme = Theme.theme(withID: $0) }
        )
    }

    private var gradientBinding: Binding<GradientPreset> {
        Binding(
            get: {
                if case .gradient(let preset) = settings.config.background { return preset }
                return .ocean
            },
            set: { settings.config.background = .gradient($0) }
        )
    }
}

/// Output pane: clipboard/save behavior, resolution, format (CS-010).
struct OutputSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Copy to clipboard automatically", isOn: $settings.autoCopy)
            Toggle("Also save to a file", isOn: $settings.alsoSaveToFile)

            Picker("Resolution", selection: $settings.exportScale) {
                Text("1×").tag(1)
                Text("2× (Retina)").tag(2)
                Text("3×").tag(3)
            }

            Picker("Format", selection: $settings.exportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .accessibilityIdentifier("settings-output-pane")
    }
}

/// Input pane: URL handling (CS-010 · Input).
struct InputSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle(
                "Treat copied URLs as a screenshot target", isOn: $settings.treatURLsAsScreenshot)
            Text(
                "When off, a copied URL is rendered as text. URL screenshots arrive in Product Phase 2."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .accessibilityIdentifier("settings-input-pane")
    }
}

/// About pane: version, links, copyright (CS-010).
struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Vitrine").font(.title.bold())
            Text("Version \(appVersion)").foregroundStyle(.secondary)
            Text("Turn code into beautiful images, from your menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("GitHub", destination: URL(string: "https://github.com/johnny4young/vitrine")!)
            Text("© 2026 johnny4young · MIT").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 460, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("settings-about-pane")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

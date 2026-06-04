import KeyboardShortcuts
import SwiftUI

/// "General" preferences pane: hotkey, output behavior, launch at login (CS-010).
struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Quick capture:", name: .quickCapture)

            Toggle("Copy result to clipboard automatically", isOn: $settings.autoCopy)

            Picker("Export resolution", selection: $settings.exportScale) {
                Text("1×").tag(1)
                Text("2× (Retina)").tag(2)
                Text("3×").tag(3)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .disabled(true)
                .help("Coming soon (CS-010).")
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }
}

/// "Style" preferences pane: theme, background, padding, font, chrome (CS-006/010).
struct StyleSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Theme", selection: themeBinding) {
                ForEach(Theme.all) { theme in
                    Text(theme.displayName).tag(theme.id)
                }
            }

            Picker("Background", selection: gradientBinding) {
                ForEach(GradientPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }

            Slider(value: $settings.config.padding, in: 16...64, step: 4) {
                Text("Padding")
            }

            Slider(value: $settings.config.fontSize, in: 10...20, step: 1) {
                Text("Font size")
            }

            Toggle("Window chrome", isOn: $settings.config.showChrome)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
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

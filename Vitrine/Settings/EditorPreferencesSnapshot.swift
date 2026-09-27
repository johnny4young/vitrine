import Foundation
import VitrineDomain
import VitrineRendering

/// Value boundary between app defaults and an independent editor. Unlike a portable
/// StyleSnapshot, this preserves the full resolved configuration, including custom
/// palettes, metadata, language, and image backgrounds. It retains no stores or catalogs;
/// applying it writes through the existing settings owners.
struct EditorPreferencesSnapshot {
    var configuration: SnapshotConfig
    let output: Output
    let destinationID: String?

    init(defaults: UserDefaults) {
        configuration = SettingsCodec.readConfig(from: defaults)
        output = Output(settings: ExportSettings(defaults: defaults))
        destinationID =
            ExportPreset.preset(
                withID: defaults.string(forKey: SettingsCodec.Keys.selectedPreset))?.id
    }

    init(settings: AppSettings) {
        configuration = settings.config
        output = Output(settings: settings.export)
        destinationID = settings.selectedPreset?.id
    }

    /// Only per-capture output preferences. Auto-copy, save behavior, close-after-copy,
    /// and cooperative clipboard privacy stay app-global and are never promoted by
    /// Make Default. Individual ExportSettings properties retain their Observation scope.
    struct Output {
        let scale: Int
        let format: ExportFormat
        let colorProfile: ColorProfile
        let richClipboard: Bool
        let textSidecar: Bool

        init(settings: ExportSettings) {
            scale = settings.scale
            format = settings.format.availableOrFallback
            colorProfile = settings.colorProfile
            richClipboard = settings.richClipboard
            textSidecar = settings.textSidecar
        }

        func apply(to settings: ExportSettings) {
            settings.scale = scale
            settings.format = format
            settings.colorProfile = colorProfile
            settings.richClipboard = richClipboard
            settings.textSidecar = textSidecar
        }
    }
}

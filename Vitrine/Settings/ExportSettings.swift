import Foundation
import Observation
import VitrineDomain
import VitrineRendering

/// The per-capture image-output settings (Output), extracted from `AppSettings` into a
/// focused sub-store so the main settings object stays cohesive rather than
/// accreting every feature's knobs — following the `WebCaptureSettings` precedent. Held
/// by `AppSettings`; because both are `@Observable`, a SwiftUI surface that reads
/// `settings.export.<field>` observes the nested store directly and refreshes on an
/// output-settings edit, so no manual change-forwarding is needed.
///
/// Persistence is unchanged from when these lived on `AppSettings`: every property reads
/// and writes the same `SettingsCodec.Keys` with the same defensive defaults, so
/// a store written by an older build loads identically and the settings schema/migration
/// is untouched. The redundant `export` prefix the `exportScale`/`exportFormat` members
/// carried on the god object is dropped here — the `export` namespace now supplies that
/// context (`settings.export.scale`).
///
/// Editor sessions carry their own copy of these. App-wide clipboard and save behavior
/// lives in ``OutputBehavior`` so a session can never hold a stale copy of it.
@Observable
final class ExportSettings {
    private typealias Keys = SettingsCodec.Keys

    /// Export resolution multiplier: 1, 2 (retina), or 3.
    var scale: Int { didSet { defaults.set(scale, forKey: Keys.exportScale) } }

    /// Exported image format (Output).
    var format: ExportFormat {
        didSet { defaults.set(format.rawValue, forKey: Keys.exportFormat) }
    }

    /// PNG color profile: sRGB by default, Display P3 as an advanced option.
    var colorProfile: ColorProfile {
        didSet { defaults.set(colorProfile.rawValue, forKey: Keys.colorProfile) }
    }

    /// Add a rich-text representation (highlighted RTF/HTML) alongside the PNG on every
    /// copy. Off by default so the one-shortcut copy stays a plain image; when
    /// on, a paste into a rich-text editor keeps the syntax colors and font while an
    /// image well still receives the picture.
    var richClipboard: Bool {
        didSet { defaults.set(richClipboard, forKey: Keys.richClipboard) }
    }

    /// Send the source along with the image as plain, copyable text. Off by default so a
    /// copy stays a plain image; when on, a copy also places the text on the clipboard and
    /// the multi-size export writes a `.txt` beside each image. Terminal output is stripped
    /// of its escape codes first, matching the rendered card.
    var textSidecar: Bool {
        didSet { defaults.set(textSidecar, forKey: Keys.textSidecar) }
    }

    private let defaults: UserDefaults

    /// Seeds every property from `defaults` with the same documented fallbacks the god
    /// object used: a missing or garbage value falls back to the default, so
    /// loading from empty, partial, or corrupt defaults always yields a usable config.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        scale = SettingsCodec.readExportScale(from: defaults)
        format = ExportFormat.resolveAvailable(defaults.string(forKey: Keys.exportFormat))
        colorProfile = ColorProfile.resolve(defaults.string(forKey: Keys.colorProfile))
        richClipboard = defaults.object(forKey: Keys.richClipboard) as? Bool ?? false
        textSidecar = defaults.object(forKey: Keys.textSidecar) as? Bool ?? false
    }

    /// Restores every output setting to its factory default, driven by
    /// `AppSettings.resetToDefaults()`. The persisted keys are cleared by that caller's
    /// key sweep; this resets the live published state so the UI updates at once.
    func resetToDefaults() {
        scale = SettingsDefaults.exportScale
        format = .fallback
        colorProfile = .fallback
        richClipboard = false
        textSidecar = false
    }
}

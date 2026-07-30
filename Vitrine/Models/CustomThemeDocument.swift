import Foundation

/// The on-disk JSON envelope for exporting and importing custom themes —
/// the documented file schema.
///
/// Themes are shared as a single self-describing file: a `format` marker, a
/// `schemaVersion`, and the array of themes. Import is **strict** both about the
/// envelope (a wrong format or unsupported version fails fast with a clear error)
/// and within each theme (a missing required color or a bad hex value is rejected
/// with a specific message). This preserves the documented import schema
/// and "bad colors or missing keys fail with clear validation errors", while a
/// totally unrelated JSON file simply fails as "not a theme file" rather than
/// crashing.
struct CustomThemeDocument: Codable, Equatable {
    /// A fixed marker so a Vitrine theme file is recognizable and a random JSON file
    /// (or a different app's export) is rejected before any field is trusted.
    static let formatMarker = "vitrine.custom-themes"
    /// The current theme-file schema version. Bump when the envelope's shape or
    /// meaning changes; older files are migrated or rejected, never misread.
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var themes: [StoredCustomTheme]

    /// Errors surfaced while importing a theme file. Each maps to clear, user-facing
    /// copy at the call site.
    enum ImportError: Error, Equatable {
        /// The bytes are not valid JSON / not a theme document at all.
        case notAThemeFile
        /// The file is a theme file but from an unsupported (usually newer) schema
        /// this build cannot read.
        case unsupportedSchemaVersion(Int)
        /// A theme had a missing required color or an invalid hex value.
        case invalidPalette(ThemePalette.ValidationError)
        /// The file decoded but contained no usable themes.
        case empty

        /// A short, human-readable explanation for an alert.
        var message: String {
            switch self {
            case .notAThemeFile:
                "This file is not a Vitrine theme file."
            case .unsupportedSchemaVersion(let version):
                "This theme file uses a newer format (version \(version)) this app can't read."
            case .invalidPalette(let error):
                error.message
            case .empty:
                "This theme file does not contain any themes."
            }
        }
    }

    /// Wraps themes for export at the current format and schema version.
    init(themes: [Theme]) {
        self.format = Self.formatMarker
        self.schemaVersion = Self.currentSchemaVersion
        self.themes = themes.compactMap(StoredCustomTheme.init)
    }

    private enum CodingKeys: String, CodingKey { case format, schemaVersion, themes }

    /// Decodes the envelope, tolerating its scalar fields so envelope validation is
    /// explicit in `themes(from:)`. The `themes` array is decoded with the strict
    /// palette validator so a bad color surfaces as a thrown error there.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? container.decode(String.self, forKey: .format)) ?? ""
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0
        themes = try container.decode([StoredCustomTheme].self, forKey: .themes)
    }

    /// Encodes a theme document as pretty, stable JSON (sorted keys) so an exported
    /// file is human-readable and diffable.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Parses and validates theme-file `data`, returning the contained themes or
    /// throwing a specific `ImportError`.
    ///
    /// Validation order is deliberate: a bad/missing color (surfaced by the palette
    /// decoder) → malformed JSON / not a theme file → wrong format marker →
    /// unsupported schema → empty. A valid document with at least one theme yields
    /// themes whose palettes have all been validated, so the caller can adopt them
    /// without any further checking.
    static func themes(from data: Data) throws -> [Theme] {
        let document: CustomThemeDocument
        do {
            document = try JSONDecoder().decode(CustomThemeDocument.self, from: data)
        } catch let error as ThemePalette.ValidationError {
            // A present-but-invalid palette is a *theme* problem, not an "unknown
            // file" one, so surface the precise color error rather than a generic message.
            throw ImportError.invalidPalette(error)
        } catch {
            throw ImportError.notAThemeFile
        }
        guard document.format == formatMarker else { throw ImportError.notAThemeFile }
        guard document.schemaVersion <= currentSchemaVersion, document.schemaVersion >= 1 else {
            throw ImportError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard !document.themes.isEmpty else { throw ImportError.empty }
        return document.themes.map(\.theme)
    }
}

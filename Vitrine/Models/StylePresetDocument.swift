import Foundation

/// The on-disk JSON envelope for exporting and importing style presets.
///
/// Presets are shared as a single self-describing file: a `format` marker, a
/// `schemaVersion`, and the array of presets. Import is **strict about the
/// envelope** but **tolerant within each preset**: the document decoder rejects a
/// wrong format or an unsupported schema version up front (so a stray JSON file or
/// a future, unreadable layout fails fast with a clear error), while each
/// `StyleSnapshot` still self-heals individual fields. The result satisfies both
/// "validate schema version and allowed fields" and "invalid preset files do not
/// crash the app".
struct StylePresetDocument: Codable, Equatable {
    /// A fixed marker so a Vitrine preset file is recognizable and a random JSON
    /// file (or a different app's export) is rejected before any field is trusted.
    static let formatMarker = "vitrine.style-presets"
    /// The current preset-file schema version. Bump when the envelope's shape or
    /// meaning changes; older files are migrated or rejected, never misread.
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var presets: [StylePreset]

    /// Errors surfaced while importing a preset file. Each maps to clear, user
    /// facing copy at the call site.
    enum ImportError: Error, Equatable {
        /// The bytes are not valid JSON / not a preset document at all.
        case notAPresetFile
        /// The file is a preset file but from an unsupported (usually newer)
        /// schema this build cannot read.
        case unsupportedSchemaVersion(Int)
        /// The file decoded but contained no usable presets.
        case empty

        /// A short, human-readable explanation for an alert.
        var message: String {
            switch self {
            case .notAPresetFile:
                "This file is not a Vitrine preset file."
            case .unsupportedSchemaVersion(let version):
                "This preset file uses a newer format (version \(version)) this app can't read."
            case .empty:
                "This preset file does not contain any presets."
            }
        }
    }

    /// Wraps presets for export at the current format and schema version.
    init(presets: [StylePreset]) {
        self.format = Self.formatMarker
        self.schemaVersion = Self.currentSchemaVersion
        self.presets = presets
    }

    private enum CodingKeys: String, CodingKey { case format, schemaVersion, presets }

    /// Decodes the envelope, rejecting anything that is not a Vitrine preset file.
    /// Individual presets remain tolerant; the envelope is what is validated here.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? container.decode(String.self, forKey: .format)) ?? ""
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0
        // Decode presets element-tolerantly: one corrupt entry drops itself rather than
        // collapsing the whole array (which would be misreported as an empty file). The
        // outer `try?` still guards "presets is not an array at all".
        presets =
            ((try? container.decode([FailableDecodable<StylePreset>].self, forKey: .presets)) ?? [])
            .compactMap(\.value)
    }

    /// Encodes a preset document as pretty, stable JSON (sorted keys) so an
    /// exported file is human-readable and diffable.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Parses and validates preset-file `data`, returning the contained presets or
    /// throwing a specific `ImportError`.
    ///
    /// Validation order is deliberate: malformed JSON → not a preset file → wrong
    /// format marker → unsupported schema → empty. A valid document with at least
    /// one preset yields presets that have already self-healed every field, so the
    /// caller can adopt them without any further checking.
    static func presets(from data: Data) throws -> [StylePreset] {
        let document: StylePresetDocument
        do {
            document = try JSONDecoder().decode(StylePresetDocument.self, from: data)
        } catch {
            throw ImportError.notAPresetFile
        }
        guard document.format == formatMarker else { throw ImportError.notAPresetFile }
        guard document.schemaVersion <= currentSchemaVersion, document.schemaVersion >= 1 else {
            throw ImportError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard !document.presets.isEmpty else { throw ImportError.empty }
        return document.presets
    }
}

import Foundation

/// The persisted/on-disk record for one custom theme: a stable id, a display name,
/// and the palette.
///
/// `Theme` itself is a SwiftUI-facing value with a non-`Codable` `Source`, so themes
/// are stored and shared through this flat, fully-`Codable` record. Decoding routes
/// through `ThemePalette`'s strict decoder, so a record with a bad or missing color
/// fails to decode and is skipped on load (or rejected on import) — origin and
/// validity are recomputed, never trusted from the file.
struct StoredCustomTheme: Codable, Equatable {
    var id: String
    var name: String
    var palette: ThemePalette

    init(id: String, name: String, palette: ThemePalette) {
        self.id = id
        self.name = name
        self.palette = palette
    }

    /// Captures a custom `theme` for storage, or `nil` for a built-in (which is never
    /// stored — built-ins ship with the app).
    init?(_ theme: Theme) {
        guard let palette = theme.palette else { return nil }
        self.id = theme.id
        self.name = theme.displayName
        self.palette = palette
    }

    /// The reconstructed `Theme`, with its id and name sanitized so a hand-edited
    /// record always yields a usable, addressable theme.
    var theme: Theme {
        let resolvedID = id.isEmpty ? CustomThemeStore.freshID() : id
        return Theme(
            id: resolvedID, displayName: CustomThemeStore.sanitizedName(name), palette: palette)
    }

    private enum CodingKeys: String, CodingKey { case id, name, palette }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        // The palette is required and strictly validated: a record without a valid
        // palette is not a usable theme, so the decode fails and the record is
        // skipped on load / rejected on import.
        palette = try container.decode(ThemePalette.self, forKey: .palette)
    }
}

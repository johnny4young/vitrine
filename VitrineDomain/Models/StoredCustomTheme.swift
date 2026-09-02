import Foundation

/// The persisted/on-disk record for one custom theme: a stable id, a display name,
/// and the palette.
///
/// `Theme` itself is a SwiftUI-facing value with a non-`Codable` `Source`, so themes
/// are stored and shared through this flat, fully-`Codable` record. Decoding routes
/// through `ThemePalette`'s strict decoder, so a record with a bad or missing color
/// fails to decode and is skipped on load (or rejected on import) — origin and
/// validity are recomputed, never trusted from the file.
public struct StoredCustomTheme: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var palette: ThemePalette

    public init(id: String, name: String, palette: ThemePalette) {
        self.id = id
        self.name = name
        self.palette = palette
    }

    /// Captures a custom `theme` for storage, or `nil` for a built-in (which is never
    /// stored — built-ins ship with the app).
    public init?(_ theme: Theme) {
        guard let palette = theme.palette else { return nil }
        self.id = theme.id
        self.name = theme.displayName
        self.palette = palette
    }

    /// The reconstructed `Theme`, with its id and name sanitized so a hand-edited
    /// record always yields a usable, addressable theme.
    public var theme: Theme {
        let resolvedID = id.isEmpty ? Self.freshID() : id
        return Theme(
            id: resolvedID, displayName: Self.sanitizedName(name), palette: palette)
    }

    /// Trims a user-entered name and collapses an empty result to a friendly
    /// default, so a custom theme always has a non-empty, tidy label.
    public static func sanitizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Custom Theme" : trimmed
    }

    /// A fresh, collision-proof id for a custom theme. The `custom.` prefix keeps a
    /// custom id visibly distinct from a built-in slug and out of the built-in id set.
    public static func freshID() -> String { "custom.\(UUID().uuidString)" }

    private enum CodingKeys: String, CodingKey { case id, name, palette }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        // The palette is required and strictly validated: a record without a valid
        // palette is not a usable theme, so the decode fails and the record is
        // skipped on load / rejected on import.
        palette = try container.decode(ThemePalette.self, forKey: .palette)
    }
}

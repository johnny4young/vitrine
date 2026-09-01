import Foundation

/// A named, reusable style the user can save, apply, export, import, and share.
///
/// A preset pairs a stable `id` and a display `name` with a `StyleSnapshot`. Two
/// origins exist:
///
/// - **Built-in** presets ship with the app. They are immutable: the store never
///   lets one be renamed, edited, or deleted — only *duplicated* into an editable
///   user copy (contract "built-in presets cannot be overwritten, only
///   duplicated"). `isBuiltIn` is recomputed from the catalog on load rather than
///   trusted from a file, so a shared file cannot smuggle in a fake "built-in"
///   flag to make itself uneditable.
/// - **User** presets are created by saving the current style, duplicating any
///   preset, or importing a file. They are fully editable.
public struct StylePreset: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier (a UUID string for user presets; a slug for built-ins).
    public let id: String
    /// Human-readable name shown in the picker and list.
    public var name: String
    /// The captured style this preset applies.
    public var style: StyleSnapshot

    /// Whether this preset is a built-in (immutable) one. Recomputed from the
    /// built-in catalog on every load, never decoded from a file, so origin cannot
    /// be spoofed by a hand-edited preset.
    public var isBuiltIn: Bool { Self.builtInIDs.contains(id) }

    public init(id: String = UUID().uuidString, name: String, style: StyleSnapshot) {
        self.id = id
        self.name = StylePreset.sanitizedName(name)
        self.style = style
    }

    /// Trims a user-entered name and collapses an empty result to a friendly
    /// default, so a preset always has a non-empty, tidy label.
    public static func sanitizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Preset" : trimmed
    }

    // MARK: Codable — `isBuiltIn` is derived, never stored or trusted from a file

    private enum CodingKeys: String, CodingKey { case id, name, style }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing id gets a fresh one so an imported preset is always addressable
        // (and never collides under an empty key); the name is sanitized.
        let decodedID = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        id = decodedID.isEmpty ? UUID().uuidString : decodedID
        name = StylePreset.sanitizedName(
            (try? container.decode(String.self, forKey: .name)) ?? "")
        style = try container.decode(StyleSnapshot.self, forKey: .style)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(style, forKey: .style)
    }
}

extension StylePreset {
    /// A clean, professional starting set that doubles as documentation of what a
    /// preset can express. Each one is a different brand mood over a known theme.
    /// Ids are stable slugs (prefixed so they can never collide with a user
    /// preset's UUID) used to recognize a built-in on load.
    public static let aurora = StylePreset(
        id: "builtin.aurora", name: "Aurora",
        style: StyleSnapshot(
            themeID: Theme.oneDark.id, padding: 40, background: .gradient(.aurora)))
    public static let midnight = StylePreset(
        id: "builtin.midnight", name: "Midnight",
        style: StyleSnapshot(
            themeID: Theme.tokyoNight.id, padding: 48, background: .gradient(.night)))
    public static let sunset = StylePreset(
        id: "builtin.sunset", name: "Sunset",
        style: StyleSnapshot(
            themeID: Theme.dracula.id, padding: 40, background: .gradient(.sunset)))
    public static let minimal = StylePreset(
        id: "builtin.minimal", name: "Minimal Light",
        style: StyleSnapshot(
            themeID: Theme.github.id, padding: 32, showShadow: false,
            background: .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1))))

    /// The built-in presets, in list order. They are immutable; the store offers
    /// "Duplicate" instead of editing or deleting any of them.
    public static let builtIns: [StylePreset] = [.aurora, .midnight, .sunset, .minimal]

    /// The set of ids that identify a built-in, used to recompute `isBuiltIn` on
    /// load so origin is never read from (or spoofed by) a file.
    public static let builtInIDs: Set<String> = Set(builtIns.map(\.id))
}

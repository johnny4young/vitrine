import Foundation

/// Optional context shown in a compact header above the code (CS-022).
///
/// Screenshots dropped into docs, slide decks, or chats often need a little
/// context — the file they came from, a title, or a one-line caption — without
/// editing the image in another tool afterward. `SnapshotMetadata` is the value
/// model behind `SnapshotConfig.metadata`: a few optional free-form fields plus a
/// toggle for the language badge.
///
/// Every text field is **optional context**, so the default is fully empty and
/// the language badge is off: an untouched config renders exactly the signature
/// look with no header at all (`isEmpty` is `true`). Fields are normalized on the
/// way in — surrounding whitespace is trimmed and an all-whitespace entry becomes
/// `nil` — so a blank filename never reserves header space and the value compares
/// and persists cleanly.
struct SnapshotMetadata: Equatable, Codable {
    /// A filename or path shown as a chip (e.g. `ContentView.swift`). Empty by
    /// default; inferring one from a file input is left to future quick-capture
    /// work (CS-022 acceptance) and is not required here.
    var filename: String?

    /// A short title shown as the header's primary line (e.g. "Aurora gradient").
    var title: String?

    /// A one-line caption shown under the title in a dimmer, smaller style.
    var caption: String?

    /// Whether to show the language badge (the active language's display name).
    /// Off by default so the signature render is unchanged until opted into.
    var showLanguageBadge: Bool = false

    /// True when no header content is configured: no filename, title, or caption,
    /// and the language badge is hidden. The canvas omits the header entirely in
    /// this case so the code body is never crowded by an empty bar.
    var isEmpty: Bool {
        filename == nil && title == nil && caption == nil && !showLanguageBadge
    }

    /// Whether any text field carries content. Used by the canvas to decide
    /// whether a text row is needed at all (separate from the badge-only case).
    var hasText: Bool {
        filename != nil || title != nil || caption != nil
    }

    /// Builds normalized metadata: each field is trimmed, and an empty or
    /// whitespace-only string is stored as `nil` so it never reserves space or
    /// pollutes equality/persistence.
    init(
        filename: String? = nil,
        title: String? = nil,
        caption: String? = nil,
        showLanguageBadge: Bool = false
    ) {
        self.filename = Self.normalized(filename)
        self.title = Self.normalized(title)
        self.caption = Self.normalized(caption)
        self.showLanguageBadge = showLanguageBadge
    }

    /// Trims surrounding whitespace/newlines and collapses an empty result to
    /// `nil`, so `"  "` and `""` are both treated as "no value".
    static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Decodes tolerantly: missing fields default to "no value" and any decoded
    /// strings are re-normalized, so a hand-edited or partial blob can never carry
    /// untrimmed or empty-but-present text into the renderer (CS-050 spirit).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = Self.normalized(try container.decodeIfPresent(String.self, forKey: .filename))
        title = Self.normalized(try container.decodeIfPresent(String.self, forKey: .title))
        caption = Self.normalized(try container.decodeIfPresent(String.self, forKey: .caption))
        showLanguageBadge =
            try container.decodeIfPresent(Bool.self, forKey: .showLanguageBadge) ?? false
    }
}

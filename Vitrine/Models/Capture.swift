import Foundation

/// A past capture stored in Recents (CS-013). Themes and languages are stored by
/// id so the model stays `Codable` and decoupled from SwiftUI types.
struct Capture: Codable, Identifiable, Equatable {
    let id: UUID
    var code: String
    var languageID: String
    var themeID: String
    var date: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        code: String,
        languageID: String,
        themeID: String,
        date: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.code = code
        self.languageID = languageID
        self.themeID = themeID
        self.date = date
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, languageID, themeID, date, isPinned
    }

    /// Older Vitrine builds persisted captures before pinning existed. Default a
    /// missing flag to `false` so upgrading never discards the user's history.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        languageID = try container.decode(String.self, forKey: .languageID)
        themeID = try container.decode(String.self, forKey: .themeID)
        date = try container.decode(Date.self, forKey: .date)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encode(languageID, forKey: .languageID)
        try container.encode(themeID, forKey: .themeID)
        try container.encode(date, forKey: .date)
        try container.encode(isPinned, forKey: .isPinned)
    }

    var language: Language { Language(rawValue: languageID) ?? .plaintext }
    var theme: Theme { Theme.theme(withID: themeID) }

    /// Places the content remembered by this recent capture over a current style.
    /// Content-bound marks belong to the document they were created for, so replacing
    /// the source must discard them rather than drawing stale highlights or annotations
    /// over unrelated code.
    func applying(to base: SnapshotConfig) -> SnapshotConfig {
        var config = base
        config.clearContentMarks()
        config.code = code
        config.language = language
        config.theme = theme
        return config
    }

    /// Whether this capture matches every whitespace-separated search term across
    /// its source, language, and theme. Recents is deliberately tiny and capped, so
    /// keeping the index value-derived avoids another persisted search structure.
    func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let searchableText = [code, language.displayName, theme.displayName]
            .joined(separator: "\n")
        return terms.allSatisfy { searchableText.localizedStandardContains(String($0)) }
    }

    /// A short, single-line label for the Recents submenu.
    var menuTitle: String {
        let firstLine = code.split(whereSeparator: \.isNewline).first.map(String.init) ?? code
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 40 ? trimmed : String(trimmed.prefix(39)) + "…"
    }
}

/// Ephemeral ordering choices for the visual Recents gallery. Sorting never
/// rewrites the persisted store, and pinned favorites always lead every mode.
enum RecentsSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case language

    var id: Self { self }

    func sorted(_ captures: [Capture]) -> [Capture] {
        captures.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }

            switch self {
            case .newestFirst:
                return orderedByDate(lhs, rhs, newestFirst: true)
            case .oldestFirst:
                return orderedByDate(lhs, rhs, newestFirst: false)
            case .language:
                let comparison = lhs.language.displayName.localizedStandardCompare(
                    rhs.language.displayName)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return orderedByDate(lhs, rhs, newestFirst: true)
            }
        }
    }

    private func orderedByDate(_ lhs: Capture, _ rhs: Capture, newestFirst: Bool) -> Bool {
        if lhs.date != rhs.date {
            return newestFirst ? lhs.date > rhs.date : lhs.date < rhs.date
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

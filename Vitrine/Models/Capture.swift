import Foundation

/// A past capture stored in Recents (CS-013). Themes and languages are stored by
/// id so the model stays `Codable` and decoupled from SwiftUI types.
struct Capture: Codable, Identifiable, Equatable {
    let id: UUID
    var code: String
    var languageID: String
    var themeID: String
    var date: Date

    init(
        id: UUID = UUID(),
        code: String,
        languageID: String,
        themeID: String,
        date: Date = Date()
    ) {
        self.id = id
        self.code = code
        self.languageID = languageID
        self.themeID = themeID
        self.date = date
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

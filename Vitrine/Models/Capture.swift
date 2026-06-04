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

    /// A short, single-line label for the Recents submenu.
    var menuTitle: String {
        let firstLine = code.split(whereSeparator: \.isNewline).first.map(String.init) ?? code
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 40 ? trimmed : String(trimmed.prefix(39)) + "…"
    }
}

import Foundation

/// Shared, local-only text matching for Vitrine's small interactive catalogs.
///
/// Search surfaces intentionally stay simple and deterministic: Recents is capped,
/// while theme, font, and command catalogs contain only tens of values. A persisted
/// index or third-party search engine would add lifecycle and dependency cost without
/// improving those bounds. This helper instead gives every surface the same
/// case-, diacritic-, and width-insensitive multi-term semantics.
enum LocalSearch {
    /// Folds user-visible text once before matching. Width folding makes full-width
    /// input from an IME match ordinary Latin catalog text in addition to the usual
    /// case and diacritic handling.
    nonisolated static func fold(_ value: String, locale: Locale = .current) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: locale)
    }

    /// Returns the non-empty whitespace-separated terms in a query, already folded.
    /// Empty and whitespace-only queries deliberately produce no terms so callers can
    /// preserve their original catalog order without doing any work.
    nonisolated static func terms(in query: String, locale: Locale = .current) -> [String] {
        query.split(whereSeparator: \.isWhitespace)
            .map { fold(String($0), locale: locale) }
            .filter { !$0.isEmpty }
    }

    /// Whether every query term occurs in at least one target. Terms may match across
    /// fields — for example, "rust dracula" can match a capture's language and theme —
    /// and their order is irrelevant.
    nonisolated static func matchesAllTerms(
        _ query: String, in targets: [String], locale: Locale = .current
    ) -> Bool {
        let needles = terms(in: query, locale: locale)
        guard !needles.isEmpty else { return true }
        let haystacks = targets.map { fold($0, locale: locale) }
        return needles.allSatisfy { needle in
            haystacks.contains { $0.contains(needle) }
        }
    }
}

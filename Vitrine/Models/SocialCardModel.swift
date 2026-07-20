import CoreGraphics
import CryptoKit
import Foundation

/// The value model behind a **local social-card render**.
///
/// A social card is a deterministic, text-and-layout template — a title, an
/// optional subtitle, a short code excerpt, an author/project line, and an
/// optional Vitrine logo — composed onto Vitrine's signature background and
/// exported as a 1200×630 OpenGraph image. It is the easiest web capture extension
/// precisely because it stays **100% local and deterministic**: there is no
/// WebKit, no network, and no remote render service. The same model renders the
/// same pixels on any Mac, so a card round-trips through `Codable` and through the
/// golden-image suite unchanged.
///
/// ## How it differs from `SnapshotConfig`
///
/// `SnapshotConfig` captures *one whole code snapshot* (a full file the user
/// pasted) and hugs its content. A `SocialCardModel` instead captures *card
/// copy*: marketing-style headline text plus a deliberately small code **excerpt**
/// that is truncated to `maxExcerptLines` so the card reads as a card, not as a
/// full screenshot. The two models share the same theme/background/font
/// vocabulary so a card looks unmistakably like the rest of Vitrine.
///
/// ## Validation
///
/// Every text field is normalized on the way in (surrounding whitespace trimmed,
/// an all-whitespace entry collapsed to `nil`) so a blank field never reserves
/// layout space. A card is **renderable** only when it carries something to show —
/// at least a `title` or a non-empty `codeExcerpt` (`isRenderable`); an entirely
/// empty model is refused by the renderer rather than producing a blank image. The
/// font size is clamped into `fontSizeRange`, and the excerpt is capped at
/// `maxExcerptLines`, so a corrupt or hand-edited blob can never feed a wild value
/// or a thousand-line "excerpt" into the layout.
struct SocialCardModel: Equatable {
    /// The card's primary headline (e.g. "Ship beautiful code screenshots").
    /// Optional; normalized to `nil` when blank.
    var title: String?

    /// A secondary line under the title, in a dimmer, smaller style. Optional;
    /// normalized to `nil` when blank.
    var subtitle: String?

    /// A short code snippet shown in a syntax-highlighted card. Truncated to
    /// `maxExcerptLines` so the card stays a card; an empty excerpt hides the code
    /// panel entirely.
    var codeExcerpt: String

    /// The language used to highlight `codeExcerpt`.
    var language: Language

    /// An author/handle shown in the footer (e.g. "@jane"). Optional; normalized.
    var author: String?

    /// A project/repository name shown in the footer (e.g. "vitrine"). Optional;
    /// normalized.
    var project: String?

    /// Whether to draw the Vitrine brand mark on the card. Off by default so a card
    /// is unbranded unless the user opts in.
    var showLogo: Bool

    /// Which built-in layout the card uses.
    var template: SocialCardTemplate

    /// The syntax theme used for the code excerpt and to derive the card's text
    /// colors, so a card reads correctly on a light or dark theme.
    var theme: Theme

    /// The canvas background (gradient preset, custom gradient, solid, transparent,
    /// or image). Defaults to the signature aurora gradient.
    var background: BackgroundStyle

    /// The code font family for the excerpt; resolved through `CodeFont` so an
    /// unavailable family falls back to the system monospaced font.
    var fontName: String

    /// The code excerpt's point size, clamped to `fontSizeRange`.
    var fontSize: Double

    // MARK: - Documented limits

    /// The default exported size: a 1200×630 OpenGraph / social card.
    static let defaultSize = CGSize(width: 1200, height: 630)

    /// The maximum number of code lines an excerpt keeps. Beyond this the excerpt
    /// is truncated (with a trailing ellipsis marker) so the card never turns into
    /// a full-file screenshot — that is what a `SnapshotConfig` capture is for.
    static let maxExcerptLines = 8

    /// Allowed bounds for the excerpt's point size. Wider than the editor's body
    /// range because a 1200×630 hero card uses a larger code size; a clamp still
    /// guards against a corrupt value.
    static let fontSizeRange = 14.0...40.0

    /// The default excerpt size when none is specified.
    static let defaultFontSize = 22.0

    // MARK: - Initialization

    /// Builds a normalized, validated card. Text fields are trimmed (blanks become
    /// `nil`), the excerpt is truncated to `maxExcerptLines`, and the font size is
    /// clamped to `fontSizeRange`, so the stored value is always render-ready.
    init(
        title: String? = nil,
        subtitle: String? = nil,
        codeExcerpt: String = "",
        language: Language = .swift,
        author: String? = nil,
        project: String? = nil,
        showLogo: Bool = false,
        template: SocialCardTemplate = .standard,
        theme: Theme = .oneDark,
        background: BackgroundStyle = .gradient(.aurora),
        fontName: String = CodeFont.default,
        fontSize: Double = SocialCardModel.defaultFontSize
    ) {
        self.title = Self.normalized(title)
        self.subtitle = Self.normalized(subtitle)
        self.codeExcerpt = Self.truncatedExcerpt(codeExcerpt)
        self.language = language
        self.author = Self.normalized(author)
        self.project = Self.normalized(project)
        self.showLogo = showLogo
        self.template = template
        self.theme = theme
        self.background = background
        self.fontName = fontName
        self.fontSize = Self.clampFontSize(fontSize)
    }

    // MARK: - Validation helpers

    /// Whether the card has anything the *chosen template* will actually draw, so
    /// the renderer returns `nil` rather than producing a blank image (
    /// "built-in templates render title, subtitle, code excerpt, …").
    ///
    /// Renderability is template-aware because the templates draw different fields:
    /// a code-bearing template (`showsCode`) is renderable from a title or a
    /// non-empty excerpt, but the headline template drops the code panel entirely,
    /// so an excerpt alone would leave it blank — it requires a title or subtitle
    /// instead. An entirely empty model is never renderable.
    var isRenderable: Bool {
        if template.showsCode {
            return title != nil || !codeExcerpt.isEmpty
        }
        return title != nil || subtitle != nil
    }

    /// Whether the footer (author and/or project) has any content, so the layout
    /// can omit the footer row entirely when both are absent.
    var hasFooter: Bool {
        author != nil || project != nil
    }

    /// The excerpt split into its (already truncated) display lines.
    var excerptLines: [String] {
        codeExcerpt.isEmpty ? [] : codeExcerpt.components(separatedBy: "\n")
    }

    /// Trims surrounding whitespace/newlines and collapses an empty result to
    /// `nil`, so `"  "` and `""` are both treated as "no value".
    static func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Truncates a raw excerpt to at most `maxExcerptLines` lines, appending an
    /// ellipsis line when content was dropped, and trims trailing blank lines so a
    /// stray newline never reserves an empty row. Returns `""` for an empty input.
    static func truncatedExcerpt(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var lines = trimmed.components(separatedBy: "\n")
        guard lines.count > maxExcerptLines else { return lines.joined(separator: "\n") }
        lines = Array(lines.prefix(maxExcerptLines))
        lines.append("…")
        return lines.joined(separator: "\n")
    }

    /// Clamps `value` into `fontSizeRange`, replacing a non-finite value with the
    /// default so corrupt floating-point data can never reach the layout.
    static func clampFontSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultFontSize }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    // MARK: - Determinism

    /// A stable, content-derived fingerprint of every field that affects pixels,
    /// recorded alongside the golden fixture ("golden image fixture for
    /// default template").
    ///
    /// It is a SHA-256 over the normalized copy, the excerpt and language, the
    /// template, the theme id, the font, and the background's non-PII kind, so a
    /// change to any rendered input changes the fingerprint and a stale fixture is
    /// detectable from the manifest alone. The background contributes only its
    /// `diagnosticsKind` (never a file path or raw color), matching the privacy rule
    /// the rest of the app follows.
    var fingerprint: String {
        let descriptor = [
            "template=\(template.rawValue)",
            "title=\(title ?? "")",
            "subtitle=\(subtitle ?? "")",
            "excerpt=\(codeExcerpt)",
            "language=\(language.rawValue)",
            "author=\(author ?? "")",
            "project=\(project ?? "")",
            "logo=\(showLogo)",
            "theme=\(theme.id)",
            "font=\(fontName)@\(fontSize)",
            "background=\(background.diagnosticsKind)",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(descriptor.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Built-in templates

/// The built-in social-card layouts.
///
/// Each template arranges the same content fields — title, subtitle, code
/// excerpt, author/project, and the optional logo — into a different composition,
/// so the user picks a look without re-entering copy. The set is intentionally
/// small and deterministic; every template renders through `ImageRenderer` (never
/// WebKit) and keeps user content local.
enum SocialCardTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The signature layout: a leading headline block above a syntax-highlighted
    /// code panel, with the author/project footer beneath.
    case standard

    /// A code-forward layout that gives the excerpt the visual weight and tucks the
    /// headline and footer around it — for when the snippet is the message.
    case codeFocus

    /// A minimal headline-only layout that drops the code panel and centers the
    /// title/subtitle — for announcements and quotes.
    case headline

    var id: String { rawValue }

    /// A short, human-readable name for the picker.
    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .codeFocus: "Code focus"
        case .headline: "Headline"
        }
    }

    /// One-line guidance shown next to the picker.
    var summary: String {
        switch self {
        case .standard: "Headline above a highlighted code excerpt, with a footer."
        case .codeFocus: "The code excerpt takes center stage, framed by the copy."
        case .headline: "Headline and subtitle only — no code panel."
        }
    }

    /// Whether this template draws the code excerpt panel at all. The headline
    /// template omits it, so the renderer can validate inputs accordingly.
    var showsCode: Bool {
        self != .headline
    }

    /// The value used when nothing is persisted or a stored string no longer maps
    /// to a case (documented fallback).
    static let fallback: SocialCardTemplate = .standard

    /// Decodes a persisted raw value, tolerating `nil` or an unrecognized string by
    /// returning `fallback`.
    static func resolve(_ rawValue: String?) -> SocialCardTemplate {
        SocialCardTemplate(rawValue: rawValue ?? "") ?? fallback
    }
}

// MARK: - Codable

extension SocialCardModel: Codable {
    private enum CodingKeys: String, CodingKey {
        case title, subtitle, codeExcerpt, language, author, project
        case showLogo, template, theme, background, fontName, fontSize
    }

    /// Decodes tolerantly and re-validates every field, so a hand-edited or corrupt
    /// blob can never feed an unknown theme/language, an out-of-range font, or an
    /// over-long excerpt into the renderer — it degrades to the documented default
    /// instead (defensive behavior). Text fields are re-normalized; the excerpt is
    /// re-truncated; the font size is re-clamped.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLanguage = try container.decodeIfPresent(String.self, forKey: .language)
        let rawTheme = try container.decodeIfPresent(String.self, forKey: .theme)
        self.init(
            title: try container.decodeIfPresent(String.self, forKey: .title),
            subtitle: try container.decodeIfPresent(String.self, forKey: .subtitle),
            codeExcerpt: try container.decodeIfPresent(String.self, forKey: .codeExcerpt) ?? "",
            language: Language(rawValue: rawLanguage ?? "") ?? .swift,
            author: try container.decodeIfPresent(String.self, forKey: .author),
            project: try container.decodeIfPresent(String.self, forKey: .project),
            showLogo: try container.decodeIfPresent(Bool.self, forKey: .showLogo) ?? false,
            template: SocialCardTemplate.resolve(
                try container.decodeIfPresent(String.self, forKey: .template)),
            theme: Theme.theme(withID: rawTheme ?? Theme.oneDark.id),
            background: (try? container.decode(BackgroundStyle.self, forKey: .background))
                ?? .gradient(.aurora),
            fontName: try container.decodeIfPresent(String.self, forKey: .fontName)
                ?? CodeFont.default,
            fontSize: try container.decodeIfPresent(Double.self, forKey: .fontSize)
                ?? Self.defaultFontSize
        )
    }

    /// Encodes the normalized fields. The theme is stored by id and the language by
    /// raw value so the on-disk shape is human-readable and resilient.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(codeExcerpt, forKey: .codeExcerpt)
        try container.encode(language.rawValue, forKey: .language)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encode(showLogo, forKey: .showLogo)
        try container.encode(template.rawValue, forKey: .template)
        try container.encode(theme.id, forKey: .theme)
        try container.encode(background, forKey: .background)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(fontSize, forKey: .fontSize)
    }
}

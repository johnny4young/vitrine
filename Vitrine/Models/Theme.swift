import Foundation
import SwiftUI

/// A code theme is a **syntax/theme palette** (CS-006/052/031). The theme controls
/// only the syntax colors; the code-card background is taken from the palette's own
/// background (see `HighlightManager.backgroundColor(for:)`), and the canvas
/// background (gradient/solid/transparent) is configured separately.
///
/// A theme has one of two origins, distinguished by `source`:
///
/// - **Built-in** themes ship with the app and resolve through a Highlight.js
///   stylesheet bundled with Highlightr (`hlJsTheme`). They are immutable.
/// - **Custom** themes (CS-031) are user-defined and carry their own `palette`,
///   which `HighlightManager` synthesizes into a Highlight.js-compatible stylesheet
///   at render time. They are stored, imported, and exported through
///   `CustomThemeStore` and never overwrite a built-in.
///
/// ## Adding a built-in theme (a one-file change, CS-052)
///
/// To add a built-in theme, declare a `static let` whose `hlJsTheme` is the name of
/// a Highlight.js stylesheet bundled with Highlightr, then list it in `builtIns`.
/// Because the card background is *derived* from that stylesheet — never a hand
/// picked color — a built-in theme stays a pure syntax theme and cannot drift from
/// its upstream palette. `appearance` records whether the theme reads as dark or
/// light so menus can group it; it is metadata only and does not change rendering.
/// `CoverageMatrixTests` verifies every advertised built-in theme resolves to a
/// real syntax palette and a non-default background, so a misspelled `hlJsTheme`
/// fails the build instead of silently falling back.
struct Theme: Identifiable, Hashable, Sendable {
    /// Whether a theme reads as dark or light. Curatorial metadata for built-ins
    /// (the rendered background and syntax colors always come from the Highlight.js
    /// stylesheet); for a custom theme it is derived from the palette's background.
    enum Appearance: String, Hashable, Sendable, Codable {
        case dark, light
    }

    /// Where a theme's colors come from: a bundled Highlight.js stylesheet
    /// (built-in) or a user-defined palette (custom, CS-031).
    enum Source: Hashable, Sendable {
        /// A built-in theme backed by the named Highlight.js stylesheet.
        case builtIn(hlJsTheme: String)
        /// A user-defined theme carrying its own palette.
        case custom(ThemePalette)
    }

    let id: String
    let displayName: String
    /// Curatorial dark/light grouping; defaults to dark.
    var appearance: Appearance = .dark
    /// The origin of this theme's colors.
    let source: Source

    /// Whether this theme is a built-in (immutable) one. Recomputed from the
    /// built-in catalog rather than trusted from any persisted flag, so origin can
    /// never be spoofed by a hand-edited theme file (CS-031).
    var isBuiltIn: Bool { Self.builtInIDs.contains(id) }

    /// The Highlight.js stylesheet name for a built-in theme, or `nil` for a custom
    /// one. `HighlightManager` uses this to load a bundled stylesheet.
    var hlJsTheme: String? {
        if case .builtIn(let name) = source { return name }
        return nil
    }

    /// The user-defined palette for a custom theme, or `nil` for a built-in one.
    /// `HighlightManager` synthesizes this into a Highlight.js stylesheet.
    var palette: ThemePalette? {
        if case .custom(let palette) = source { return palette }
        return nil
    }

    /// Convenience initializer for a built-in theme backed by a bundled
    /// Highlight.js stylesheet. `nonisolated` so the built-in `static let` catalog
    /// (also `nonisolated`) can construct themes off the main actor.
    nonisolated init(
        id: String, displayName: String, hlJsTheme: String, appearance: Appearance = .dark
    ) {
        self.id = id
        self.displayName = displayName
        self.appearance = appearance
        self.source = .builtIn(hlJsTheme: hlJsTheme)
    }

    /// Builds a custom theme from a user-defined palette (CS-031). The appearance is
    /// derived from the palette's background luminance so menus group it correctly.
    nonisolated init(id: String, displayName: String, palette: ThemePalette) {
        self.id = id
        self.displayName = displayName
        self.appearance = palette.appearance
        self.source = .custom(palette)
    }

    // The built-in catalog is `nonisolated`: a built-in `Theme` is an immutable
    // `Sendable` value, so its set is safe to read from any context (including the
    // Swift Testing `@Test(arguments:)` parameter lists in `CoverageMatrixTests`,
    // which the macro evaluates outside the main actor).

    // Dark themes — the signature look, listed first.
    nonisolated static let oneDark = Theme(
        id: "one-dark", displayName: "One Dark", hlJsTheme: "atom-one-dark")
    nonisolated static let nightOwl = Theme(
        id: "night-owl", displayName: "Night Owl", hlJsTheme: "night-owl")
    nonisolated static let dracula = Theme(
        id: "dracula", displayName: "Dracula", hlJsTheme: "dracula")
    nonisolated static let monokai = Theme(
        id: "monokai", displayName: "Monokai", hlJsTheme: "monokai")
    nonisolated static let nord = Theme(id: "nord", displayName: "Nord", hlJsTheme: "nord")
    nonisolated static let gruvbox = Theme(
        id: "gruvbox", displayName: "Gruvbox", hlJsTheme: "gruvbox-dark")
    nonisolated static let tokyoNight = Theme(
        id: "tokyo-night", displayName: "Tokyo Night", hlJsTheme: "tokyo-night-dark")
    nonisolated static let solarized = Theme(
        id: "solarized", displayName: "Solarized", hlJsTheme: "solarized-dark")
    nonisolated static let githubDark = Theme(
        id: "github-dark", displayName: "GitHub Dark", hlJsTheme: "github-dark")
    nonisolated static let xcodeDark = Theme(
        id: "xcode-dark", displayName: "Xcode Dark", hlJsTheme: "xcode-dark")

    // Light themes.
    nonisolated static let github = Theme(
        id: "github", displayName: "GitHub", hlJsTheme: "github", appearance: .light)
    nonisolated static let oneLight = Theme(
        id: "one-light", displayName: "One Light", hlJsTheme: "atom-one-light", appearance: .light)
    nonisolated static let solarizedLight = Theme(
        id: "solarized-light", displayName: "Solarized Light", hlJsTheme: "solarized-light",
        appearance: .light)

    /// All bundled (built-in) themes, in menu order (dark set first, then light).
    nonisolated static let builtIns: [Theme] = [
        .oneDark, .nightOwl, .dracula, .monokai, .nord, .gruvbox, .tokyoNight,
        .solarized, .githubDark, .xcodeDark,
        .github, .oneLight, .solarizedLight,
    ]

    /// The set of ids reserved for built-in themes, used to recompute `isBuiltIn`
    /// and to refuse any custom theme that would shadow a built-in (CS-031).
    nonisolated static let builtInIDs: Set<String> = Set(builtIns.map(\.id))

    /// Backwards-compatible alias for the built-in catalog. Existing call sites and
    /// the coverage matrix iterate `Theme.all`; it lists only the built-ins, which
    /// are the immutable, always-present set.
    nonisolated static var all: [Theme] { builtIns }

    /// Looks up a **built-in** theme by id, falling back to One Dark.
    ///
    /// Custom themes (CS-031) live in `CustomThemeStore` and are resolved through
    /// `CustomThemeStore.shared.theme(withID:)`, which falls back to this for a
    /// built-in id or an unknown one. This function stays `nonisolated` and
    /// pure so the `Codable`, off-main-actor call sites (`Capture`, `StyleSnapshot`)
    /// keep resolving built-ins without touching the main-actor store.
    nonisolated static func theme(withID id: String) -> Theme {
        builtIns.first { $0.id == id } ?? .oneDark
    }
}

// MARK: - Custom theme palette (CS-031)

/// A user-defined syntax palette: the documented schema a custom theme file carries
/// (CS-031).
///
/// A palette is a small, self-contained set of named hex colors — a `background`,
/// a default `foreground`, and one color per syntax token group (keywords, strings,
/// comments, …). `HighlightManager` synthesizes it into a Highlight.js-compatible
/// stylesheet at render time, so a custom theme paints real syntax colors over its
/// own background without referencing any bundled stylesheet, and built-in themes
/// are never touched (their colors still come from Highlightr).
///
/// ## Validation
///
/// `background` and `foreground` are **required**; the token colors are optional and
/// fall back to `foreground` when omitted, so a minimal two-color file is valid.
/// Every supplied value must be a `#RGB`/`#RGBA`/`#RRGGBB`/`#RRGGBBAA` hex string.
/// `validated(...)` and the throwing decoder reject a bad color or a missing
/// required key with a specific `ValidationError` (CS-031 "bad colors or missing
/// keys fail with clear validation errors"), so an invalid file is refused up front
/// rather than feeding a broken color into the renderer.
///
/// Because the palette is captured by value and resolved through a fixed sRGB
/// representation, the same palette renders the same pixels on any Mac, which keeps
/// exported screenshots deterministic across custom themes (CS-031 acceptance).
struct ThemePalette: Hashable, Sendable, Codable {
    /// The card background the code sits on (the only background a syntax theme
    /// owns; the canvas background is configured separately).
    var background: HexColor
    /// The default text color, used for any token group not given its own color.
    var foreground: HexColor
    /// Language keywords (`func`, `return`, `if`, …).
    var keyword: HexColor
    /// String and character literals.
    var string: HexColor
    /// Comments.
    var comment: HexColor
    /// Numeric and boolean/`nil` literals.
    var number: HexColor
    /// Type, class, and built-in names.
    var type: HexColor
    /// Function, method, and section/title names.
    var function: HexColor
    /// Variables, properties, parameters, and symbols.
    var variable: HexColor
    /// Attributes, tags, and meta/preprocessor markers.
    var attribute: HexColor

    /// Whether the palette reads as dark or light, derived from the background's
    /// luminance. Drives a custom theme's curatorial `appearance` so it groups with
    /// the built-ins of the same mood in menus.
    nonisolated var appearance: Theme.Appearance {
        background.relativeLuminance < 0.5 ? .dark : .light
    }

    /// Builds a palette from required `background`/`foreground` plus optional token
    /// colors that default to `foreground`. Used by tests and the editor.
    init(
        background: HexColor,
        foreground: HexColor,
        keyword: HexColor? = nil,
        string: HexColor? = nil,
        comment: HexColor? = nil,
        number: HexColor? = nil,
        type: HexColor? = nil,
        function: HexColor? = nil,
        variable: HexColor? = nil,
        attribute: HexColor? = nil
    ) {
        self.background = background
        self.foreground = foreground
        self.keyword = keyword ?? foreground
        self.string = string ?? foreground
        self.comment = comment ?? foreground
        self.number = number ?? foreground
        self.type = type ?? foreground
        self.function = function ?? foreground
        self.variable = variable ?? foreground
        self.attribute = attribute ?? foreground
    }

    /// A problem found while validating a palette, each mapping to clear user-facing
    /// copy at the call site (CS-031 "clear validation errors").
    enum ValidationError: Error, Equatable {
        /// A required key (`background` or `foreground`) was missing.
        case missingKey(String)
        /// A value was present but not a valid hex color.
        case invalidColor(key: String, value: String)

        /// A short, human-readable explanation for an alert.
        var message: String {
            switch self {
            case .missingKey(let key):
                "The theme is missing the required \"\(key)\" color."
            case .invalidColor(let key, let value):
                "The \"\(key)\" color \"\(value)\" is not a valid hex color (e.g. \"#1E1E1E\")."
            }
        }
    }

    // MARK: Codable — required keys throw, optional token colors default

    private enum CodingKeys: String, CodingKey {
        case background, foreground, keyword, string, comment, number
        case type, function, variable, attribute
    }

    /// Decodes a palette from a theme file, **rejecting** a missing required key or
    /// any invalid color so a bad file fails with a clear error instead of crashing
    /// or silently degrading (CS-031). Optional token colors default to `foreground`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try Self.decodeRequired(container, .background)
        foreground = try Self.decodeRequired(container, .foreground)
        keyword = try Self.decodeOptional(container, .keyword) ?? foreground
        string = try Self.decodeOptional(container, .string) ?? foreground
        comment = try Self.decodeOptional(container, .comment) ?? foreground
        number = try Self.decodeOptional(container, .number) ?? foreground
        type = try Self.decodeOptional(container, .type) ?? foreground
        function = try Self.decodeOptional(container, .function) ?? foreground
        variable = try Self.decodeOptional(container, .variable) ?? foreground
        attribute = try Self.decodeOptional(container, .attribute) ?? foreground
    }

    /// Decodes a required color string into a validated `HexColor`, throwing a
    /// specific `ValidationError` for a missing key or an unparseable value.
    private static func decodeRequired(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> HexColor {
        guard let raw = try? container.decode(String.self, forKey: key) else {
            throw ValidationError.missingKey(key.stringValue)
        }
        guard let color = HexColor(raw) else {
            throw ValidationError.invalidColor(key: key.stringValue, value: raw)
        }
        return color
    }

    /// Decodes an optional color string, returning `nil` when the key is absent but
    /// still rejecting a present-but-invalid value (a typo should surface, not be
    /// silently dropped).
    private static func decodeOptional(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> HexColor? {
        guard let raw = try? container.decode(String.self, forKey: key) else { return nil }
        guard let color = HexColor(raw) else {
            throw ValidationError.invalidColor(key: key.stringValue, value: raw)
        }
        return color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(background.hexString, forKey: .background)
        try container.encode(foreground.hexString, forKey: .foreground)
        try container.encode(keyword.hexString, forKey: .keyword)
        try container.encode(string.hexString, forKey: .string)
        try container.encode(comment.hexString, forKey: .comment)
        try container.encode(number.hexString, forKey: .number)
        try container.encode(type.hexString, forKey: .type)
        try container.encode(function.hexString, forKey: .function)
        try container.encode(variable.hexString, forKey: .variable)
        try container.encode(attribute.hexString, forKey: .attribute)
    }

    // MARK: Highlight.js stylesheet synthesis

    /// Synthesizes a Highlight.js-compatible stylesheet for this palette, which
    /// `Highlightr.Theme(themeString:)` parses exactly like a bundled theme.
    ///
    /// Each token group maps to the Highlight.js classes Highlightr's parser keys
    /// on. `.hljs` carries the background and default foreground (Highlightr reads
    /// the card background from `.hljs { background }`), so a custom theme paints
    /// real syntax colors over its own background. The output uses only `color`/
    /// `background` declarations, the two properties Highlightr's CSS stripper
    /// understands, so no unsupported rule can leak through.
    var highlightJSStylesheet: String {
        var rules: [String] = [
            ".hljs{display:block;background:\(background.hexString);color:\(foreground.hexString);}"
        ]
        func rule(_ selectors: [String], _ color: HexColor) {
            let body = selectors.map { ".hljs-\($0)" }.joined(separator: ",")
            rules.append("\(body){color:\(color.hexString);}")
        }
        rule(["keyword", "literal", "selector-tag"], keyword)
        rule(["string", "regexp", "addition"], string)
        rule(["comment", "quote"], comment)
        rule(["number"], number)
        rule(["type", "class", "title.class_", "built_in", "builtin-name"], type)
        rule(["title", "title.function_", "function", "section", "name"], function)
        rule(["variable", "template-variable", "attr", "property", "symbol", "params"], variable)
        rule(["attribute", "tag", "meta", "selector-id", "selector-class"], attribute)
        return rules.joined(separator: "\n")
    }
}

// MARK: - Hex color (CS-031)

/// A validated sRGB color stored as a hex string, the on-disk form custom-theme
/// files use (CS-031).
///
/// Unlike `Color(hex:)` — which is a release-tolerant convenience that falls back to
/// black on bad input — `HexColor` is **strict**: its failable initializer returns
/// `nil` for anything that is not a `#RGB`/`#RGBA`/`#RRGGBB`/`#RRGGBBAA` hex string,
/// which is exactly what lets a theme file's validation reject a typo instead of
/// silently rendering the wrong color. The components are kept in `0...1` sRGB and
/// re-serialized to a canonical uppercase `#RRGGBB`/`#RRGGBBAA` string, so a palette
/// round-trips deterministically (and identically on any Mac), keeping exported
/// screenshots stable across custom themes.
struct HexColor: Hashable, Sendable {
    /// Straight (non-premultiplied) sRGB components in `0...1`.
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// Parses a hex string, returning `nil` for any malformed input. Accepts an
    /// optional leading `#` and the 3/4/6/8-digit forms; rejects everything else.
    init?(_ string: String) {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        guard cleaned.allSatisfy(\.isHexDigit) else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }

        switch cleaned.count {
        case 8:  // RRGGBBAA
            red = Double((value & 0xFF00_0000) >> 24) / 255
            green = Double((value & 0x00FF_0000) >> 16) / 255
            blue = Double((value & 0x0000_FF00) >> 8) / 255
            alpha = Double(value & 0x0000_00FF) / 255
        case 6:  // RRGGBB
            red = Double((value & 0xFF_0000) >> 16) / 255
            green = Double((value & 0x00_FF00) >> 8) / 255
            blue = Double(value & 0x00_00FF) / 255
            alpha = 1
        case 4:  // RGBA shorthand → each nibble doubled
            red = Double((value & 0xF000) >> 12) / 15
            green = Double((value & 0x0F00) >> 8) / 15
            blue = Double((value & 0x00F0) >> 4) / 15
            alpha = Double(value & 0x000F) / 15
        case 3:  // RGB shorthand
            red = Double((value & 0xF00) >> 8) / 15
            green = Double((value & 0x0F0) >> 4) / 15
            blue = Double(value & 0x00F) / 15
            alpha = 1
        default:
            return nil
        }
    }

    /// The canonical `#RRGGBB` (or `#RRGGBBAA` when not fully opaque) string, used
    /// for stylesheet synthesis and as the stable serialized form.
    var hexString: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let base = String(
            format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha >= 1 ? base : base + String(format: "%02X", byte(alpha))
    }

    /// Rec. 601 relative luminance in `0...1`, used to classify a palette as dark or
    /// light without an AppKit round-trip.
    nonisolated var relativeLuminance: Double {
        0.299 * red + 0.587 * green + 0.114 * blue
    }

    /// The SwiftUI color, reconstructed in the fixed sRGB space the components were
    /// parsed in so it renders identically on any display (CS-031 determinism).
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension HexColor: Codable {
    /// Decodes from the hex string form, rejecting a malformed value so a bad color
    /// never decodes to a misleading fallback (the surrounding `ThemePalette` maps
    /// this to a clear `ValidationError`).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let color = HexColor(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid hex color \"\(raw)\"")
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

import Foundation

/// The presentation/style of a snapshot, captured so it can be saved, named,
/// exported, imported, and shared as a reusable preset.
///
/// A `StyleSnapshot` is the *style half* of a `SnapshotConfig`: theme, font,
/// padding, chrome, shadow, line numbers, line wrapping, and the canvas background. It is
/// deliberately **presentation-only** — it never carries `code`, `language`, the
/// metadata header text, or the highlighted-line ranges, all of which describe a
/// *particular* capture rather than a reusable brand look. Applying a snapshot
/// therefore reframes how code is rendered and can never alter the user's source,
/// matching the philosophy `ExportPreset` already follows.
///
/// Every field is value-typed and `Codable`, and the decoder re-validates each one
/// (catalog membership for the theme and font, range clamps for the numbers,
/// `BackgroundStyle`'s own tolerant decode for the background). A hand-edited or
/// corrupt preset file can therefore never feed an unknown theme, a missing font,
/// or an out-of-range number into the renderer — it degrades to the documented
/// default instead.
struct StyleSnapshot: Hashable, Codable {
    /// The syntax theme id (e.g. `"dracula"`); resolved through `Theme.theme(withID:)`
    /// so an unknown id falls back to One Dark.
    var themeID: String
    /// The code font family name; only honored if it is a known `CodeFont`.
    var fontName: String
    /// Code point size, clamped to the Style slider range on decode.
    var fontSize: Double
    /// Whether programming ligatures are on.
    var fontLigatures: Bool
    /// Canvas padding in points, clamped to the Style slider range on decode.
    var padding: Double
    /// Code-card corner radius in points, clamped to its documented range.
    var cornerRadius: Double
    /// Whether the window chrome (traffic lights) is drawn.
    var showChrome: Bool
    /// Whether the drop shadow is drawn.
    var showShadow: Bool
    /// Whether a line-number gutter is drawn.
    var showLineNumbers: Bool
    /// Optional code soft-wrap column count; `nil` keeps the card size-to-content.
    var wrapColumns: Int?
    /// The canvas background. Round-trips through `BackgroundStyle`'s own tolerant
    /// `Codable`, which degrades an unknown gradient name or a corrupt blob to a
    /// safe value rather than failing the whole decode.
    var background: BackgroundStyle

    /// Captures the style of `config` into a portable snapshot.
    ///
    /// An **image** background is not portable — it points at a file in this app's
    /// container that will not exist on another machine or after a reset — so it is
    /// replaced by the signature aurora gradient when captured. Every other
    /// background kind (solid, gradient preset, custom gradient, transparent) is
    /// self-contained and captured by value. Code, language, header text, and
    /// highlighted lines are intentionally excluded.
    init(capturing config: SnapshotConfig) {
        self.themeID = config.theme.id
        self.fontName = config.fontName
        self.fontSize = config.fontSize
        self.fontLigatures = config.fontLigatures
        self.padding = config.padding
        self.cornerRadius = config.cornerRadius
        self.showChrome = config.showChrome
        self.showShadow = config.showShadow
        self.showLineNumbers = config.showLineNumbers
        self.wrapColumns = config.wrapColumns.map(SettingsDefaults.clampWrapColumns)
        self.background = Self.portableBackground(config.background)
    }

    /// The full-fidelity initializer used by built-in presets and tests, applying
    /// the same clamps and image-background rule as a captured snapshot.
    init(
        themeID: String,
        fontName: String = CodeFont.default,
        fontSize: Double = SettingsDefaults.fontSize,
        fontLigatures: Bool = false,
        padding: Double = SettingsDefaults.padding,
        cornerRadius: Double = SettingsDefaults.cornerRadius,
        showChrome: Bool = true,
        showShadow: Bool = true,
        showLineNumbers: Bool = false,
        wrapColumns: Int? = nil,
        background: BackgroundStyle
    ) {
        self.themeID = themeID
        self.fontName = fontName
        self.fontSize = SettingsDefaults.clampFontSize(fontSize)
        self.fontLigatures = fontLigatures
        self.padding = SettingsDefaults.clampPadding(padding)
        self.cornerRadius = SettingsDefaults.clampCornerRadius(cornerRadius)
        self.showChrome = showChrome
        self.showShadow = showShadow
        self.showLineNumbers = showLineNumbers
        self.wrapColumns = wrapColumns.map(SettingsDefaults.clampWrapColumns)
        self.background = Self.portableBackground(background)
    }

    /// Applies this style to `config` in place, touching only presentation fields.
    ///
    /// The theme and font are resolved through the same catalog lookups the live
    /// reads use, so an id/name that no longer exists degrades to the default
    /// rather than producing a broken render. `code`, `language`, the metadata
    /// header, and highlighted-line ranges are never read or written here.
    func apply(to config: inout SnapshotConfig) {
        config.theme = Theme.theme(withID: themeID)
        config.fontName = CodeFont.all.contains(fontName) ? fontName : CodeFont.default
        config.fontSize = SettingsDefaults.clampFontSize(fontSize)
        config.fontLigatures = fontLigatures
        config.padding = SettingsDefaults.clampPadding(padding)
        config.cornerRadius = SettingsDefaults.clampCornerRadius(cornerRadius)
        config.showChrome = showChrome
        config.showShadow = showShadow
        config.showLineNumbers = showLineNumbers
        config.wrapColumns = wrapColumns.map(SettingsDefaults.clampWrapColumns)
        config.background = background
    }

    /// Replaces a non-portable image background with the signature gradient, while
    /// passing every self-contained background kind through untouched.
    private static func portableBackground(_ background: BackgroundStyle) -> BackgroundStyle {
        if case .image = background { return .gradient(.aurora) }
        return background
    }

    // MARK: Codable — re-validate every field so a corrupt file cannot crash

    private enum CodingKeys: String, CodingKey {
        case themeID, fontName, fontSize, fontLigatures, padding, cornerRadius
        case showChrome, showShadow, showLineNumbers, wrapColumns, background
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The theme/font are stored by id/name and re-validated on apply, so a
        // missing key here decodes to the default rather than failing the file.
        themeID =
            (try? container.decode(String.self, forKey: .themeID)) ?? Theme.oneDark.id
        fontName =
            (try? container.decode(String.self, forKey: .fontName)) ?? CodeFont.default
        fontSize = SettingsDefaults.clampFontSize(
            (try? container.decode(Double.self, forKey: .fontSize)) ?? SettingsDefaults.fontSize)
        fontLigatures =
            (try? container.decode(Bool.self, forKey: .fontLigatures)) ?? false
        padding = SettingsDefaults.clampPadding(
            (try? container.decode(Double.self, forKey: .padding)) ?? SettingsDefaults.padding)
        cornerRadius = SettingsDefaults.clampCornerRadius(
            (try? container.decode(Double.self, forKey: .cornerRadius))
                ?? SettingsDefaults.cornerRadius)
        showChrome = (try? container.decode(Bool.self, forKey: .showChrome)) ?? true
        showShadow = (try? container.decode(Bool.self, forKey: .showShadow)) ?? true
        showLineNumbers = (try? container.decode(Bool.self, forKey: .showLineNumbers)) ?? false
        if let columns = try? container.decode(Int.self, forKey: .wrapColumns) {
            wrapColumns = SettingsDefaults.clampWrapColumns(columns)
        } else {
            wrapColumns = nil
        }
        // A missing or corrupt background degrades to the signature gradient rather
        // than failing the whole snapshot.
        let decodedBackground =
            (try? container.decode(BackgroundStyle.self, forKey: .background)) ?? .gradient(.aurora)
        background = Self.portableBackground(decodedBackground)
    }
}

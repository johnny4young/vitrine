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
public struct StyleSnapshot: Hashable, Codable, Sendable {
    /// The syntax theme id (e.g. `"dracula"`); resolved when the snapshot is
    /// applied so callers with a wider catalog can restore custom themes too.
    public var themeID: String
    /// The code font family name; only honored if it is a known `CodeFont`.
    public var fontName: String
    /// Code point size, clamped to the Style slider range on decode.
    public var fontSize: Double
    /// Whether programming ligatures are on.
    public var fontLigatures: Bool
    /// Canvas padding in points, clamped to the Style slider range on decode.
    public var padding: Double
    /// Code-card corner radius in points, clamped to its documented range.
    public var cornerRadius: Double
    /// Whether the window chrome (traffic lights) is drawn.
    public var showChrome: Bool
    /// Whether the drop shadow is drawn.
    public var showShadow: Bool
    /// Drop-shadow blur radius in points ("Shadow depth"), clamped to its documented
    /// range. Part of the shadow look alongside `showShadow`; presets saved before this
    /// field existed decode to the type default.
    public var shadowRadius: Double
    /// Whether a line-number gutter is drawn.
    public var showLineNumbers: Bool
    /// Optional code soft-wrap column count; `nil` keeps the card size-to-content.
    public var wrapColumns: Int?
    /// The canvas background. Round-trips through `BackgroundStyle`'s own tolerant
    /// `Codable`, which degrades an unknown gradient name or a corrupt blob to a
    /// safe value rather than failing the whole decode.
    public var background: BackgroundStyle

    /// The full-fidelity initializer used by built-in presets and tests, applying
    /// the same clamps and image-background rule as a captured snapshot.
    public init(
        themeID: String,
        fontName: String = SettingsDefaults.fontName,
        fontSize: Double = SettingsDefaults.fontSize,
        fontLigatures: Bool = false,
        padding: Double = SettingsDefaults.padding,
        cornerRadius: Double = SettingsDefaults.cornerRadius,
        showChrome: Bool = true,
        showShadow: Bool = true,
        shadowRadius: Double = SettingsDefaults.shadowRadius,
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
        self.shadowRadius = SettingsDefaults.clampShadowRadius(shadowRadius)
        self.showLineNumbers = showLineNumbers
        self.wrapColumns = wrapColumns.map(SettingsDefaults.clampWrapColumns)
        self.background = Self.portableBackground(background)
    }

    /// Replaces a non-portable image background with the signature gradient, while
    /// passing every self-contained background kind through untouched.
    public static func portableBackground(_ background: BackgroundStyle) -> BackgroundStyle {
        if case .image = background { return .gradient(.aurora) }
        return background
    }

    // MARK: Codable — re-validate every field so a corrupt file cannot crash

    private enum CodingKeys: String, CodingKey {
        case themeID, fontName, fontSize, fontLigatures, padding, cornerRadius
        case showChrome, showShadow, shadowRadius, showLineNumbers, wrapColumns, background
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The theme/font are stored by id/name and re-validated on apply, so a
        // missing key here decodes to the default rather than failing the file.
        themeID =
            (try? container.decode(String.self, forKey: .themeID)) ?? Theme.oneDark.id
        fontName =
            (try? container.decode(String.self, forKey: .fontName)) ?? SettingsDefaults.fontName
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
        // Presets saved before this field existed have no key: decode to the type
        // default so an older file applies exactly as it did when it was saved.
        shadowRadius = SettingsDefaults.clampShadowRadius(
            (try? container.decode(Double.self, forKey: .shadowRadius))
                ?? SettingsDefaults.shadowRadius)
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

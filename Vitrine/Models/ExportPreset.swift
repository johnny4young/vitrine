import SwiftUI

/// One-click image-size/style presets for the surfaces developers actually post
/// to (CS-020).
///
/// A preset is **presentation/output only**: applying one mutates the snapshot's
/// look (padding, background) and pins an exact output size and scale, but it
/// never touches `code` or `language`. The user's source is sacred; a preset
/// only reframes how it is rendered. This keeps switching presets a safe,
/// reversible operation that never risks the thing being captured. Every shipped
/// destination pins a `.fixed` canvas at its platform's native pixels, so the
/// export is exactly the shape its name promises (e.g. X / Twitter is 1600×900);
/// the code card is centered and the background fills the frame (see SnapshotCanvas).
struct ExportPreset: Identifiable, Hashable {
    /// Stable identifier persisted in preferences and used for menu tags.
    let id: String
    /// Human-readable name shown in the picker (e.g. "X / Twitter").
    let displayName: String
    /// One-line guidance shown as help text next to the picker.
    let summary: String
    /// How the rendered canvas should be sized for this destination.
    let sizing: Sizing
    /// Export resolution multiplier the destination expects. Fixed-size presets
    /// (OpenGraph) pin this to `1` so the logical and pixel sizes match.
    let scale: Int
    /// Background guidance: the canvas background a preset suggests, or `nil`
    /// to leave the user's current background untouched.
    let background: BackgroundStyle?
    /// Canvas padding guidance, in points, applied to `SnapshotConfig.padding`.
    let padding: Double

    /// How a preset constrains the rendered canvas size.
    enum Sizing: Hashable {
        /// Render at an exact logical-pixel canvas (width × height). The exporter
        /// fills this frame precisely; OpenGraph uses 1200×630.
        case fixed(width: Double, height: Double)
        /// Recommend an aspect ratio (width : height) without forcing a size; the
        /// canvas still hugs its content. The content-hugging alternative to
        /// `.fixed` — no shipped destination uses it (they all pin exact pixels), but
        /// it stays available for a future "shape only" preset.
        case aspect(width: Double, height: Double)

        /// The exact logical pixel size to render, when the preset pins one.
        var fixedSize: CGSize? {
            if case .fixed(let width, let height) = self {
                return CGSize(width: width, height: height)
            }
            return nil
        }

        /// The width : height ratio this preset targets, for both fixed and
        /// aspect sizing. Never zero (every preset declares positive dimensions).
        var aspectRatio: Double {
            switch self {
            case .fixed(let width, let height), .aspect(let width, let height):
                height == 0 ? 1 : width / height
            }
        }
    }

    /// Applies this preset's presentation/output guidance to `config` in place.
    ///
    /// Only presentation fields are written: padding and (when the preset
    /// declares one) the background. `code` and `language` are never read or
    /// modified, so applying a preset can never alter the user's source.
    func apply(to config: inout SnapshotConfig) {
        config.padding = SettingsDefaults.clampPadding(padding)
        if let background {
            config.background = background
        }
    }

    /// Whether `config` already matches everything this preset would apply, so
    /// the picker can reflect the active preset (and fall back to "Custom" once
    /// the user diverges). Scale is compared by the caller, which owns it.
    func matches(_ config: SnapshotConfig) -> Bool {
        guard config.padding == SettingsDefaults.clampPadding(padding) else { return false }
        if let background, config.background != background { return false }
        return true
    }
}

extension ExportPreset {
    /// X / Twitter timeline image — the 16:9 in-stream card at its native
    /// 1600×900 pixels, so the export is exactly the shape the timeline shows (CS-020).
    static let twitter = ExportPreset(
        id: "twitter",
        displayName: "X / Twitter",
        summary: "1600×900 (16:9) in-stream card.",
        sizing: .fixed(width: 1600, height: 900),
        scale: 1,
        background: .gradient(.aurora),
        padding: 40
    )

    /// LinkedIn feed image — the platform's 1.91:1 link-card shape at 1200×628 (CS-020).
    static let linkedIn = ExportPreset(
        id: "linkedin",
        displayName: "LinkedIn",
        summary: "1200×628 (1.91:1) feed image.",
        sizing: .fixed(width: 1200, height: 628),
        scale: 1,
        background: .gradient(.ocean),
        padding: 40
    )

    /// Keynote / slide deck — a full 1920×1080 (16:9) surface for presentations (CS-020).
    static let keynote = ExportPreset(
        id: "keynote",
        displayName: "Keynote",
        summary: "1920×1080 (16:9) slide with generous padding.",
        sizing: .fixed(width: 1920, height: 1080),
        scale: 1,
        background: .gradient(.night),
        padding: 56
    )

    /// Docs / blog — a tighter image that drops into prose without dominating it
    /// (CS-020). Leaves the background as-is so it can match a site's theme.
    static let docs = ExportPreset(
        id: "docs",
        displayName: "Docs / Blog",
        summary: "1200×800 (3:2) image for inline docs and blog posts.",
        sizing: .fixed(width: 1200, height: 800),
        scale: 1,
        background: nil,
        padding: 24
    )

    /// Transparent slide — real alpha for dropping onto any deck background
    /// (CS-020). Pairs transparency with no drop shadow downstream guidance.
    static let transparentSlide = ExportPreset(
        id: "transparent-slide",
        displayName: "Transparent Slide",
        summary: "1920×1080 (16:9) transparent layer for any slide.",
        sizing: .fixed(width: 1920, height: 1080),
        scale: 1,
        background: .transparent,
        padding: 48
    )

    /// OpenGraph card — exactly 1200×630 logical pixels at 1× (CS-020). The
    /// canonical link-preview size for X, Slack, Discord, and most CMSs.
    static let openGraph = ExportPreset(
        id: "opengraph",
        displayName: "OpenGraph 1200×630",
        summary: "Exact 1200×630 link-preview card at 1×.",
        sizing: .fixed(width: 1200, height: 630),
        scale: 1,
        background: .gradient(.aurora),
        padding: 56
    )

    /// Instagram Story / Reels cover — the 9:16 vertical canvas at 1080×1920 (CS-020).
    static let instagramStory = ExportPreset(
        id: "instagram-story",
        displayName: "Instagram Story",
        summary: "1080×1920 (9:16) vertical story.",
        sizing: .fixed(width: 1080, height: 1920),
        scale: 1,
        background: .gradient(.sunset),
        padding: 64
    )

    /// GitHub README banner — a wide 2:1 header image at 1280×640 (CS-020).
    static let githubBanner = ExportPreset(
        id: "github-banner",
        displayName: "GitHub Banner",
        summary: "1280×640 (2:1) README header image.",
        sizing: .fixed(width: 1280, height: 640),
        scale: 1,
        background: .gradient(.carbon),
        padding: 48
    )

    /// All presets, in picker order.
    static let all: [ExportPreset] = [
        .twitter, .linkedIn, .keynote, .docs, .transparentSlide, .openGraph,
        .instagramStory, .githubBanner,
    ]

    /// Looks up a preset by id, returning `nil` for an unknown or absent id so
    /// the caller can present "Custom" (no preset applied).
    static func preset(withID id: String?) -> ExportPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

// MARK: - Style presets (CS-030)

/// The presentation/style of a snapshot, captured so it can be saved, named,
/// exported, imported, and shared as a reusable preset (CS-030).
///
/// A `StyleSnapshot` is the *style half* of a `SnapshotConfig`: theme, font,
/// padding, chrome, shadow, line numbers, and the canvas background. It is
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
/// default instead (CS-030 "invalid preset files do not crash", CS-050 spirit).
struct StyleSnapshot: Hashable, Codable {
    /// The syntax theme id (e.g. `"dracula"`); resolved through `Theme.theme(withID:)`
    /// so an unknown id falls back to One Dark.
    var themeID: String
    /// The code font family name; only honored if it is a known `CodeFont`.
    var fontName: String
    /// Code point size, clamped to the Style slider range on decode.
    var fontSize: Double
    /// Whether programming ligatures are on (CS-052).
    var fontLigatures: Bool
    /// Canvas padding in points, clamped to the Style slider range on decode.
    var padding: Double
    /// Code-card corner radius in points, clamped to its documented range.
    var cornerRadius: Double
    /// Whether the window chrome (traffic lights) is drawn.
    var showChrome: Bool
    /// Whether the drop shadow is drawn.
    var showShadow: Bool
    /// Whether a line-number gutter is drawn (CS-021).
    var showLineNumbers: Bool
    /// The canvas background. Round-trips through `BackgroundStyle`'s own tolerant
    /// `Codable`, which degrades an unknown gradient name or a corrupt blob to a
    /// safe value rather than failing the whole decode.
    var background: BackgroundStyle

    /// Captures the style of `config` into a portable snapshot (CS-030).
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
        case showChrome, showShadow, showLineNumbers, background
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
        // A missing or corrupt background degrades to the signature gradient rather
        // than failing the whole snapshot.
        let decodedBackground =
            (try? container.decode(BackgroundStyle.self, forKey: .background)) ?? .gradient(.aurora)
        background = Self.portableBackground(decodedBackground)
    }
}

/// A named, reusable style the user can save, apply, export, import, and share
/// (CS-030).
///
/// A preset pairs a stable `id` and a display `name` with a `StyleSnapshot`. Two
/// origins exist:
///
/// - **Built-in** presets ship with the app. They are immutable: the store never
///   lets one be renamed, edited, or deleted — only *duplicated* into an editable
///   user copy (CS-030 acceptance "built-in presets cannot be overwritten, only
///   duplicated"). `isBuiltIn` is recomputed from the catalog on load rather than
///   trusted from a file, so a shared file cannot smuggle in a fake "built-in"
///   flag to make itself uneditable.
/// - **User** presets are created by saving the current style, duplicating any
///   preset, or importing a file. They are fully editable.
struct StylePreset: Identifiable, Hashable, Codable {
    /// Stable identifier (a UUID string for user presets; a slug for built-ins).
    let id: String
    /// Human-readable name shown in the picker and list.
    var name: String
    /// The captured style this preset applies.
    var style: StyleSnapshot

    /// Whether this preset is a built-in (immutable) one. Recomputed from the
    /// built-in catalog on every load, never decoded from a file, so origin cannot
    /// be spoofed by a hand-edited preset.
    var isBuiltIn: Bool { Self.builtInIDs.contains(id) }

    init(id: String = UUID().uuidString, name: String, style: StyleSnapshot) {
        self.id = id
        self.name = StylePreset.sanitizedName(name)
        self.style = style
    }

    /// Builds a user preset capturing the current style of `config` under `name`.
    static func capturing(_ config: SnapshotConfig, name: String) -> StylePreset {
        StylePreset(name: name, style: StyleSnapshot(capturing: config))
    }

    /// Trims a user-entered name and collapses an empty result to a friendly
    /// default, so a preset always has a non-empty, tidy label.
    static func sanitizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Preset" : trimmed
    }

    // MARK: Codable — `isBuiltIn` is derived, never stored or trusted from a file

    private enum CodingKeys: String, CodingKey { case id, name, style }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A missing id gets a fresh one so an imported preset is always addressable
        // (and never collides under an empty key); the name is sanitized.
        let decodedID = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        id = decodedID.isEmpty ? UUID().uuidString : decodedID
        name = StylePreset.sanitizedName(
            (try? container.decode(String.self, forKey: .name)) ?? "")
        style = try container.decode(StyleSnapshot.self, forKey: .style)
    }

    func encode(to encoder: Encoder) throws {
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
    static let aurora = StylePreset(
        id: "builtin.aurora", name: "Aurora",
        style: StyleSnapshot(
            themeID: Theme.oneDark.id, padding: 40, background: .gradient(.aurora)))
    static let midnight = StylePreset(
        id: "builtin.midnight", name: "Midnight",
        style: StyleSnapshot(
            themeID: Theme.tokyoNight.id, padding: 48, background: .gradient(.night)))
    static let sunset = StylePreset(
        id: "builtin.sunset", name: "Sunset",
        style: StyleSnapshot(
            themeID: Theme.dracula.id, padding: 40, background: .gradient(.sunset)))
    static let minimal = StylePreset(
        id: "builtin.minimal", name: "Minimal Light",
        style: StyleSnapshot(
            themeID: Theme.github.id, padding: 32, showShadow: false, background: .solid(.white)))

    /// The built-in presets, in list order. They are immutable; the store offers
    /// "Duplicate" instead of editing or deleting any of them (CS-030).
    static let builtIns: [StylePreset] = [.aurora, .midnight, .sunset, .minimal]

    /// The set of ids that identify a built-in, used to recompute `isBuiltIn` on
    /// load so origin is never read from (or spoofed by) a file.
    static let builtInIDs: Set<String> = Set(builtIns.map(\.id))
}

/// The on-disk JSON envelope for exporting and importing style presets (CS-030).
///
/// Presets are shared as a single self-describing file: a `format` marker, a
/// `schemaVersion`, and the array of presets. Import is **strict about the
/// envelope** but **tolerant within each preset**: the document decoder rejects a
/// wrong format or an unsupported schema version up front (so a stray JSON file or
/// a future, unreadable layout fails fast with a clear error), while each
/// `StyleSnapshot` still self-heals individual fields. The result satisfies both
/// "validate schema version and allowed fields" and "invalid preset files do not
/// crash the app".
struct StylePresetDocument: Codable, Equatable {
    /// A fixed marker so a Vitrine preset file is recognizable and a random JSON
    /// file (or a different app's export) is rejected before any field is trusted.
    static let formatMarker = "vitrine.style-presets"
    /// The current preset-file schema version. Bump when the envelope's shape or
    /// meaning changes; older files are migrated or rejected, never misread.
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var presets: [StylePreset]

    /// Errors surfaced while importing a preset file. Each maps to clear, user
    /// facing copy at the call site (CS-030 "clear validation errors").
    enum ImportError: Error, Equatable {
        /// The bytes are not valid JSON / not a preset document at all.
        case notAPresetFile
        /// The file is a preset file but from an unsupported (usually newer)
        /// schema this build cannot read.
        case unsupportedSchemaVersion(Int)
        /// The file decoded but contained no usable presets.
        case empty

        /// A short, human-readable explanation for an alert.
        var message: String {
            switch self {
            case .notAPresetFile:
                "This file is not a Vitrine preset file."
            case .unsupportedSchemaVersion(let version):
                "This preset file uses a newer format (version \(version)) this app can't read."
            case .empty:
                "This preset file does not contain any presets."
            }
        }
    }

    /// Wraps presets for export at the current format and schema version.
    init(presets: [StylePreset]) {
        self.format = Self.formatMarker
        self.schemaVersion = Self.currentSchemaVersion
        self.presets = presets
    }

    private enum CodingKeys: String, CodingKey { case format, schemaVersion, presets }

    /// Decodes the envelope, rejecting anything that is not a Vitrine preset file.
    /// Individual presets remain tolerant; the envelope is what is validated here.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? container.decode(String.self, forKey: .format)) ?? ""
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0
        presets = (try? container.decode([StylePreset].self, forKey: .presets)) ?? []
    }

    /// Encodes a preset document as pretty, stable JSON (sorted keys) so an
    /// exported file is human-readable and diffable.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Parses and validates preset-file `data`, returning the contained presets or
    /// throwing a specific `ImportError` (CS-030).
    ///
    /// Validation order is deliberate: malformed JSON → not a preset file → wrong
    /// format marker → unsupported schema → empty. A valid document with at least
    /// one preset yields presets that have already self-healed every field, so the
    /// caller can adopt them without any further checking.
    static func presets(from data: Data) throws -> [StylePreset] {
        let document: StylePresetDocument
        do {
            document = try JSONDecoder().decode(StylePresetDocument.self, from: data)
        } catch {
            throw ImportError.notAPresetFile
        }
        guard document.format == formatMarker else { throw ImportError.notAPresetFile }
        guard document.schemaVersion <= currentSchemaVersion, document.schemaVersion >= 1 else {
            throw ImportError.unsupportedSchemaVersion(document.schemaVersion)
        }
        guard !document.presets.isEmpty else { throw ImportError.empty }
        return document.presets
    }
}

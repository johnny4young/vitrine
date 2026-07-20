import AppKit
import OSLog

/// The pure, testable state layer behind editor-window restoration and
/// multi-window editing.
///
/// Vitrine is a menu-bar agent that opens editor windows on demand. To behave like
/// a native multi-window Mac app, each window must:
///
/// - **Remember its size and position across launches** — handled by AppKit frame
///   autosave keyed by a per-window autosave name (``EditorWindowIdentity``), with a
///   recovery pass (``WindowFrameSolver``) that pulls a restored frame back onto a
///   visible screen when the display arrangement changed since it was saved.
/// - **Carry its own draft configuration** — each window edits an independent
///   ``SnapshotConfig`` rather than the app-wide default, captured for state
///   restoration by ``EditorWindowState`` so a relaunch can rebuild the exact
///   document that window held.
///
/// Everything here is free of live `NSWindow` instances and SwiftUI so the identity,
/// geometry, and encode/decode rules are unit-testable in isolation. The AppKit
/// wiring that consumes them lives in `EditorWindowController`.

// MARK: - Per-window identity (frame autosave name)

/// The stable identity of one editor window: a small integer index and the derived
/// frame-autosave name AppKit uses to persist that window's frame.
///
/// The first editor window is index 1 and autosaves under the bare `editor` name so
/// it keeps the frame an earlier single-window build saved (no migration needed);
/// subsequent windows append their index (`editor-2`, `editor-3`, …). Indexes are
/// assigned lowest-free-first so closing a window frees its slot for the next one,
/// which keeps the set of live autosave names — and therefore each window's restored
/// frame — stable as windows come and go.
struct EditorWindowIdentity: Equatable, Hashable {
    /// 1-based window index. Index 1 is the primary editor window.
    let index: Int

    init(index: Int) {
        // A window index is always positive; clamp a stray non-positive value to the
        // primary slot rather than minting an unusable autosave name.
        self.index = max(1, index)
    }

    /// The primary editor window.
    static let primary = EditorWindowIdentity(index: 1)

    /// The AppKit frame-autosave name for this window. The primary window keeps the
    /// bare base so an upgrade preserves the prior single-window frame; later windows
    /// are suffixed with their index.
    var frameAutosaveName: NSWindow.FrameAutosaveName {
        index == 1 ? Self.autosaveBase : "\(Self.autosaveBase)-\(index)"
    }

    /// The window-restoration identifier, mirroring the autosave name so the two
    /// addressing schemes stay aligned.
    var restorationIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(frameAutosaveName)
    }

    /// The window's title bar / Window-menu label. The primary window reads simply
    /// "Vitrine Editor"; additional windows append their index ("Vitrine Editor 2",
    /// "Vitrine Editor 3", …) so several open editors are distinguishable in the
    /// Window menu and Mission Control rather than all reading identically.
    /// Mirrors the index-suffix scheme of `frameAutosaveName` and the accessibility
    /// identifier. Localized through the String Catalog; the index is
    /// inserted into the localized template.
    var windowTitle: String {
        index == 1
            ? String(localized: "Vitrine Editor")
            : String(localized: "Vitrine Editor \(index)")
    }

    /// The base autosave name shared by the primary window and the prefix for the rest.
    static let autosaveBase = "editor"

    /// The lowest window index not present in `used`, so a closed window's slot is
    /// reused before a new, higher index is minted. Pure so window-lifecycle bookkeeping
    /// is unit-testable without creating real windows.
    static func nextAvailableIndex(notIn used: Set<Int>) -> Int {
        var candidate = 1
        while used.contains(candidate) { candidate += 1 }
        return candidate
    }
}

// MARK: - Per-window draft config (state restoration payload)

/// A fully `Codable`, value-typed snapshot of an editor window's ``SnapshotConfig``,
/// used as the per-window state-restoration payload.
///
/// `SnapshotConfig` carries a `Theme` (a SwiftUI-facing value that is deliberately
/// not `Codable`) and normalized line-highlight ranges, so it cannot be archived
/// directly. This bridge stores the same flat, defensively-decoded representation
/// `AppSettings` already persists — the theme by id, the language by raw value, the
/// highlighted lines as their canonical spec string, and the `Codable` background and
/// metadata verbatim — so a window's draft round-trips with exactly the same fidelity
/// and the same documented fallbacks as the app-wide settings (defensive posture).
///
/// Decoding resolves the theme through a ``CustomThemeStore`` so a window that was
/// editing a *custom* theme restores it, falling back to the built-in lookup (and
/// ultimately One Dark) for a built-in or unknown id. A missing or wrongly-typed
/// field decodes to the `SnapshotConfig` default for that field rather than throwing,
/// so a truncated or hand-edited restoration blob can never fail to rebuild a usable
/// document.
struct EditorWindowState: Codable, Equatable {
    var code: String
    var languageID: String
    var themeID: String
    var fontName: String
    var fontSize: Double
    var fontLigatures: Bool
    var padding: Double
    var cornerRadius: Double
    var shadowRadius: Double
    var showChrome: Bool
    var showShadow: Bool
    var showLineNumbers: Bool
    var highlightedLines: String
    var redactedLines: String
    var background: BackgroundStyle
    var metadata: SnapshotMetadata
    var foregroundImageFileName: String?
    var imageFrameID: String
    var imageFrameAppearanceID: String

    /// Captures `config` for archiving. Line ranges are flattened to their canonical
    /// spec string and the theme/language to their ids, matching how the rest of the
    /// app persists the same fields.
    init(config: SnapshotConfig) {
        code = config.code
        languageID = config.language.rawValue
        themeID = config.theme.id
        fontName = config.fontName
        fontSize = config.fontSize
        fontLigatures = config.fontLigatures
        padding = config.padding
        cornerRadius = config.cornerRadius
        shadowRadius = config.shadowRadius
        showChrome = config.showChrome
        showShadow = config.showShadow
        showLineNumbers = config.showLineNumbers
        highlightedLines = LineHighlight.describe(config.highlightedLineRanges)
        redactedLines = LineHighlight.describe(config.redactedLineRanges)
        background = config.background
        metadata = config.metadata
        foregroundImageFileName = config.foregroundImage?.fileName
        imageFrameID = config.imageFrame.rawValue
        imageFrameAppearanceID = config.imageFrameAppearance.rawValue
    }

    /// Rebuilds a `SnapshotConfig`, resolving the theme through `themes` (so a custom
    /// theme survives) and the language from its raw value, and re-parsing the
    /// line-highlight spec. Numeric fields are clamped to their documented ranges so a
    /// corrupt value can never drive the renderer out of bounds, mirroring
    /// `AppSettings.readConfig`.
    func config(themes: CustomThemeStore = .shared) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = code
        if let language = Language(rawValue: languageID) { config.language = language }
        config.theme = themes.theme(withID: themeID)
        if CodeFont.all.contains(fontName) { config.fontName = fontName }
        config.fontSize = SettingsDefaults.clampFontSize(fontSize)
        config.fontLigatures = fontLigatures
        config.padding = SettingsDefaults.clampPadding(padding)
        config.cornerRadius = SettingsDefaults.clampCornerRadius(cornerRadius)
        config.shadowRadius = SettingsDefaults.clampShadowRadius(shadowRadius)
        config.showChrome = showChrome
        config.showShadow = showShadow
        config.showLineNumbers = showLineNumbers
        config.highlightedLineRanges = LineHighlight.parse(highlightedLines)
        config.redactedLineRanges = LineHighlight.parse(redactedLines)
        config.background = background
        config.metadata = metadata
        if let foregroundImageFileName, !foregroundImageFileName.isEmpty {
            config.foregroundImage = ImageReference(fileName: foregroundImageFileName)
        }
        config.imageFrame = ImageFrame(rawValue: imageFrameID) ?? .none
        config.imageFrameAppearance = FrameAppearance(rawValue: imageFrameAppearanceID) ?? .auto
        return config
    }

    private enum CodingKeys: String, CodingKey {
        case code, languageID, themeID, fontName, fontSize, fontLigatures
        case padding, cornerRadius, shadowRadius, showChrome, showShadow
        case showLineNumbers, highlightedLines, redactedLines, background, metadata
        case foregroundImageFileName, imageFrameID, imageFrameAppearanceID
    }

    /// A defensive decoder: every field tolerates being absent or the wrong type by
    /// falling back to the `SnapshotConfig` default for that field, so a partial or
    /// hand-edited restoration payload still rebuilds a complete, valid draft.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SnapshotConfig()
        code = (try? container.decode(String.self, forKey: .code)) ?? fallback.code
        languageID =
            (try? container.decode(String.self, forKey: .languageID)) ?? fallback.language.rawValue
        themeID = (try? container.decode(String.self, forKey: .themeID)) ?? fallback.theme.id
        fontName = (try? container.decode(String.self, forKey: .fontName)) ?? fallback.fontName
        fontSize = (try? container.decode(Double.self, forKey: .fontSize)) ?? fallback.fontSize
        fontLigatures =
            (try? container.decode(Bool.self, forKey: .fontLigatures)) ?? fallback.fontLigatures
        padding = (try? container.decode(Double.self, forKey: .padding)) ?? fallback.padding
        cornerRadius =
            (try? container.decode(Double.self, forKey: .cornerRadius)) ?? fallback.cornerRadius
        shadowRadius =
            (try? container.decode(Double.self, forKey: .shadowRadius)) ?? fallback.shadowRadius
        showChrome = (try? container.decode(Bool.self, forKey: .showChrome)) ?? fallback.showChrome
        showShadow = (try? container.decode(Bool.self, forKey: .showShadow)) ?? fallback.showShadow
        showLineNumbers =
            (try? container.decode(Bool.self, forKey: .showLineNumbers)) ?? fallback.showLineNumbers
        highlightedLines =
            (try? container.decode(String.self, forKey: .highlightedLines))
            ?? LineHighlight.describe(fallback.highlightedLineRanges)
        redactedLines =
            (try? container.decode(String.self, forKey: .redactedLines))
            ?? LineHighlight.describe(fallback.redactedLineRanges)
        background =
            (try? container.decode(BackgroundStyle.self, forKey: .background))
            ?? fallback.background
        metadata =
            (try? container.decode(SnapshotMetadata.self, forKey: .metadata)) ?? fallback.metadata
        foregroundImageFileName =
            try? container.decodeIfPresent(String.self, forKey: .foregroundImageFileName)
        imageFrameID =
            (try? container.decode(String.self, forKey: .imageFrameID))
            ?? fallback.imageFrame.rawValue
        imageFrameAppearanceID =
            (try? container.decode(String.self, forKey: .imageFrameAppearanceID))
            ?? fallback.imageFrameAppearance.rawValue
    }

    /// JSON for archiving this draft into an `NSCoder` restoration record.
    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Rebuilds a draft from archived JSON, tolerating absent or corrupt bytes by
    /// yielding `nil` so the caller can fall back to the app-wide default config.
    static func decoded(from data: Data?) -> EditorWindowState? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(EditorWindowState.self, from: data)
    }
}

// MARK: - Off-screen recovery (frame geometry)

/// Pure geometry for keeping a restored window frame on a currently-visible screen
/// ("behaves correctly across display changes without off-screen windows").
///
/// A frame saved on one display arrangement can land entirely off-screen after a
/// monitor is unplugged or rearranged. ``onScreenFrame(for:visibleFrames:)`` decides
/// whether a frame still shows a usable amount of its title bar on *some* visible
/// screen; when it does not, the frame is nudged — or, as a last resort, re-centered —
/// back into the nearest visible screen, preserving the window's size. Operating on
/// plain `CGRect`s (the screens' `visibleFrame`s) keeps the whole policy testable
/// without a window server.
enum WindowFrameSolver {
    /// The minimum width and height of a window's frame that must remain inside a
    /// visible screen for the window to count as reachable. Generous enough to keep a
    /// grabbable strip of title bar on screen even when a window straddles an edge.
    static let minimumVisibleExtent: CGFloat = 80

    /// Whether `frame` exposes at least ``minimumVisibleExtent`` in both axes on any
    /// of `visibleFrames`. An empty screen list (no displays reported) is treated as
    /// "nothing is reachable" so the caller re-centers onto its fallback.
    static func isReachable(_ frame: CGRect, on visibleFrames: [CGRect]) -> Bool {
        guard !visibleFrames.isEmpty else { return false }
        return visibleFrames.contains { screen in
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { return false }
            return overlap.width >= effectiveExtent(frame.width)
                && overlap.height >= effectiveExtent(frame.height)
        }
    }

    /// Returns `frame` unchanged when it is already reachable, otherwise a frame moved
    /// fully inside the screen whose visible area it overlaps most (or, with no overlap
    /// at all, the largest screen). The size is preserved when it fits that screen and
    /// shrunk to the screen's size when it does not — a recovered window must be fully
    /// usable, and controls along the far edge of an overhanging window would stay
    /// unreachable (the small-display failure mode this guards against). With no
    /// visible screens the frame is returned as-is — the caller owns the "no displays"
    /// fallback.
    static func onScreenFrame(for frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        if isReachable(frame, on: visibleFrames) { return frame }
        let target = bestScreen(for: frame, in: visibleFrames)
        return clamp(frame, into: target)
    }

    /// Moves `frame` so it sits fully within `screen`, keeping its size when it fits.
    /// A frame wider or taller than the screen is resized down to the screen's extent
    /// on that axis, so the result never overhangs an edge.
    static func clamp(_ frame: CGRect, into screen: CGRect) -> CGRect {
        let size = CGSize(
            width: min(frame.width, screen.width),
            height: min(frame.height, screen.height))
        let origin = CGPoint(
            x: min(max(frame.minX, screen.minX), screen.maxX - size.width),
            y: min(max(frame.minY, screen.minY), screen.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }

    /// The screen whose visible area `frame` overlaps the most; with no overlap on any
    /// screen, the largest screen by area, so a fully off-screen window lands on the
    /// most spacious available display.
    private static func bestScreen(for frame: CGRect, in visibleFrames: [CGRect]) -> CGRect {
        if let overlapping = visibleFrames.max(by: { lhs, rhs in
            overlapArea(frame, lhs) < overlapArea(frame, rhs)
        }), overlapArea(frame, overlapping) > 0 {
            return overlapping
        }
        return visibleFrames.max(by: { $0.width * $0.height < $1.width * $1.height })
            ?? visibleFrames[0]
    }

    /// The area of the intersection of two rects, or 0 when they do not overlap.
    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return 0 }
        return overlap.width * overlap.height
    }

    /// The required on-screen extent along one axis: the minimum, but never more than
    /// the window's own size, so a window smaller than ``minimumVisibleExtent`` only
    /// has to be fully visible rather than impossibly over-visible.
    private static func effectiveExtent(_ dimension: CGFloat) -> CGFloat {
        min(minimumVisibleExtent, dimension)
    }
}

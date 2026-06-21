import Foundation

/// The bundled, offline release notes that back the "What's New" surface (CS-049).
///
/// Notes live in the repo (here) rather than being fetched, so the whole feature
/// works with no network access: the same binary that ships a version also ships
/// the notes for it. Each entry is a short, human-readable summary of what changed
/// in one shipped version; the newest entry leads the list.
///
/// The version strings are dotted numeric identifiers that match the app's
/// `CFBundleShortVersionString` (the `MARKETING_VERSION` in `project.yml`). The
/// gate that decides whether "What's New" should appear compares the latest
/// bundled version against the last one the user has seen, using
/// `SemanticVersion`'s numeric ordering rather than string comparison, so `0.10.0`
/// correctly sorts after `0.9.0`.
struct ReleaseNote: Identifiable, Equatable {
    /// The shipped version this note describes (e.g. `"0.1.0"`).
    let version: String
    /// A one-line headline for the release.
    let headline: String
    /// The notable changes in this version, each a short user-facing sentence.
    let highlights: [String]

    /// A stable identity for `ForEach`: a version ships its notes exactly once.
    var id: String { version }

    /// The version parsed for ordered comparison. A malformed string (not expected
    /// for a hand-authored note) sorts as the zero version so it can never mask a
    /// real, newer release in the gate.
    var semanticVersion: SemanticVersion { SemanticVersion(version) ?? .zero }
}

/// The single source of truth for Vitrine's bundled release notes (CS-049).
///
/// Authoring a release adds an entry here (newest first) as part of the release
/// checklist in `docs/RELEASING.md`, keeping the notes versioned in the repo and
/// shipped inside the app. Nothing here touches the network.
enum ReleaseNotes {
    /// Every shipped version's notes, newest first.
    ///
    /// Keep this ordered with the most recent release at the top; `latest` and the
    /// "What's New" list both assume index `0` is newest.
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "0.11.0",
            headline: "Turn terminal output into beautiful images",
            highlights: [
                "Paste colored terminal output — git, test runners, build logs — and "
                    + "Vitrine renders the ANSI colors and styles (bold, italic, underline, "
                    + "strikethrough) as a clean terminal image.",
                "The terminal card follows your theme: a light theme renders on a light "
                    + "card, and Dracula and Nord use their own signature palettes.",
                "Set up the shell helpers once with vitrine shell-init: vgrab copies an "
                    + "image of a command's colored output, and vlast shares the last command "
                    + "you ran — without re-running it.",
            ]),
        ReleaseNote(
            version: "0.10.0",
            headline: "Your accent, free brand placement, and polish",
            highlights: [
                "Vitrine's controls now follow your macOS accent color. On the default "
                    + "Multicolor, they keep Vitrine's signature accent.",
                "Brand Kit gains a Free placement: drag your mark anywhere on the image — in "
                    + "the editor or the Style preview.",
                "Annotations and highlighted lines now reset when you load new code (paste, "
                    + "drop, or quick capture), so old marks never strand over new content; a "
                    + "mid-edit paste keeps them.",
                "The menu-bar icon is the Vitrine logo now, with a tooltip on hover, and the "
                    + "Settings buttons and website got a cleaner, more legible pass.",
            ]),
        ReleaseNote(
            version: "0.9.0",
            headline: "Vitrine PRO, now available",
            highlights: [
                "You can buy Vitrine PRO now: the paywall and the website both link to a secure "
                    + "checkout, and the license key you get by email activates PRO — verified "
                    + "offline after the first check.",
                "Early-bird pricing: $19.99 through 2026 (regular price $25). One-time, not a "
                    + "subscription.",
                "PRO unlocks Brand Kit watermarks, multi-size one-pass export, and automation "
                    + "(the vitrine CLI, Shortcuts, and folder batch). The free tier loses nothing.",
            ]),
        ReleaseNote(
            version: "0.8.1",
            headline: "Vitrine PRO is here",
            highlights: [
                "Vitrine PRO unlocks Brand Kit watermarks on every export, multi-size "
                    + "one-pass export, and automation (the vitrine CLI, Shortcuts, and "
                    + "folder batch).",
                "Activate a one-time license key in the paywall — it's verified offline after "
                    + "the first check, so PRO keeps working with no network.",
                "The free tier loses nothing: no watermark, no resolution cap, no nags.",
            ]),
        ReleaseNote(
            version: "0.8.0",
            headline: "Web boards, and a faster Vitrine",
            highlights: [
                "Capture a page at several viewport sizes at once and Vitrine lays them out "
                    + "into one shareable responsive board (direct-download build).",
                "Copy a URL and Vitrine offers to open Web Snapshot prefilled with it, so a "
                    + "link becomes an image in two clicks.",
                "Faster across the board: quicker syntax highlighting, lighter exports, and a "
                    + "lighter Web Snapshot filmstrip.",
                "Menu-bar recents are now proper buttons for VoiceOver and the keyboard, the "
                    + "accent color resets to its default, and the What's New layout is tidier.",
                "Vitrine PRO is on the way: Brand Kit watermarks, multi-size one-pass export, "
                    + "and automation (the vitrine CLI, Shortcuts, and folder batch).",
            ]),
        ReleaseNote(
            version: "0.7.0",
            headline: "Annotate your screenshots",
            highlights: [
                "Mark up a snapshot from a new toolbar — arrows, lines, rectangles, text, "
                    + "a highlighter, blur boxes, and numbered counters — drawn right on the preview.",
                "Pick a tool and drag to draw, move and resize with handles, restyle the "
                    + "color and size, and undo or redo with ⌘Z.",
                "Two new export shapes — an Instagram Story (1080×1920) and a GitHub README "
                    + "banner — plus a View ▸ Theme quick menu and searchable theme and font pickers.",
                "Focus mode dims the lines outside your highlight, diff coloring paints + and − "
                    + "lines (automatic for the Diff language), and you can add a window title and "
                    + "tune corner radius and shadow.",
                "Drop an image background straight from a URL, and the editor now closes itself "
                    + "after you copy (with a Settings toggle).",
            ]),
        ReleaseNote(
            version: "0.6.0",
            headline: "Social cards and web snapshots",
            highlights: [
                "Compose a 1200×630 social card from your code — pick a template, "
                    + "theme, and background, then copy, save, or share it.",
                "Render pasted HTML to an image locally in the new Web Snapshot "
                    + "window — fully on your Mac, with no network.",
                "On the direct-download build, capture a webpage to an image: "
                    + "Vitrine loads it locally in WebKit, with a privacy disclosure first.",
            ]),
        ReleaseNote(
            version: "0.5.0",
            headline: "The command line, included",
            highlights: [
                "The vitrine command-line renderer now ships inside the app — "
                    + "Homebrew installs put it on your PATH automatically.",
                "Installed from the DMG? Settings ▸ General ▸ Command-line tool "
                    + "links the command for you.",
                "vitrine render input.swift --out image.png — output "
                    + "pixel-identical to the app, fully offline.",
            ]),
        ReleaseNote(
            version: "0.4.0",
            headline: "A fresh new look",
            highlights: [
                "Vitrine is redesigned end to end: the editor, Settings, Welcome, and "
                    + "the menu-bar panel now share one design language, light and dark.",
                "The editor preview floats in ambient light cast by your background "
                    + "and always scales to fit the window.",
                "Settings is a sidebar window with a pinned live preview and chip "
                    + "pickers for themes, fonts, and backgrounds.",
                "The menu-bar panel shows your recent captures with thumbnails — "
                    + "reopen one, or copy its image again, in a click.",
                "The Welcome tour now renders a real sample card you can restyle "
                    + "before your first capture.",
            ]),
        ReleaseNote(
            version: "0.3.0",
            headline: "Smarter windows, smarter paste",
            highlights: [
                "New and restored editor windows now size themselves to fit the screen, "
                    + "so nothing opens half off a smaller display.",
                "Pasted code is re-indented by structure, so snippets copied from deep "
                    + "nesting land clean.",
                "The Welcome tour and version-aware What's New now greet you on regular "
                    + "launches, not just from the Help menu.",
                "The main menu is fully localized, matching the rest of the app in Spanish.",
                "Pasted-HTML snapshots no longer load remote resources, keeping every "
                    + "render fully local.",
            ]),
        ReleaseNote(
            version: "0.1.0",
            headline: "Welcome to Vitrine",
            highlights: [
                "Turn copied code into a beautiful image from the menu bar with a global hotkey.",
                "A focused editor with curated themes, developer fonts, and adjustable padding, "
                    + "corner radius, window chrome, and line numbers.",
                "Destination and style presets, plus custom solid, gradient, and image backgrounds.",
                "Copy or save as PNG or PDF — with rich-text and data-URI copy options.",
                "Private by design: rendering is fully local, with no account, no network, and no "
                    + "screen-recording or Accessibility permission.",
            ]),
    ]

    /// The newest bundled release note, or `nil` if none are bundled. Callers gate
    /// on this being present, so an empty catalog simply never shows "What's New".
    static var latest: ReleaseNote? { all.first }

    /// The version string of the newest bundled note, used as the value to persist
    /// once the user has seen "What's New" for this version.
    static var latestVersion: String? { latest?.version }

    /// Decides whether the version-gated "What's New" should be presented (CS-049).
    ///
    /// It appears only when the newest bundled notes are strictly newer than the
    /// version the user last saw. The rules, in order:
    ///
    /// - With no bundled notes, there is nothing to show.
    /// - On a clean first run (`lastSeenVersion == nil`), it does **not** appear:
    ///   onboarding owns the first-run experience (CS-035), so a brand-new user is
    ///   never shown both. The current version is instead recorded as already seen
    ///   by the launch path so the *next* upgrade is what surfaces notes.
    /// - Otherwise it appears exactly when `latest > lastSeen`, and never for the
    ///   same or an older last-seen version (so it shows at most once per upgrade).
    ///
    /// This is a pure function of its inputs so the gate is trivial to unit-test
    /// without a running app or any persistence.
    static func shouldPresent(latest: ReleaseNote?, lastSeenVersion: String?) -> Bool {
        guard let latest else { return false }
        // First run: onboarding owns it; never show What's New on a clean install.
        guard let lastSeenVersion else { return false }
        // An unparseable persisted value is treated as "nothing meaningful seen
        // yet" — but since we already passed the first-run guard, fall back to the
        // zero version so a real, newer bundled version still surfaces once.
        let seen = SemanticVersion(lastSeenVersion) ?? .zero
        return latest.semanticVersion > seen
    }
}

/// A minimal, dependency-free semantic-version value for *ordering* version
/// strings (CS-049).
///
/// It parses a dotted numeric string (`"1.2.3"`, `"0.10"`, `"2"`) into its numeric
/// components and compares them component-by-component, so `"0.10.0"` sorts after
/// `"0.9.0"` where a plain string comparison would get it wrong. Missing trailing
/// components are treated as zero (`"1.2" == "1.2.0"`). A pre-release/build suffix
/// (anything after `-` or `+`) is ignored for ordering, matching the intent of
/// "is this build newer than what the user last saw".
///
/// This is intentionally tiny and total: any unparseable component makes the whole
/// parse fail (returning `nil`), and callers substitute `.zero`, so the gate can
/// never trap on a hand-edited or corrupt persisted value.
struct SemanticVersion: Comparable, Equatable {
    /// The numeric components, most-significant first (e.g. `[1, 2, 3]`).
    let components: [Int]

    /// The zero version (`0.0.0`), used as a safe floor for unparseable input.
    static let zero = SemanticVersion(components: [0])

    /// Parses a dotted numeric version, ignoring any `-`/`+` suffix. Returns `nil`
    /// for an empty string or a non-numeric component so callers can fall back.
    init?(_ string: String) {
        // Drop a SemVer pre-release/build suffix; only the numeric core orders.
        let core = string.prefix { $0 != "-" && $0 != "+" }
        let trimmed = core.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            guard let value = Int(part), value >= 0 else { return nil }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }
        components = parsed
    }

    private init(components: [Int]) {
        self.components = components
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            // Treat a missing trailing component as zero, so "1.2" == "1.2.0".
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

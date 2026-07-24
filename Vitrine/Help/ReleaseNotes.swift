import Foundation

/// The bundled, offline release notes that back the "What's New" surface.
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

/// The single source of truth for Vitrine's bundled release notes.
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
            version: "0.24.0",
            headline: "Terminal context, sturdier releases",
            highlights: [
                "Share terminal output that explains itself: vgrab now adds the project, "
                    + "current Git branch when available, and exact command above the result. "
                    + "Use --no-context whenever the command or branch should stay private.",
                "Release builds now use checksum-verified tooling, carry a dependency "
                    + "inventory, and exercise a safer App Store archive path before shipping.",
            ]),
        ReleaseNote(
            version: "0.23.0",
            headline: "Precise annotations, local previews",
            highlights: [
                "Edit annotations faster: duplicate a selected mark, nudge it one point "
                    + "at a time with the arrow keys (ten with Shift), and send it to the "
                    + "front or back — all backed by a bounded, reliable undo history.",
                "Capture a local dev server (direct-download build): turn on the "
                    + "explicit, default-off setting to snapshot a page running on this Mac. "
                    + "Access stays limited to localhost and loopback — LAN, .local, and "
                    + "metadata addresses remain blocked, including on redirects.",
            ]),
        ReleaseNote(
            version: "0.22.0",
            headline: "Faster previews, safer sharing",
            highlights: [
                "Find and run editor actions from the new Command Palette: press ⌘K, "
                    + "type a few letters, and apply themes, change the preview, or export "
                    + "without leaving the keyboard.",
                "Copy a fully local share link that opens the same styled snapshot in "
                    + "Vitrine — no server or upload. The link contains the snapshot's code, "
                    + "so review it before sharing sensitive content.",
                "Secret redaction now works on images with on-device OCR, while faster "
                    + "bounded preview caches and stricter input validation keep editing "
                    + "responsive and predictable.",
            ]),
        ReleaseNote(
            version: "0.21.0",
            headline: "From snapshot to post",
            highlights: [
                "Carousel export (PRO): split a long snippet into numbered 4:5 slides "
                    + "for a LinkedIn or Instagram carousel — balanced pages, your style "
                    + "and brand mark on every slide.",
                "Post to X, LinkedIn, or Bluesky straight from the share sheet: the "
                    + "image is staged on the clipboard and the compose page opens — one "
                    + "paste from posting, nothing sent by Vitrine.",
                "A bigger annotation toolkit: spotlight dimming, a pixel-measure ruler, "
                    + "curved arrows, and emoji stickers — plus a pinned floating "
                    + "snapshot, on-device OCR, HEIC export, and asciinema import.",
            ]),
        ReleaseNote(
            version: "0.20.0",
            headline: "Beautify any image, not just code",
            highlights: [
                "Drop, paste, or quick-capture any screenshot and render it on your "
                    + "backgrounds, padding, and shadow — then frame it as a macOS window, a "
                    + "browser, or a MacBook / iPhone mockup.",
                "Auto frame chrome: the title bar samples the image's top edge and tints "
                    + "itself to match, so the frame blends into the shot. Browser and device "
                    + "frames are PRO.",
            ]),
        ReleaseNote(
            version: "0.19.0",
            headline: "Redact secrets before you share",
            highlights: [
                "One-click Redact secrets: Vitrine scans your capture for likely API keys, "
                    + "tokens, passwords, and private keys and blurs those lines for you — "
                    + "terminal output included.",
                "The blur is leak-proof: the copyable text that travels with the image hides "
                    + "the same lines, so a secret can't slip out through the sidecar or clipboard.",
            ]),
        ReleaseNote(
            version: "0.18.0",
            headline: "Editable annotations, tool shortcuts, and a usability pass",
            highlights: [
                "Text annotations are editable: pick the Text tool and type right on the "
                    + "canvas — double-click to edit, Return to commit. Switch tools fast with "
                    + "⌘1–⌘8.",
                "Web captures you can stop: a long multi-size URL capture now shows progress "
                    + "and a Cancel button, and a quick-captured URL starts on its own.",
                "Clearer settings: Brand Kit is its own pane, and the editor explains that its "
                    + "controls style this capture while Settings sets the default for new ones.",
            ]),
        ReleaseNote(
            version: "0.17.0",
            headline: "Wrap long lines, and a snappier preview",
            highlights: [
                "New \"Wrap long lines\": a long line now soft-wraps to a column width instead "
                    + "of making an extremely wide image. Toggle it in the editor inspector and "
                    + "drag the width — the preview reflows live; off by default.",
                "Snappier editing: the recents gallery and the terminal / social-card previews "
                    + "render from a cache, so the app stays smooth even on large captures.",
            ]),
        ReleaseNote(
            version: "0.16.1",
            headline: "Sharper responsive boards and safer downloads",
            highlights: [
                "The responsive board's viewport labels no longer truncate — each render is "
                    + "captioned with its name above its exact size, so a tall full-page "
                    + "capture reads cleanly instead of showing \"Deskt…\".",
                "Hardened remote background-image downloads: size-bounded streaming that "
                    + "tears the transfer down the moment the cap is hit, with private and "
                    + "redirected targets refused before the request is followed.",
            ]),
        ReleaseNote(
            version: "0.16.0",
            headline: "Web Snapshot & Social Card, refined",
            highlights: [
                "The Web Snapshot and Social Card windows were redesigned to match the "
                    + "editor — cleaner inspectors, branded empty states, and a centered "
                    + "preview.",
                "Capture a webpage at several viewports at once — social, desktop, Full HD, "
                    + "mobile — composed into a shareable responsive board. New Web Snapshot "
                    + "and New Social Card are now in the menu-bar icon panel too.",
                "Fixed the Get Vitrine PRO purchase link after the store moved.",
            ]),
        ReleaseNote(
            version: "0.15.0",
            headline: "Sharper terminal captures — emoji, CJK, exact width",
            highlights: [
                "Full-screen terminal captures now handle wide characters: CJK text and "
                    + "emoji line up correctly instead of drifting, so an htop or a 你好 / 🚀 "
                    + "dashboard reconstructs cleanly.",
                "vgrab -w <cols> now pins the exact reconstruction width, so wide output "
                    + "like git log --graph wraps just as it did in your terminal.",
                "In-place line edits — shell autosuggestion and the like — reconstruct "
                    + "faithfully, with wide characters kept whole.",
            ]),
        ReleaseNote(
            version: "0.14.0",
            headline: "Capture full-screen terminal apps",
            highlights: [
                "Vitrine now turns full-screen terminal apps — htop, vim, lazygit, k9s, "
                    + "less — into images, not just scrolling output. It reconstructs the "
                    + "program's final screen, colors and all, in your theme.",
                "It's automatic: vgrab htop captures the dashboard, while a plain git log "
                    + "or test run still renders as the full scrolling transcript.",
            ]),
        ReleaseNote(
            version: "0.13.0",
            headline: "A lighter terminal integration",
            highlights: [
                "The vitrine shell integration is now a single vgrab function — it no "
                    + "longer runs a background recorder or re-execs your shell, so it has "
                    + "no effect on your terminal's performance.",
                "To capture a command you already ran, recall it (↑ or !!) and prepend "
                    + "vgrab — for example, vgrab !!.",
            ]),
        ReleaseNote(
            version: "0.12.0",
            headline: "Terminal capture, now in any shell",
            highlights: [
                "Set up the shell helpers in one click from Settings ▸ General ▸ Shell "
                    + "integration — no more editing a dotfile by hand. Works with zsh, bash, "
                    + "and fish.",
                "vgrab and vlast now work in bash and fish, not just zsh, so the last command "
                    + "you ran is one keystroke from a beautiful image in any shell.",
                "Terminal images show Powerline separators and prompt icons from tools like "
                    + "starship and eza --icons, using a Nerd Font you already have installed.",
                "vgrab --edit, vlast --edit, and vitrine render --edit open the capture in the "
                    + "editor so you can restyle and annotate before sharing.",
                "Terminal hyperlinks render as styled links, and an optional plain-text sidecar "
                    + "keeps the words selectable right next to the image.",
            ]),
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

    /// Decides whether the version-gated "What's New" should be presented.
    ///
    /// It appears only when the newest bundled notes are strictly newer than the
    /// version the user last saw. The rules, in order:
    ///
    /// - With no bundled notes, there is nothing to show.
    /// - On a clean first run (`lastSeenVersion == nil`), it does **not** appear:
    ///   onboarding owns the first-run experience, so a brand-new user is
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
/// strings.
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

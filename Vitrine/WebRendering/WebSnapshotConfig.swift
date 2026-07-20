import CoreGraphics
import Foundation

/// The configuration and safety policy for capturing a user-provided URL through
/// local WebKit.
///
/// URL screenshots are web capture, and they must preserve Vitrine's privacy
/// promise: the requested page is loaded **locally** in a `WKWebView` on this Mac,
/// never through a remote render service. This type carries the explicit network
/// mode that makes that promise auditable — what is persisted, whether cookies are
/// allowed, and the validated URL the renderer is permitted to load — so the policy
/// is a value the tests drive directly rather than behavior buried in a web view.
///
/// ## What this owns
///
/// - **The data-store policy** (`DataStoreMode`): `WKWebsiteDataStore.nonPersistent()`
///   is the default, and cookies / persistent website data are opt-in only.
/// - **The first-use disclosure** (`firstUseDisclosure`): the plain-language copy
///   that explains Vitrine will load the requested URL locally in WebKit, shown the
///   first time a user captures a URL.
///
/// Two security-relevant collaborators live in their own reviewable files:
/// **URL validation** (`WebSnapshotConfig.validate(captureURL:)`, the SSRF host
/// blocklist, and `URLValidationError`) in `WebURLValidation.swift`, and the
/// **network-capability gate** in `NetworkCapability.swift` — both still compiled
/// into the CLI alongside this file (the validating initializer below depends on
/// `validate`, and settings surfaces read the capability gate).
///
/// ## Predictable capture policy
///
/// The configuration makes a web screenshot *predictable across sites* by carrying the layout
/// and timing policy as values the tests drive directly:
///
/// - **Viewport presets** (`ViewportPreset`): 1200×630, 1440×900, 1920×1080, a
///   mobile size, and a custom width/height, so the same URL renders to a chosen,
///   predictable pixel size.
/// - **Capture mode** (`CaptureMode`): the visible viewport, or the full page laid
///   out at the viewport width and extended to the document's content height.
/// - **Wait strategy** (`WaitStrategy`): wait for the DOM, a fixed extra delay, or a
///   best-effort network-quiet settle, so a page that loads its content
///   asynchronously has a chance to finish before the snapshot.
/// - **Safety caps** (`SafetyCaps`): a maximum captured page height and a hard
///   timeout ceiling, so a full-page capture of a runaway document cannot exhaust
///   memory or hang.
///
/// These policies keep network behavior explicit and the safety gate reviewable.
struct WebSnapshotConfig: Equatable {
    /// The validated page to capture. Always an `http`/`https` URL that passed
    /// `WebSnapshotConfig.validate(captureURL:)` — the initializer is the only way
    /// to build one, so a `WebSnapshotConfig` can never carry a rejected scheme.
    let url: URL

    /// The viewport preset the page is laid out in. The width is always honored; the
    /// height is the captured height only in `.visibleViewport` mode (in `.fullPage`
    /// mode the height grows to the document's content height, capped by
    /// `safetyCaps.maxPageHeight`). Defaults to OpenGraph's 1200×630.
    var viewportPreset: ViewportPreset = .openGraph

    /// The captured viewport size in points, derived from `viewportPreset`. The page
    /// is laid out at this width; the height is the rendered height in
    /// `.visibleViewport` mode.
    var viewport: CGSize { viewportPreset.size }

    /// Whether to capture only the visible viewport or the full scrollable page. The
    /// default is the visible viewport, which is the deterministic, social-card-sized
    /// capture; full-page is an explicit choice that extends to the content height.
    var captureMode: CaptureMode = .visibleViewport

    /// How long to wait, and on what signal, before snapshotting the page. The
    /// default is `.domContentLoaded`: snapshot as soon as the load settles. The
    /// other strategies add a bounded extra wait for pages whose content arrives
    /// asynchronously.
    var waitStrategy: WaitStrategy = .domContentLoaded

    /// The memory- and time-safety ceilings applied to every capture. Bounds the
    /// captured page height and the total wait so a runaway page cannot exhaust
    /// memory or hang the caller. Always applied; never disabled.
    var safetyCaps: SafetyCaps = .standard

    /// Output scale (1/2/3), matching `ExportManager`'s default. The rendered image
    /// is `viewport × scale` device pixels.
    var scale: CGFloat = 2

    /// Color profile to tag the output with — sRGB by default.
    var profile: ColorProfile = .sRGB

    /// What the web view is allowed to persist while loading the page. Defaults to
    /// `.nonPersistent`, so nothing the page touches is written to disk or shared
    /// with any other web view; cookies and persistent website data are opt-in only.
    var dataStoreMode: DataStoreMode = .nonPersistent

    /// The effective capture deadline: the configured `waitStrategy`'s total budget,
    /// clamped to the safety ceiling so no strategy can wait longer than
    /// `safetyCaps.maxTimeout`. The URL engine applies this as one absolute deadline
    /// across navigation, post-load settling, and full-page lazy-load waits.
    var timeout: Duration {
        SafetyCaps.clampTimeout(waitStrategy.totalBudget, to: safetyCaps.maxTimeout)
    }

    /// Builds a configuration for `captureURL`, rejecting any URL that is not a
    /// safe `http`/`https` page with a typed `URLValidationError`. This is the only
    /// initializer, so every `WebSnapshotConfig` carries a validated URL by
    /// construction.
    init(
        captureURL: URL,
        viewportPreset: ViewportPreset = .openGraph,
        captureMode: CaptureMode = .visibleViewport,
        waitStrategy: WaitStrategy = .domContentLoaded,
        safetyCaps: SafetyCaps = .standard,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB,
        dataStoreMode: DataStoreMode = .nonPersistent
    ) throws {
        self.url = try WebSnapshotConfig.validate(captureURL: captureURL)
        self.viewportPreset = viewportPreset
        self.captureMode = captureMode
        self.waitStrategy = waitStrategy
        self.safetyCaps = safetyCaps
        self.scale = scale
        self.profile = profile
        self.dataStoreMode = dataStoreMode
    }
}

// MARK: - Hermetic test hook

extension WebSnapshotConfig {
    /// Builds a configuration that loads `localFileURL` **without** the http(s)
    /// validation, for hermetic offscreen-render tests only.
    ///
    /// Production code can build a `WebSnapshotConfig` only through the validating
    /// initializer, so a shipping URL capture is always an `http`/`https` page that
    /// passed `validate(captureURL:)`. The live render path, however, must rasterize
    /// a real page without contacting the network, which means loading a local
    /// `file:` fixture — a scheme validation deliberately rejects. This hook exists
    /// solely so the engine's real `load`/`takeSnapshot` path can be exercised
    /// against a local file; it is never reached by the app or the CLI. It traps if
    /// handed anything other than a `file:` URL, so it cannot be misused to load a
    /// remote page behind validation's back.
    init(
        localFileURL: URL,
        viewportPreset: ViewportPreset = .openGraph,
        captureMode: CaptureMode = .visibleViewport,
        waitStrategy: WaitStrategy = .domContentLoaded,
        safetyCaps: SafetyCaps = .standard,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB
    ) {
        precondition(
            localFileURL.isFileURL,
            "The hermetic test hook loads only a local file URL; production capture is validated http(s)."
        )
        self.url = localFileURL
        self.viewportPreset = viewportPreset
        self.captureMode = captureMode
        self.waitStrategy = waitStrategy
        self.safetyCaps = safetyCaps
        self.scale = scale
        self.profile = profile
        self.dataStoreMode = .nonPersistent
    }
}

// MARK: - Viewport presets

extension WebSnapshotConfig {
    /// The size the page is laid out and captured in.
    ///
    /// A web screenshot is only predictable if its layout width is fixed, so the
    /// renderer never captures "whatever size the window happens to be". The presets
    /// cover the sizes that matter for sharing a page: OpenGraph's social-card size,
    /// two common desktop widths, a mobile width that triggers responsive layouts,
    /// and a custom width/height for anything else. The width is always the layout
    /// width; the height is the captured height only for a visible-viewport capture
    /// (a full-page capture extends past it to the document's content height).
    enum ViewportPreset: Equatable, Sendable {
        /// OpenGraph's 1200×630 — the default, sized for a social share card.
        case openGraph
        /// 1440×900 — a common laptop logical resolution.
        case desktop
        /// 1920×1080 — full-HD, for a wide desktop capture.
        case fullHD
        /// 390×844 — an iPhone-class width that triggers a responsive/mobile layout.
        case mobile
        /// A user-specified size. The width and height are clamped into a sane range
        /// by `init`, so a custom preset can never carry a zero, negative, or
        /// absurd dimension that would crash layout or exhaust memory.
        case custom(width: Int, height: Int)

        /// The captured size in points.
        var size: CGSize {
            switch self {
            case .openGraph: CGSize(width: 1200, height: 630)
            case .desktop: CGSize(width: 1440, height: 900)
            case .fullHD: CGSize(width: 1920, height: 1080)
            case .mobile: CGSize(width: 390, height: 844)
            case .custom(let width, let height):
                CGSize(width: width, height: height)
            }
        }

        /// A short, localized label for the preset, used in the settings picker. The
        /// names flow through the String Catalog so the picker reads in the
        /// user's language, matching the localized chrome around it.
        var displayName: String {
            switch self {
            case .openGraph: String(localized: "Social card (1200 × 630)")
            case .desktop: String(localized: "Desktop (1440 × 900)")
            case .fullHD: String(localized: "Full HD (1920 × 1080)")
            case .mobile: String(localized: "Mobile (390 × 844)")
            case .custom(let width, let height):
                String(localized: "Custom (\(width) × \(height))")
            }
        }

        /// The preset's name without its dimensions, e.g. "Desktop" — the first line of
        /// the responsive board's caption. Derived from `displayName` (split at its "Name
        /// (W × H)" shape) so the board reuses the already-localized name rather than
        /// carrying a second catalog entry; falls back to the whole name if a translation
        /// drops the parenthetical.
        var boardName: String {
            guard let paren = displayName.firstIndex(of: "(") else { return displayName }
            return String(displayName[..<paren]).trimmingCharacters(in: .whitespaces)
        }

        /// The preset's dimensions as shown on the board's caption, e.g. "1440 × 900" —
        /// the second line. Empty when `displayName` carries no parenthesized size, so the
        /// caption gracefully collapses to just the name. Trimmed (like `boardName`) so a
        /// translation that pads the parentheses can't leak stray whitespace into the label.
        var boardDimensions: String {
            guard let open = displayName.firstIndex(of: "("),
                let close = displayName.lastIndex(of: ")"), open < close
            else { return "" }
            return String(displayName[displayName.index(after: open)..<close])
                .trimmingCharacters(in: .whitespaces)
        }

        /// The non-custom presets, for listing in a picker. `.custom` is excluded
        /// because it is parameterized; the UI offers it as a separate row with
        /// width/height fields.
        static let fixedPresets: [ViewportPreset] = [.openGraph, .desktop, .fullHD, .mobile]

        /// The inclusive bounds a custom viewport dimension is clamped into. The
        /// floor keeps layout viable (a sub-100pt width is not a usable page width);
        /// the ceiling bounds a single axis so a custom size cannot, by itself, ask
        /// for a multi-gigapixel bitmap.
        static let customDimensionRange: ClosedRange<Int> = 100...5000

        /// Clamps a single custom viewport dimension into `customDimensionRange`, so
        /// a stored or typed width/height is always a usable, memory-safe value.
        static func clampCustomDimension(_ value: Int) -> Int {
            customDimensionRange.clamping(value)
        }

        /// Builds a `.custom` preset with both dimensions clamped into
        /// `customDimensionRange`, so a custom viewport is always a usable,
        /// memory-safe size regardless of the raw input.
        static func custom(clampingWidth width: Int, height: Int) -> ViewportPreset {
            .custom(
                width: clampCustomDimension(width),
                height: clampCustomDimension(height))
        }

        /// A flat, raw-value discriminant for the preset, dropping the custom size's
        /// associated values. This is what the picker tags and what `AppSettings`
        /// persists; the custom width/height are stored alongside it as separate
        /// values, so an associated-value enum round-trips through `UserDefaults`
        /// without a bespoke encoder.
        enum Kind: String, CaseIterable, Equatable, Sendable {
            case openGraph, desktop, fullHD, mobile, custom
        }

        /// The discriminant for this preset.
        var kind: Kind {
            switch self {
            case .openGraph: .openGraph
            case .desktop: .desktop
            case .fullHD: .fullHD
            case .mobile: .mobile
            case .custom: .custom
            }
        }

        /// Reconstructs a preset from a persisted `kind` plus the stored custom size.
        /// A non-custom kind ignores the size; a custom kind clamps the size into the
        /// safe range, so a hand-edited or out-of-range stored value can never produce
        /// a degenerate viewport (defensive-read posture).
        static func resolve(kind: Kind, customWidth: Int, customHeight: Int) -> ViewportPreset {
            switch kind {
            case .openGraph: .openGraph
            case .desktop: .desktop
            case .fullHD: .fullHD
            case .mobile: .mobile
            case .custom: .custom(clampingWidth: customWidth, height: customHeight)
            }
        }
    }
}

// MARK: - Capture mode

extension WebSnapshotConfig {
    /// Whether a capture is the visible viewport or the whole scrollable page.
    ///
    /// The visible viewport is the deterministic default: the page is captured at
    /// exactly the preset size, which is what a social card or a hero shot wants.
    /// Full-page capture extends the rendered height to the document's content height
    /// (bounded by `SafetyCaps.maxPageHeight`) so a long article or a docs page is
    /// captured top to bottom — useful, but explicitly opt-in because the output
    /// height then depends on the page.
    enum CaptureMode: String, CaseIterable, Equatable, Sendable {
        /// Capture exactly the preset viewport — fixed width and height.
        case visibleViewport
        /// Capture the full scrollable page: preset width, height grown to the
        /// document's content height (capped).
        case fullPage

        /// A short, localized label for the mode, used in the settings picker. Flows
        /// through the String Catalog so it reads in the user's language.
        var displayName: String {
            switch self {
            case .visibleViewport: String(localized: "Visible area")
            case .fullPage: String(localized: "Full page")
            }
        }

        /// Whether this mode captures past the viewport to the document's content
        /// height. `false` for the fixed visible viewport, `true` for full page.
        var capturesFullHeight: Bool { self == .fullPage }
    }
}

// MARK: - Wait strategy

extension WebSnapshotConfig {
    /// How long to wait, and on what signal, before snapshotting a page.
    ///
    /// A static page is ready the instant its load settles, but a page that fetches
    /// its content with JavaScript is blank at that point. The strategies trade
    /// determinism for completeness:
    ///
    /// - `.domContentLoaded` snapshots as soon as the navigation finishes — fastest
    ///   and fully deterministic, right for a static or server-rendered page.
    /// - `.fixedDelay` waits a set duration *after* the load settles, so
    ///   client-rendered content has a predictable window to appear.
    /// - `.networkQuiet` is best-effort: it waits up to a budget for network activity
    ///   to go quiet (no in-flight requests for a short idle window), then snapshots.
    ///   It is documented as best-effort because a page that polls forever never goes
    ///   quiet, so the budget — not true silence — is the guarantee.
    enum WaitStrategy: Equatable, Sendable {
        /// Snapshot as soon as the navigation settles. No extra wait.
        case domContentLoaded
        /// Wait `delay` after the load settles before snapshotting.
        case fixedDelay(Duration)
        /// Wait up to `budget` for the network to go quiet, then snapshot. Best-effort:
        /// the budget is the upper bound, reached if the page never quiesces.
        case networkQuiet(budget: Duration)

        /// The total wait budget this strategy may spend, used to derive the engine's
        /// absolute capture deadline. It is the navigation-load allowance plus any
        /// post-load wait, so the effective timeout already accounts for the chosen
        /// strategy before the safety ceiling clamps it.
        var totalBudget: Duration {
            switch self {
            case .domContentLoaded: Self.baseLoadBudget
            case .fixedDelay(let delay): Self.baseLoadBudget + delay
            case .networkQuiet(let budget): Self.baseLoadBudget + budget
            }
        }

        /// The extra wait applied *after* the navigation settles, before the snapshot.
        /// Zero for `.domContentLoaded`; the configured value otherwise. Exposed so the
        /// engine and the tests share one definition of the post-load delay.
        var postLoadDelay: Duration {
            switch self {
            case .domContentLoaded: .zero
            case .fixedDelay(let delay): delay
            case .networkQuiet(let budget): budget
            }
        }

        /// A short, localized label for the strategy, used in the settings picker.
        /// Flows through the String Catalog so it reads in the user's
        /// language, matching the localized chrome around it.
        var displayName: String {
            switch self {
            case .domContentLoaded: String(localized: "Page loaded")
            case .fixedDelay: String(localized: "Fixed delay")
            case .networkQuiet: String(localized: "Network quiet (best effort)")
            }
        }

        /// The base allowance for the navigation load itself, before any
        /// strategy-specific extra wait. Generous enough for a real remote page to
        /// finish loading, and the floor of every strategy's `totalBudget`.
        static let baseLoadBudget: Duration = .seconds(30)

        /// The default post-load wait, in seconds, the UI seeds a fixed-delay or
        /// network-quiet strategy with when the user first switches to it. A short,
        /// useful window that still leaves the total inside the hard timeout cap.
        static let defaultExtraWaitSeconds = 2

        /// A flat, raw-value discriminant for the strategy, dropping the duration's
        /// associated value. This is what the picker tags and what `AppSettings`
        /// persists; the post-load delay seconds are stored alongside it, so an
        /// associated-value enum round-trips through `UserDefaults` without a bespoke
        /// encoder.
        enum Kind: String, CaseIterable, Equatable, Sendable {
            case domContentLoaded, fixedDelay, networkQuiet
        }

        /// The discriminant for this strategy.
        var kind: Kind {
            switch self {
            case .domContentLoaded: .domContentLoaded
            case .fixedDelay: .fixedDelay
            case .networkQuiet: .networkQuiet
            }
        }

        /// Reconstructs a strategy from a persisted `kind` plus a post-load delay in
        /// seconds. `.domContentLoaded` ignores the delay; the timed strategies clamp
        /// the seconds to a non-negative value, so a corrupt stored value can never
        /// produce a negative `Duration` (defensive-read posture).
        static func resolve(kind: Kind, extraWaitSeconds: Int) -> WaitStrategy {
            let seconds = Duration.seconds(max(extraWaitSeconds, 0))
            switch kind {
            case .domContentLoaded: return .domContentLoaded
            case .fixedDelay: return .fixedDelay(seconds)
            case .networkQuiet: return .networkQuiet(budget: seconds)
            }
        }
    }
}

// MARK: - Safety caps

extension WebSnapshotConfig {
    /// The memory- and time-safety ceilings applied to every capture.
    ///
    /// These bound the two ways a hostile or pathological page could harm the app: a
    /// full-page capture of an infinitely tall document (memory) and a page that
    /// never finishes settling (time). The caps are always applied — there is no
    /// "off" — so even a custom viewport and a generous wait strategy cannot produce a
    /// runaway bitmap or an unbounded wait.
    struct SafetyCaps: Equatable, Sendable {
        /// The maximum captured page height in points. A full-page capture taller
        /// than this is clipped to this height, so the rendered bitmap's pixel count
        /// is bounded no matter how long the document is.
        var maxPageHeight: CGFloat

        /// The hard ceiling on the load timeout. No wait strategy can wait longer than
        /// this, so a page that never settles still fails within a bounded time.
        var maxTimeout: Duration

        /// The standard caps Vitrine ships: a tall-but-bounded page height and a
        /// one-minute hard timeout. Chosen so an ordinary long article captures fully
        /// while a pathological page is still bounded.
        static let standard = SafetyCaps(
            maxPageHeight: 20_000, maxTimeout: .seconds(60))

        /// Clamps a requested full-page `contentHeight` to `maxPageHeight`, so the
        /// captured height never exceeds the cap. A non-positive height falls back to
        /// the cap-bounded minimum of the viewport so the result is always drawable.
        func clampPageHeight(_ contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
            let lowerBound = max(viewportHeight, 1)
            let requested = max(contentHeight, lowerBound)
            return min(requested, maxPageHeight)
        }

        /// Clamps `requested` to `ceiling`, so the effective timeout never exceeds the
        /// hard cap. Pure arithmetic on `Duration` so the timeout cap is unit-testable
        /// without a web view.
        static func clampTimeout(_ requested: Duration, to ceiling: Duration) -> Duration {
            min(requested, ceiling)
        }
    }
}

extension ClosedRange where Bound: Comparable {
    /// Clamps `value` into the range: the lower bound below it, the upper bound above
    /// it, otherwise the value itself. Small local helper so the custom-viewport and
    /// page-height clamps read as a single call.
    fileprivate func clamping(_ value: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

// MARK: - Data-store mode

extension WebSnapshotConfig {
    /// What the offscreen web view is permitted to persist for a URL capture.
    ///
    /// The privacy default is `.nonPersistent`: the web view uses
    /// `WKWebsiteDataStore.nonPersistent()`, so cookies, caches, and local storage
    /// live only for the single render and are never written to disk or shared with
    /// any other web view. `.persistent` is an explicit opt-in for the rare case a
    /// user needs a logged-in page; it is never the default, which is what keeps the
    /// "cookies and persistent website data are opt-in only" contract true.
    enum DataStoreMode: String, CaseIterable, Equatable, Sendable {
        /// The default: nothing the page touches is persisted (a per-render data
        /// store). Cookies are not sent or stored across renders.
        case nonPersistent

        /// Opt-in only: the default persistent data store is used, so existing
        /// cookies and website data are available to the page and updates persist.
        /// A user chooses this deliberately; it is never reached by default.
        case persistent

        /// Whether this mode persists cookies and website data to disk. `false` for
        /// the default per-render store, `true` only for the explicit opt-in.
        var persistsWebsiteData: Bool { self == .persistent }

        /// Whether cookies are available to the page. Cookies ride the persistent
        /// store, so they are available only in the explicit opt-in mode — the
        /// "cookies are opt-in only" guarantee expressed as a single accessor.
        var allowsCookies: Bool { self == .persistent }
    }
}

// MARK: - First-use disclosure

extension WebSnapshotConfig {
    /// The plain-language explanation shown the first time a user captures a URL,
    /// so the privacy posture is understood before any page loads.
    ///
    /// The copy makes the one fact that matters explicit: Vitrine loads the
    /// requested webpage **locally in WebKit on this Mac**, and the screenshot is
    /// produced on-device — there is no remote render service.  owns the full
    /// disclosure view; this is the reviewable, localizable source of its words so
    /// the copy is asserted in tests and reused wherever the disclosure appears.
    struct FirstUseDisclosure: Equatable {
        /// The disclosure title.
        let title: String
        /// The body paragraph explaining local WebKit loading.
        let message: String
        /// The label of the button that proceeds with the capture.
        let confirmTitle: String
        /// The label of the button that cancels without loading anything.
        let cancelTitle: String
    }

    /// The first-use disclosure copy. Built from the String Catalog so it localizes
    /// and reads cleanly in every UI that presents it.
    static var firstUseDisclosure: FirstUseDisclosure {
        FirstUseDisclosure(
            title: String(localized: "Capture a webpage?"),
            message: String(
                localized:
                    "Vitrine will load this webpage locally in WebKit on your Mac and turn it into an image. The page is rendered on-device — Vitrine never sends the URL to a remote screenshot service."
            ),
            confirmTitle: String(localized: "Load and Capture"),
            cancelTitle: String(localized: "Cancel"))
    }
}

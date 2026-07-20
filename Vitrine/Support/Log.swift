import OSLog

/// Structured logging for Vitrine.
///
/// Everything goes through Apple's unified logging system (`os.Logger`) under a
/// single subsystem — `com.johnny4young.vitrine` — split into a fixed set of categories so a
/// developer can filter the stream in Console.app or `log stream` by feature.
/// There is **no** telemetry: nothing is sent off the Mac, and the only way a log
/// excerpt ever leaves the machine is the user-initiated diagnostics export
/// (`DiagnosticsBundle`), which the user saves to a file they choose.
///
/// ## Privacy rule
///
/// Log messages must **never** contain user code, clipboard text, file contents,
/// or file paths beyond ones the user explicitly chose to share. In practice that
/// means string interpolation in a log call stays `.public` only for app-derived,
/// non-PII values (counts, durations, enum names, booleans); anything that could
/// echo user input is either omitted or measured (e.g. a character count) rather
/// than logged verbatim. `os.Logger` also redacts dynamic strings as `<private>`
/// by default, but we do not rely on that alone — we simply do not pass user
/// content in.
/// `nonisolated` so logging works from any isolation — including the `@concurrent`
/// off-main export/encode hops. Every member is a `Sendable` `Logger` (or a
/// pure factory), so there is no main-actor state to protect.
nonisolated enum Log {
    /// The single subsystem all categories share. Matches the bundle identifier so
    /// the unified-logging stream is easy to find (`log stream --subsystem com.johnny4young.vitrine`).
    static let subsystem = "com.johnny4young.vitrine"

    /// The fixed set of logging categories, one per product area.
    /// Keeping these as an enum — rather than ad-hoc category strings scattered
    /// across the codebase — guarantees the diagnostics bundle can enumerate every
    /// category it knows about and document exactly what it collects.
    enum Category: String, CaseIterable {
        case app
        case capture
        case render
        case export
        case settings
    }

    /// App lifecycle (launch, hotkey wiring, termination).
    static let app = logger(.app)
    /// Quick-capture path: clipboard → render → clipboard/file, with no user content.
    static let capture = logger(.capture)
    /// Canvas/render path. Also carries the render signposts that feed performance metrics.
    static let render = logger(.render)
    /// Image export to clipboard, file, or share sheet.
    static let export = logger(.export)
    /// Settings load, persistence, migration, and reset.
    static let settings = logger(.settings)

    /// A `Logger` for `category` under the shared subsystem.
    static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}

/// Signposting for the render path, which feeds the performance budget.
///
/// `OSSignposter` emits interval markers visible in Instruments' os_signpost track
/// and in the unified log, so render latency can be measured without a stopwatch in
/// production code. Like everything in `Log`, signpost arguments stay non-PII: we
/// name the interval and attach only derived measures (e.g. code length), never the
/// code itself.
enum RenderSignpost {
    /// The signposter bound to the render category, so its intervals line up with
    /// the `Log.render` text log.
    static let signposter = OSSignposter(logger: Log.render)

    /// The interval name shown in Instruments for a single canvas render.
    static let renderName: StaticString = "Render snapshot"
}

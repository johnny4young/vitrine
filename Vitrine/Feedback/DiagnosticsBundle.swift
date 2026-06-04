import AppKit
import OSLog
import UniformTypeIdentifiers

/// A privacy-safe diagnostics report a user can attach to a bug report (CS-048).
///
/// Vitrine ships no telemetry, so when something misbehaves in the field there is
/// otherwise no supported way to capture what happened. "Export diagnostics…"
/// gathers a small, **reproducible** snapshot — app version, OS/arch, the current
/// settings with any user code redacted, and the set of log categories the app
/// uses — into a single plain-text file the user explicitly saves and can read in
/// full before sharing.
///
/// ## What it deliberately does *not* contain
///
/// - The code being edited or anything from the clipboard.
/// - Recent-capture contents, file contents, or file paths.
/// - Any identifier that could deanonymize the user.
///
/// The type is split into a **pure builder** (`build(environment:settings:)`) and a
/// **renderer** (`text`) so the redaction and formatting can be unit-tested with
/// fixtures and asserted to never echo user code, with no file-system or AppKit
/// dependency.
struct DiagnosticsBundle: Equatable {
    /// A schema marker written into the file so the format is self-describing and a
    /// future reader can tell which layout it is looking at. Bump when the sections
    /// or their meaning change.
    static let schemaVersion = 1

    /// The product the bundle describes (always Vitrine; kept explicit so the file
    /// is unambiguous when detached from its filename).
    let product: String
    /// App marketing version, e.g. `0.1.0`.
    let appVersion: String
    /// App build number, e.g. `1`.
    let buildNumber: String
    /// Operating-system version string, e.g. `macOS 14.5.0`.
    let osVersion: String
    /// CPU architecture, e.g. `arm64` or `x86_64`.
    let architecture: String
    /// Redacted, sorted key→value lines describing the current settings. The
    /// builder guarantees no user code appears here.
    let settings: [SettingLine]
    /// The logging categories the app uses, so a reader knows what to look for in
    /// `log stream --subsystem app.vitrine`.
    let logCategories: [String]
    /// Recent log lines from the app's own subsystem. These are safe to include
    /// because every Vitrine log statement is non-PII by construction (CS-048);
    /// the reader (`OSLogReader`) further limits collection to the app subsystem.
    let logExcerpts: [LogExcerpt]

    /// One redacted setting, as a stable key/value pair.
    struct SettingLine: Equatable {
        let key: String
        let value: String
    }

    /// A single recent log line, reduced to its non-PII fields.
    struct LogExcerpt: Equatable {
        let category: String
        let level: String
        let message: String
    }

    // MARK: - Pure builder

    /// Inputs the builder reads, injected so the bundle is deterministic and
    /// testable without touching `ProcessInfo`, `Bundle`, or the real settings
    /// singleton.
    struct Environment: Equatable {
        var product: String
        var appVersion: String
        var buildNumber: String
        var osVersion: String
        var architecture: String

        /// Resolves the live runtime environment from `Bundle.main` and
        /// `ProcessInfo`. Reads only app/OS metadata — never user content.
        static func current(bundle: Bundle = .main) -> Environment {
            let info = bundle.infoDictionary ?? [:]
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return Environment(
                product: info["CFBundleName"] as? String ?? "Vitrine",
                appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
                buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
                osVersion: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                architecture: machineArchitecture()
            )
        }

        /// The hardware architecture string (`arm64`, `x86_64`, …) via `uname`.
        /// This is a CPU model, not a device identifier.
        private static func machineArchitecture() -> String {
            var info = utsname()
            guard uname(&info) == 0 else { return "unknown" }
            return withUnsafeBytes(of: &info.machine) { raw in
                let bytes = raw.prefix { $0 != 0 }
                return String(decoding: bytes, as: UTF8.self)
            }
        }
    }

    /// Builds a bundle from an environment, a settings snapshot, and (optionally)
    /// recent log excerpts. Pure: it copies only non-PII, app-derived values and
    /// never reads the code being edited. `logExcerpts` is injected — the live
    /// exporter supplies entries from `OSLogReader`; tests pass fixtures (or none)
    /// to keep the output deterministic.
    static func build(
        environment: Environment,
        settings: DiagnosticsSettingsSnapshot,
        logExcerpts: [LogExcerpt] = []
    ) -> DiagnosticsBundle {
        DiagnosticsBundle(
            product: environment.product,
            appVersion: environment.appVersion,
            buildNumber: environment.buildNumber,
            osVersion: environment.osVersion,
            architecture: environment.architecture,
            settings: settings.redactedLines(),
            logCategories: Log.Category.allCases.map(\.rawValue).sorted(),
            logExcerpts: logExcerpts
        )
    }

    // MARK: - Rendering

    /// The bundle as deterministic, human-readable plain text. Lines are stable and
    /// ordered so two runs with the same inputs produce byte-identical output, which
    /// is what the reproducibility test asserts. Generated at a fixed `date` (the
    /// only non-deterministic input) so callers control the timestamp.
    func text(generatedAt date: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("# \(product) diagnostics")
        lines.append("schema: \(Self.schemaVersion)")
        lines.append("generated: \(Self.timestamp(date))")
        lines.append("")
        lines.append("## Environment")
        lines.append("app version: \(appVersion) (\(buildNumber))")
        lines.append("os: \(osVersion)")
        lines.append("architecture: \(architecture)")
        lines.append("")
        lines.append("## Settings (user code redacted)")
        for line in settings {
            lines.append("\(line.key): \(line.value)")
        }
        lines.append("")
        lines.append("## Log categories")
        lines.append("subsystem: \(Log.subsystem)")
        for category in logCategories {
            lines.append("- \(category)")
        }
        lines.append("")
        lines.append("## Recent log (this session, non-PII)")
        if logExcerpts.isEmpty {
            lines.append("(none captured)")
        } else {
            for excerpt in logExcerpts {
                lines.append("[\(excerpt.level)] \(excerpt.category): \(excerpt.message)")
            }
        }
        lines.append("")
        lines.append("## Privacy")
        lines.append(Self.privacyNote)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// A short, fixed statement of what the file does and does not contain, written
    /// into every bundle so it documents itself (CS-048 acceptance).
    static let privacyNote =
        "This report contains no code, clipboard text, file contents, or file paths. "
        + "It was generated locally and is only shared if you choose to send it."

    /// ISO-8601 UTC timestamp, formatted independently of the user's locale so the
    /// output is stable across machines.
    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

/// A non-PII snapshot of the settings worth including in a diagnostics bundle.
///
/// This is intentionally a flat value type rather than a reference to `AppSettings`:
/// it copies only the knobs that affect rendering/output behavior and **never** the
/// `code` field (or anything else free-form a user typed), so it is impossible for
/// user code to reach a bundle through this path. `redactedLines()` is the single
/// place the wire format is produced, which keeps the redaction guarantee in one
/// auditable spot.
struct DiagnosticsSettingsSnapshot: Equatable {
    var themeID: String
    var languageID: String
    var fontName: String
    /// Whether programming ligatures are enabled (CS-052). A plain boolean knob,
    /// never user-entered text. Defaults to off so older call sites that predate
    /// the flag construct a valid snapshot without it.
    var fontLigatures: Bool = false
    var fontSize: Double
    var padding: Double
    var cornerRadius: Double
    var showChrome: Bool
    var showShadow: Bool
    var backgroundKind: String
    var autoCopy: Bool
    var alsoSaveToFile: Bool
    var exportScale: Int
    var exportFormat: String
    var colorProfile: String
    var hotkeyAction: String
    var treatURLsAsScreenshot: Bool
    var recentLanguageCount: Int
    var schemaVersion: Int

    /// Sorted, redacted key/value lines. Every value here is an enum name, a number,
    /// or a boolean — none of it is user-entered free text.
    func redactedLines() -> [DiagnosticsBundle.SettingLine] {
        let pairs: [(String, String)] = [
            ("theme", themeID),
            ("language", languageID),
            ("font", fontName),
            ("fontLigatures", String(fontLigatures)),
            ("fontSize", String(format: "%.0f", fontSize)),
            ("padding", String(format: "%.0f", padding)),
            ("cornerRadius", String(format: "%.0f", cornerRadius)),
            ("showChrome", String(showChrome)),
            ("showShadow", String(showShadow)),
            ("background", backgroundKind),
            ("autoCopy", String(autoCopy)),
            ("alsoSaveToFile", String(alsoSaveToFile)),
            ("exportScale", String(exportScale)),
            ("exportFormat", exportFormat),
            ("colorProfile", colorProfile),
            ("hotkeyAction", hotkeyAction),
            ("treatURLsAsScreenshot", String(treatURLsAsScreenshot)),
            ("recentLanguageCount", String(recentLanguageCount)),
            ("settingsSchemaVersion", String(schemaVersion)),
        ]
        return
            pairs
            .sorted { $0.0 < $1.0 }
            .map { DiagnosticsBundle.SettingLine(key: $0.0, value: $0.1) }
    }
}

/// The user-initiated "Export diagnostics…" action (CS-048).
///
/// This is the *only* path by which any diagnostic information leaves the app, and
/// it is entirely user-driven: it builds a `DiagnosticsBundle`, presents an
/// `NSSavePanel`, and writes the text to the single file the user selects. It never
/// sends anything anywhere, opens no network connection, and uses only the existing
/// user-selected file-access entitlement (no new entitlement is required).
enum DiagnosticsExporter {
    /// Builds the bundle for the current runtime + settings. Kept separate from the
    /// save panel so callers (and tests) can obtain the exact text that would be
    /// written.
    static func currentBundle(settings: AppSettings = .shared) -> DiagnosticsBundle {
        DiagnosticsBundle.build(
            environment: .current(),
            settings: settings.diagnosticsSnapshot,
            logExcerpts: OSLogReader.recentExcerpts()
        )
    }

    /// Presents a save panel and writes the diagnostics text to the chosen file.
    /// No-op if the user cancels. Returns the URL written, or `nil` on cancel/failure.
    @discardableResult
    static func exportWithSavePanel(settings: AppSettings = .shared) -> URL? {
        let bundle = currentBundle(settings: settings)
        let text = bundle.text()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "vitrine-diagnostics.txt"
        // An explicit title and field label give the panel clear context and a
        // VoiceOver-announced purpose, rather than relying on the body message
        // alone with the system's generic default title.
        panel.title = "Export Diagnostics"
        panel.nameFieldLabel = "Save as:"
        panel.message =
            "Diagnostics are saved only to the file you choose. Nothing is sent anywhere."
        panel.prompt = "Save"

        Log.export.info("Presenting diagnostics export save panel")
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("Diagnostics export cancelled")
            return nil
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            Log.export.notice("Wrote diagnostics bundle (\(text.count, privacy: .public) bytes)")
            return url
        } catch {
            // Log only the error domain/code, never `localizedDescription`, which
            // can contain the user-chosen path (CS-048 privacy rule).
            let nsError = error as NSError
            Log.export.error(
                "Failed to write diagnostics bundle (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return nil
        }
    }
}

/// Reads recent entries from the unified log for *this process only* (CS-048).
///
/// `OSLogStore(scope: .currentProcessIdentifier)` is the sandbox-safe scope: it
/// returns the running app's own log entries without any new entitlement and
/// without exposing other processes' logs. We further restrict to Vitrine's
/// subsystem and copy only the composed message and a few non-PII fields. Because
/// every Vitrine log statement is non-PII by construction, the result is safe to
/// embed in a user-shared bundle.
enum OSLogReader {
    /// The number of most-recent app log entries to include. Bounded so the bundle
    /// stays small and readable.
    static let maxEntries = 200

    /// Recent log excerpts from this process's Vitrine subsystem, oldest→newest.
    /// Returns an empty array if the store is unavailable — the bundle then simply
    /// notes that none were captured rather than failing.
    static func recentExcerpts() -> [DiagnosticsBundle.LogExcerpt] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        // Scan a bounded recent window rather than the whole store.
        let since = store.position(date: Date().addingTimeInterval(-3600))
        let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
        guard
            let entries = try? store.getEntries(
                at: since, matching: predicate)
        else { return [] }

        let excerpts =
            entries
            .compactMap { $0 as? OSLogEntryLog }
            .map {
                DiagnosticsBundle.LogExcerpt(
                    category: $0.category,
                    level: levelName($0.level),
                    message: $0.composedMessage
                )
            }
        return Array(excerpts.suffix(maxEntries))
    }

    /// A short, stable name for an `OSLogEntryLog.Level`.
    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        case .undefined: "undefined"
        @unknown default: "unknown"
        }
    }
}

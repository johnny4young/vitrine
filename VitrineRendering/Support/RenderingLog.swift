import OSLog

/// Rendering-owned unified logging. The category names intentionally match the app's
/// diagnostics catalog while keeping the reusable module independent of app lifecycle.
nonisolated enum RenderingLog {
    private static let subsystem = "com.johnny4young.vitrine"

    /// Quick-capture and file-input path. Matches the app catalog's `capture`
    /// category so a moved file keeps landing in the same stream and the
    /// diagnostics bundle keeps collecting it.
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let render = Logger(subsystem: subsystem, category: "render")
    static let export = Logger(subsystem: subsystem, category: "export")
}

public enum RenderSignpost {
    public static let signposter = OSSignposter(logger: RenderingLog.render)
    public static let renderName: StaticString = "Render snapshot"
}

import OSLog

/// Rendering-owned unified logging. The category names intentionally match the app's
/// diagnostics catalog while keeping the reusable module independent of app lifecycle.
nonisolated enum RenderingLog {
    private static let subsystem = "com.johnny4young.vitrine"

    static let render = Logger(subsystem: subsystem, category: "render")
    static let export = Logger(subsystem: subsystem, category: "export")
}

public enum RenderSignpost {
    public static let signposter = OSSignposter(logger: RenderingLog.render)
    public static let renderName: StaticString = "Render snapshot"
}

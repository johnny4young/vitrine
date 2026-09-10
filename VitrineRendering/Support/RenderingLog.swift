import OSLog
import VitrineDomain

/// Rendering-owned unified logging. The categories come from the shared `LogCategory`
/// in the value layer, so this module stays independent of app lifecycle without
/// keeping a second, drift-prone copy of the diagnostics catalog.
nonisolated enum RenderingLog {
    private static func logger(_ category: LogCategory) -> Logger {
        Logger(subsystem: LogCategory.subsystem, category: category.rawValue)
    }

    /// Quick-capture and file-input path. Built from the shared `LogCategory` rather
    /// than a matching string literal, so renaming or removing a case is a compile
    /// error here instead of silently emitting to a category the diagnostics bundle
    /// no longer collects.
    static let capture = logger(.capture)
    static let render = logger(.render)
    static let export = logger(.export)
}

public enum RenderSignpost {
    public static let signposter = OSSignposter(logger: RenderingLog.render)
    public static let renderName: StaticString = "Render snapshot"
}

import OSLog
import VitrineDomain

/// Process-local CLI loggers share the diagnostics catalog, not app lifecycle code.
/// Never interpolate user content, token bytes, or paths into these messages.
nonisolated enum Log {
    static let app = Logger(subsystem: LogCategory.subsystem, category: LogCategory.app.rawValue)
    static let export = Logger(
        subsystem: LogCategory.subsystem, category: LogCategory.export.rawValue)
}

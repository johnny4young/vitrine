import AppKit
import OSLog
import UniformTypeIdentifiers

/// The save-panel flow shared by every exchange file (presets, themes, recipes,
/// diagnostics) and image saves, with one write policy.
enum FileExchangePanel {
    /// The localized wording of one save panel.
    struct Copy {
        var title: String
        var message: String
        var prompt: String
        var nameFieldLabel = String(localized: "Save as:")
    }

    enum SaveOutcome: Equatable {
        case saved(URL)
        case cancelled
        case failed
    }

    /// Presents a save panel and writes `data` to the chosen file. Paths and error
    /// descriptions are never logged; only the label and the error domain/code are.
    static func save(
        _ data: Data, contentType: UTType, suggestedFilename: String, copy: Copy,
        logLabel: String
    ) -> SaveOutcome {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = suggestedFilename
        // Modern macOS largely ignores `title`, so the orienting wording lives in
        // `message`, which always shows.
        panel.title = copy.title
        panel.nameFieldLabel = copy.nameFieldLabel
        panel.message = copy.message
        panel.prompt = copy.prompt
        guard panel.runModal() == .OK, let url = panel.url else {
            Log.export.info("\(logLabel, privacy: .public) save cancelled")
            return .cancelled
        }
        do {
            try write(data, to: url)
            Log.export.notice(
                "Wrote \(logLabel, privacy: .public) (\(data.count, privacy: .public) bytes)")
            return .saved(url)
        } catch {
            let nsError = error as NSError
            Log.export.error(
                "Failed to write \(logLabel, privacy: .public) (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return .failed
        }
    }

    /// Writes atomically so a failed write never leaves a truncated file. The sandbox
    /// grants the chosen file, not its folder; where the volume refuses the sibling
    /// temporary file, the write falls back to replacing the file in place.
    static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch let error as CocoaError
            where error.code == .fileWriteNoPermission
        {
            Log.export.info("Atomic write refused; writing the chosen file in place")
            try data.write(to: url)
        }
    }
}

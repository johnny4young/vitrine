import AppKit

/// Routes batch exports through app-owned directory presentation without coupling
/// SwiftUI sheets to AppKit window lifecycles.
struct BatchExportPresentation {
    private let selectDirectory: (String) -> URL?
    private let revealDirectory: (URL) -> Void

    init(
        selectDirectory: @escaping (String) -> URL?,
        revealDirectory: @escaping (URL) -> Void
    ) {
        self.selectDirectory = selectDirectory
        self.revealDirectory = revealDirectory
    }

    func chooseDirectory(message: String) -> URL? {
        selectDirectory(message)
    }

    func reveal(_ directory: URL) {
        revealDirectory(directory)
    }

    static let live = BatchExportPresentation(
        selectDirectory: { message in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = String(localized: "Export")
            panel.message = message
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        },
        revealDirectory: { directory in
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        })

    static let noOp = BatchExportPresentation(
        selectDirectory: { _ in nil },
        revealDirectory: { _ in })
}

/// Interprets a batch writer's counters without trusting a zero failure count alone.
/// A sheet finishes only when every expected output was reported as written.
struct BatchExportCompletion: Equatable {
    let isComplete: Bool
    let failureNote: String?

    init(
        written: Int, failed: Int, expected: Int,
        renderFailure: RenderBudgetError? = nil
    ) {
        isComplete = expected > 0 && written == expected && failed == 0
        failureNote =
            if isComplete {
                nil
            } else if let renderFailure {
                "\(written)/\(expected) — \(Notifier.renderFailure(renderFailure).message)"
            } else {
                "\(written)/\(expected) — "
                    + String(
                        localized:
                            "Some images couldn't be written. Check the folder and try again.")
            }
    }
}

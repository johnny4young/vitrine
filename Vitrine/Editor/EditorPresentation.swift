import AppKit
import VitrineDomain
import VitrineRendering

/// Routes editor actions to app-owned presentation surfaces without exposing their
/// lifecycles to the SwiftUI editor or command responder.
struct EditorPresentation {
    private let presentPin: (NSImage) -> Void
    private let presentShare: (NSImage, NSView) -> Void
    private let resolvePreflight: ExportPreflightPrompt.Resolver
    let batchExport: BatchExportPresentation

    init(
        presentPin: @escaping (NSImage) -> Void,
        presentShare: @escaping (NSImage, NSView) -> Void,
        batchExport: BatchExportPresentation,
        resolvePreflight: @escaping ExportPreflightPrompt.Resolver = { _, _ in .proceed }
    ) {
        self.presentPin = presentPin
        self.presentShare = presentShare
        self.batchExport = batchExport
        self.resolvePreflight = resolvePreflight
    }

    func pin(_ image: NSImage) {
        presentPin(image)
    }

    func share(_ image: NSImage, relativeTo view: NSView?) {
        guard let view else { return }
        presentShare(image, view)
    }

    /// Whether `action` may run on `settings`' document. A clean document never sees a
    /// dialog, and only an explicit choice can add redactions to the export.
    func clearsPreflight(
        of settings: AppSettings, for action: ExportPreflight.Action,
        delivering payload: ExportPreflight.Payload
    ) -> Bool {
        while true {
            let report = ExportPreflight(settings.config, payload: payload)
            guard !report.isClean else { return true }
            let acknowledgement = report.acknowledgement(for: action)
            guard !settings.acknowledgedPreflights.contains(acknowledgement) else { return true }
            let choice = resolvePreflight(report, action)
            if choice == .cancel { return false }
            // A format finishing behind the dialog can move rows, and the answer only covers
            // what was shown, so a changed document is asked about again.
            let current = ExportPreflight(settings.config, payload: payload)
            guard current.acknowledgement(for: action) == acknowledgement else { continue }
            if choice == .redact {
                settings.style.redactedLineRanges = report.redactions(
                    adding: settings.style.redactedLineRanges)
            } else {
                settings.acknowledgedPreflights.insert(acknowledgement)
            }
            return true
        }
    }

    /// A file or pasteboard item with text riders exposes more than its pixels.
    static func copyPayload(of settings: AppSettings) -> ExportPreflight.Payload {
        settings.export.richClipboard || settings.export.textSidecar ? .text : .image
    }

    /// A PDF keeps its text selectable and an embedded project carries a share link;
    /// otherwise bitmap formats hold pixels only.
    static func savePayload(of settings: AppSettings) -> ExportPreflight.Payload {
        if settings.export.format == .pdf { return .text }
        return EditorImageSave.embeddingPlan(settings).link == nil ? .image : .transcript
    }

    static let live = EditorPresentation(
        presentPin: { PinnedSnapshotController.shared.pin($0) },
        presentShare: { image, view in
            ShareManager.share(
                image, relativeTo: view,
                concealed: AppEnvironment.shared.appSettings.outputBehavior.concealClipboard)
        },
        batchExport: .live,
        resolvePreflight: { ExportPreflightPrompt.resolve($0, action: $1) })

    static let noOp = EditorPresentation(
        presentPin: { _ in },
        presentShare: { _, _ in },
        batchExport: .noOp)
}

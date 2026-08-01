import AppKit

/// Routes editor actions to app-owned presentation surfaces without exposing their
/// lifecycles to the SwiftUI editor or command responder.
struct EditorPresentation {
    private let presentPin: (NSImage) -> Void
    private let presentShare: (NSImage, NSView) -> Void
    let batchExport: BatchExportPresentation

    init(
        presentPin: @escaping (NSImage) -> Void,
        presentShare: @escaping (NSImage, NSView) -> Void,
        batchExport: BatchExportPresentation
    ) {
        self.presentPin = presentPin
        self.presentShare = presentShare
        self.batchExport = batchExport
    }

    func pin(_ image: NSImage) {
        presentPin(image)
    }

    func share(_ image: NSImage, relativeTo view: NSView?) {
        guard let view else { return }
        presentShare(image, view)
    }

    static let live = EditorPresentation(
        presentPin: { PinnedSnapshotController.shared.pin($0) },
        presentShare: { image, view in
            ShareManager.share(image, relativeTo: view)
        },
        batchExport: .live)

    static let noOp = EditorPresentation(
        presentPin: { _ in },
        presentShare: { _, _ in },
        batchExport: .noOp)
}

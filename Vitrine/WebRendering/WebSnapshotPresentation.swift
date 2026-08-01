import AppKit

/// Routes Web Snapshot actions to app-owned presentation surfaces without exposing
/// their singleton lifecycles to the SwiftUI editor.
struct WebSnapshotPresentation {
    private let presentSignIn: (URL) -> Void
    private let presentShare: (NSImage) -> Void
    let batchExport: BatchExportPresentation

    init(
        presentSignIn: @escaping (URL) -> Void,
        presentShare: @escaping (NSImage) -> Void,
        batchExport: BatchExportPresentation
    ) {
        self.presentSignIn = presentSignIn
        self.presentShare = presentShare
        self.batchExport = batchExport
    }

    func showSignIn(for url: URL) {
        presentSignIn(url)
    }

    func share(_ image: NSImage) {
        presentShare(image)
    }

    static let live = WebSnapshotPresentation(
        presentSignIn: { WebSessionWindowController.shared.show(url: $0) },
        presentShare: { image in
            guard let view = NSApp.keyWindow?.contentView else { return }
            ShareManager.share(image, relativeTo: view)
        },
        batchExport: .live)

    static let noOp = WebSnapshotPresentation(
        presentSignIn: { _ in },
        presentShare: { _ in },
        batchExport: .noOp)
}

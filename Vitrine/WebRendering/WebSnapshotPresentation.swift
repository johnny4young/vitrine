import AppKit

/// Routes Web Snapshot actions to app-owned presentation surfaces without exposing
/// their singleton lifecycles to the SwiftUI editor.
struct WebSnapshotPresentation {
    private let presentSignIn: (URL, Bool) -> Void
    private let presentShare: @MainActor (NSImage) -> Void
    let batchExport: BatchExportPresentation

    init(
        presentSignIn: @escaping (URL, Bool) -> Void,
        presentShare: @escaping @MainActor (NSImage) -> Void,
        batchExport: BatchExportPresentation
    ) {
        self.presentSignIn = presentSignIn
        self.presentShare = presentShare
        self.batchExport = batchExport
    }

    func showSignIn(for url: URL, allowsLoopback: Bool) {
        presentSignIn(url, allowsLoopback)
    }

    func share(_ image: NSImage) {
        presentShare(image)
    }

    /// Keep the live window lookup and share action injectable so the no-window
    /// path and the selected anchor can be checked without opening a share sheet.
    static func makeLive(
        requestSignIn: @escaping (URL, Bool) -> Void = WebSessionWindowController.requestSignIn,
        keyWindow: @escaping () -> NSWindow? = { NSApp.keyWindow },
        share: @escaping @MainActor (NSImage, NSView) -> Void = ShareManager.share
    ) -> WebSnapshotPresentation {
        WebSnapshotPresentation(
            presentSignIn: requestSignIn,
            presentShare: { image in
                guard let view = keyWindow()?.contentView else { return }
                share(image, view)
            },
            batchExport: .live)
    }

    static let live = makeLive()

    static let noOp = WebSnapshotPresentation(
        presentSignIn: { _, _ in },
        presentShare: { _ in },
        batchExport: .noOp)
}

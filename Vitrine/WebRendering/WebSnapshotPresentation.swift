import AppKit

/// Routes Web Snapshot actions to app-owned presentation surfaces without exposing
/// their singleton lifecycles to the SwiftUI editor.
struct WebSnapshotPresentation {
    private let presentSignIn: (URL, Bool) -> Void
    private let presentShare: (NSImage) -> Void
    let batchExport: BatchExportPresentation

    init(
        presentSignIn: @escaping (URL, Bool) -> Void,
        presentShare: @escaping (NSImage) -> Void,
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

    static let live = WebSnapshotPresentation(
        presentSignIn: { url, allowsLoopback in
            Task { @MainActor in
                do {
                    try await WebSessionWindowController.shared.show(
                        url: url, allowsLoopback: allowsLoopback)
                } catch {
                    // The window is deliberately not opened without network isolation.
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Could Not Open Sign-In Window")
                    alert.informativeText = String(
                        localized:
                            "Vitrine could not establish safe web access. Try again later.")
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        },
        presentShare: { image in
            guard let view = NSApp.keyWindow?.contentView else { return }
            ShareManager.share(image, relativeTo: view)
        },
        batchExport: .live)

    static let noOp = WebSnapshotPresentation(
        presentSignIn: { _, _ in },
        presentShare: { _ in },
        batchExport: .noOp)
}

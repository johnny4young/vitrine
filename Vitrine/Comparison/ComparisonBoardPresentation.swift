import AppKit

/// Routes comparison-board sharing through the app-owned presentation surface.
struct ComparisonBoardPresentation {
    private let presentShare: (NSImage) -> Void

    init(presentShare: @escaping (NSImage) -> Void) {
        self.presentShare = presentShare
    }

    func share(_ image: NSImage) {
        presentShare(image)
    }

    static let live = ComparisonBoardPresentation { image in
        guard let view = NSApp.keyWindow?.contentView else { return }
        ShareManager.share(image, relativeTo: view)
    }

    static let noOp = ComparisonBoardPresentation(presentShare: { _ in })
}

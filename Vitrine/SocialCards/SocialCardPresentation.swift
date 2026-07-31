import AppKit

/// Routes Social Card actions to app-owned presentation surfaces without exposing
/// their singleton lifecycles to the SwiftUI editor or renderer.
struct SocialCardPresentation {
    private let presentShare: (NSImage) -> Void

    init(presentShare: @escaping (NSImage) -> Void) {
        self.presentShare = presentShare
    }

    func share(_ image: NSImage) {
        presentShare(image)
    }

    static let live = SocialCardPresentation { image in
        guard let view = NSApp.keyWindow?.contentView else { return }
        ShareManager.share(image, relativeTo: view)
    }

    static let noOp = SocialCardPresentation(presentShare: { _ in })
}

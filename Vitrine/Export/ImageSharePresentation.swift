import AppKit

/// Routes an image share to the system share sheet without exposing its singleton
/// lifecycle to SwiftUI views. Shared by the Social Card and Comparison Board windows.
struct ImageSharePresentation {
    private let presentShare: (NSImage) -> Void

    init(presentShare: @escaping (NSImage) -> Void) {
        self.presentShare = presentShare
    }

    func share(_ image: NSImage) {
        presentShare(image)
    }

    /// Shares from the key window, reading the clipboard-privacy preference from
    /// `environment` and reporting compose results through `feedback`.
    static func live(environment: AppEnvironment, feedback: FeedbackDisplay) -> Self {
        ImageSharePresentation { image in
            guard let view = NSApp.keyWindow?.contentView else { return }
            ShareManager.share(
                image, relativeTo: view,
                concealed: environment.appSettings.outputBehavior.concealClipboard,
                feedback: feedback)
        }
    }

    static let noOp = ImageSharePresentation(presentShare: { _ in })
}

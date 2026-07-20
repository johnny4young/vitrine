import Foundation

extension Notification.Name {
    /// Opens the frontmost editor's command palette without coupling the caller to
    /// the editor's view state.
    static let vitrineOpenCommandPalette = Notification.Name("vitrine.openCommandPalette")

    /// Selects an annotation tool in the editor window carried as the notification
    /// object, preserving per-window editing state.
    static let vitrineSelectAnnotationTool = Notification.Name("vitrine.selectAnnotationTool")
}

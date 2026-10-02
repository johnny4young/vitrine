import Foundation

extension Notification.Name {
    /// Selects an annotation tool in the editor window carried as the notification
    /// object, preserving per-window editing state.
    static let vitrineSelectAnnotationTool = Notification.Name("vitrine.selectAnnotationTool")
}

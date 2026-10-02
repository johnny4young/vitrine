import AppKit

extension Notification.Name {
    /// Selects an annotation tool in the editor window carried as the notification
    /// object, preserving per-window editing state.
    static let vitrineSelectAnnotationTool = Notification.Name("vitrine.selectAnnotationTool")
    /// Runs a selected-mark action (`AnnotationMarkAction`) in the editor window
    /// carried as the notification object.
    static let vitrineAnnotationMarkAction = Notification.Name("vitrine.annotationMarkAction")
}

/// Selected-mark commands the Edit menu owns, so their shortcuts work while the
/// toolbar keeps them in a lazily built SwiftUI menu.
enum AnnotationMarkAction: String, CaseIterable {
    case duplicate
    case bringToFront
    case sendToBack

    var localizedTitle: String {
        switch self {
        case .duplicate: String(localized: "Duplicate")
        case .bringToFront: String(localized: "Bring to Front")
        case .sendToBack: String(localized: "Send to Back")
        }
    }

    var keyEquivalent: String {
        switch self {
        case .duplicate: "d"
        case .bringToFront: "]"
        case .sendToBack: "["
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        self == .duplicate ? [.command] : [.command, .option]
    }
}

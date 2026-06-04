import AppKit

/// Presents the macOS Share Sheet for a rendered image (CS-008).
enum ShareManager {
    /// Shows the sharing picker anchored to `view`.
    static func share(_ image: NSImage, relativeTo view: NSView) {
        let picker = NSSharingServicePicker(items: [image])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}

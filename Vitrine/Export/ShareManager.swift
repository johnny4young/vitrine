import AppKit

/// Presents the macOS Share Sheet for a rendered image (CS-008).
///
/// `NSSharingServicePicker` shows its popover **asynchronously** and must outlive the
/// `show(...)` call — a transient local would be released the instant `share(_:)`
/// returns, dropping the picker (or its completion) under ARC. So a small retained
/// presenter holds the picker until the popover closes, then releases it. At most one
/// picker is retained at a time (a new share replaces the previous one).
@MainActor
final class ShareManager: NSObject, NSSharingServicePickerDelegate {
    /// Retains the live picker across its async popover; cleared when it dismisses.
    private static var active: ShareManager?

    private let picker: NSSharingServicePicker

    private init(image: NSImage) {
        self.picker = NSSharingServicePicker(items: [image])
        super.init()
        self.picker.delegate = self
    }

    /// Shows the sharing picker anchored to `view`, retaining it until dismissed.
    static func share(_ image: NSImage, relativeTo view: NSView) {
        let presenter = ShareManager(image: image)
        active = presenter  // keep it alive across the async popover
        presenter.picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    /// AppKit calls this when the user picks a service or dismisses the popover; either
    /// way the picker's job is done, so release the retained presenter.
    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
    ) {
        Self.active = nil
    }
}

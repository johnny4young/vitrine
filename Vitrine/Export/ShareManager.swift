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

    /// Adds the Post-to compose targets (feature #25) ahead of the system services.
    /// Each one stages the image on the clipboard and opens the network's web compose
    /// page with a paste hint — the web intents can't attach an image, so this is the
    /// closest honest flow: one paste away from posting, nothing sent by Vitrine.
    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        guard let image = items.first as? NSImage else { return proposedServices }
        let composeServices = SocialComposer.Network.allCases.compactMap { network in
            makeComposeService(for: network, image: image)
        }
        return composeServices + proposedServices
    }

    /// One compose target as a custom `NSSharingService`: pasteboard-stage the PNG,
    /// open the compose URL, confirm via the HUD.
    private func makeComposeService(
        for network: SocialComposer.Network, image: NSImage
    ) -> NSSharingService? {
        guard let url = SocialComposer.composeURL(for: network, text: "") else { return nil }
        return NSSharingService(
            title: network.title, image: NSImage(named: NSImage.shareTemplateName) ?? NSImage(),
            alternateImage: nil
        ) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            // Only open the compose page when the image actually reached the
            // pasteboard — with nothing to paste, opening the browser and claiming
            // success would just mislead (PR review).
            guard pasteboard.writeObjects([image]) else {
                ExportFeedback.presentCopy(false)
                return
            }
            NSWorkspace.shared.open(url)
            CaptureHUDController.shared.present(
                Notifier.confirmation(
                    String(localized: "Image copied — paste it into your post")))
        }
    }
}

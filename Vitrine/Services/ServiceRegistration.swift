import AppKit

/// Registers Vitrine's Services menu provider with AppKit at launch (CS-034).
///
/// Two things make a Services action work, and both must agree:
///
/// 1. The `NSServices` array in Info.plist declares the menu item, the provider
///    selector (`NSMessage` = `renderCodeImage`), and the send/return pasteboard
///    types. This is what populates the system-wide Services menu.
/// 2. At runtime the app must set `NSApp.servicesProvider` to the object whose
///    `renderCodeImage:userData:error:` selector handles the request, and advertise
///    the send/return types so the menu item enables for a text selection and offers
///    to return an image.
///
/// `register()` performs step 2; `AppDelegate` calls it once at launch. Keeping it
/// here keeps `AppDelegate` thin and makes the registration unit-coverable by reading
/// the same declared types the Info.plist promises.
enum ServiceRegistration {
    /// The pasteboard types the service accepts as input — plain text in its modern
    /// UTI form. A host app that vends a string selection to Services satisfies this.
    static let sendTypes: [NSPasteboard.PasteboardType] = [.string]

    /// The pasteboard types the service can return — a rendered PNG image, so the
    /// host app can paste or drop the result.
    static let returnTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    /// Installs the provider and advertises the send/return types so the Services
    /// menu item appears and enables for a text selection.
    @MainActor
    static func register(provider: CodeImageService = .shared) {
        NSApp.servicesProvider = provider
        NSApp.registerServicesMenuSendTypes(sendTypes, returnTypes: returnTypes)
        // Refresh the system Services cache so the freshly registered action is
        // discoverable without a relaunch in development; harmless in production.
        NSUpdateDynamicServices()
    }
}

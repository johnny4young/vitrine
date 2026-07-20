import AppKit

/// The standard macOS "About Vitrine" panel, branded with the app's tagline.
///
/// The system panel supplies the app icon, name, and version, and shows the
/// `NSHumanReadableCopyright` from `Info.plist` on its own. The branded credits add
/// **only** the tagline — adding the copyright/license line here too would print it
/// twice (the bug this type fixes). Both entry points — the App-menu "About Vitrine"
/// command and the menu-bar panel's About row — present through here so the surface is
/// identical from either path.
@MainActor
enum AboutPanel {
    /// Activates the app and shows the standard About panel with the branded credits.
    static func present() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// The branded credits: the localized tagline only. The copyright/license line is
    /// supplied by `Info.plist`'s `NSHumanReadableCopyright`, so it must not appear here.
    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor(Brand.Palette.textSecondary.color),
            .paragraphStyle: paragraph,
        ]
        let tagline = String(localized: "Turn code into beautiful images, from your menu bar.")
        return NSAttributedString(string: tagline, attributes: attributes)
    }
}

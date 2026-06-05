import CoreText
import Foundation
import OSLog

/// Registers the app's bundled monospaced fonts with Core Text at runtime so a
/// command-line render can use them (CS-033).
///
/// The GUI registers these families through `ATSApplicationFontsPath` in its
/// `Info.plist`, but a command-line tool has no app bundle and so gets no automatic
/// registration. Without this, `NSFont(name: "JetBrains Mono", …)` would fall back to
/// the system monospaced font and a default CLI render would *not* match the app. The
/// executable calls `registerBundledFonts(in:)` at startup, pointing at the `Fonts`
/// resource directory copied next to the binary, so the default and every bundled
/// font resolve to the exact same glyphs the GUI uses — keeping CLI output
/// pixel-identical (CS-033 acceptance).
///
/// Registration is process-scoped (`.process`) and best-effort: a font that is
/// already registered or a missing file is skipped without failing the render, so a
/// system-font-only request still works even if the `Fonts` directory is absent.
enum CLIFontRegistration {
    /// Registers every TrueType/OpenType font found directly inside `directory`.
    ///
    /// Returns the family file names that were registered (or were already
    /// available), mainly so a caller or test can confirm the bundled fonts were
    /// found. A `nil` directory (no bundled `Fonts` folder) registers nothing.
    @discardableResult
    static func registerBundledFonts(in directory: URL?) -> [String] {
        guard let directory,
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }

        var registered: [String] = []
        for url in entries where Self.fontExtensions.contains(url.pathExtension.lowercased()) {
            if register(url) {
                registered.append(url.lastPathComponent)
            }
        }
        Log.app.info(
            "CLI registered \(registered.count, privacy: .public) bundled fonts")
        return registered
    }

    /// The file extensions treated as registrable fonts.
    private static let fontExtensions: Set<String> = ["ttf", "otf"]

    /// Registers a single font file for the current process. Treats an
    /// already-registered font as success (so re-running in one process is a no-op)
    /// and any other failure as a skip.
    private static func register(_ url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if ok { return true }

        // A font already registered in this process is not a real failure.
        if let cfError = error?.takeRetainedValue() {
            let code = CFErrorGetCode(cfError)
            if code == CTFontManagerError.alreadyRegistered.rawValue {
                return true
            }
        }
        return false
    }
}

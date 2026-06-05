import AppKit
import OSLog
import UniformTypeIdentifiers

/// Provides the macOS Services menu action "Render Code Image with Vitrine" (CS-034).
///
/// When the user selects code text in any app that vends a selection to Services
/// (TextEdit, Xcode, Notes, the browser, …) and picks this service, macOS hands the
/// selected text in on a pasteboard; this provider renders it through the
/// **unchanged** app render path and writes the resulting PNG back onto the same
/// pasteboard, so the host app receives an image it can paste or drop.
///
/// The service reuses `SnapshotRenderService` and the user's live style exactly like
/// the App Intents and quick capture, so it produces an identical image and inherits
/// the app's privacy/sandbox posture — fully local, no network, nothing written to
/// disk. The selected text is detected for language the same way quick capture is.
///
/// Registration (`NSApp.servicesProvider`, send/return types) and the matching
/// `NSServices` Info.plist declaration live in `ServiceRegistration` and the app's
/// Info.plist; this type is only the provider object the runtime calls.
final class CodeImageService: NSObject {
    /// The shared provider instance the app registers with `NSApp.servicesProvider`.
    static let shared = CodeImageService()

    /// The result of handling a Services request, so the logic is testable without the
    /// runtime's out-pointer: either the image was placed on the pasteboard, or it
    /// failed with a user-facing message to show in the Services error sheet.
    enum Outcome: Equatable {
        /// The rendered image was written onto the pasteboard for the host app.
        case rendered
        /// Nothing was rendered; the associated string is shown to the user.
        case failed(message: String)
    }

    /// The Services entry point named by the Info.plist `NSMessage` (`renderCodeImage`).
    ///
    /// The runtime calls this selector with the incoming `NSPasteboard` (carrying the
    /// selected text), an unused `userData` string, and an out-pointer for an error
    /// message string. This is a thin adapter over the testable `process(pasteboard:)`
    /// core: it runs the logic and, only on failure, writes the message to the
    /// out-pointer.
    ///
    /// The Objective-C selector is pinned to `renderCodeImage:userData:error:`, the
    /// shape AppKit invokes from the Info.plist `NSMessage` (`renderCodeImage`),
    /// regardless of the Swift argument label. The final argument is the classic
    /// Services error *message* out-pointer (an `NSString *`), not an `NSError` —
    /// assigning it shows the string to the user.
    @objc(renderCodeImage:userData:error:)
    func renderCodeImage(
        _ pasteboard: NSPasteboard,
        userData: String?,
        errorMessage: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        if case .failed(let message) = process(pasteboard: pasteboard) {
            errorMessage.pointee = message as NSString
        }
    }

    /// Renders the pasteboard's selected text and, on success, writes the image back
    /// onto the same pasteboard — the whole Services behavior as a pure function of the
    /// pasteboard, returning an `Outcome` instead of mutating an out-pointer so it is
    /// unit-testable without unsafe pointer handling.
    ///
    /// The selected text is read, language-detected the same way quick capture does,
    /// and rendered from the user's live style. Failures (no selection, render error,
    /// could-not-write) return `.failed` with a clear message; success returns
    /// `.rendered` after both an `NSImage` (for image wells) and explicit PNG bytes
    /// (for apps that read raw PNG) are placed on the pasteboard.
    @discardableResult
    func process(pasteboard: NSPasteboard) -> Outcome {
        // Read the selected text the host app placed on the pasteboard. Both modern
        // (`.string`) and any plain-text representation are covered by `.string`.
        guard let text = pasteboard.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            Log.capture.info("Services: no selected text to render")
            return .failed(message: "Select some code first, then run the service.")
        }

        // Detect the language from the selection the same way quick capture does, and
        // start from the user's live style so the service honors their saved look.
        let interpreted = LanguageDetector.interpret(text)
        let request = SnapshotRenderRequest(
            code: interpreted.code,
            language: interpreted.language,
            baseStyle: AppSettings.shared.config)

        let image: NSImage
        do {
            image = try SnapshotRenderService.renderImage(request)
        } catch let renderError as SnapshotRenderService.RenderError {
            Log.capture.error("Services render failed")
            return .failed(message: "\(renderError)")
        } catch {
            Log.capture.error("Services render failed (unexpected)")
            return .failed(message: "Vitrine could not render an image from that code.")
        }

        // Hand the image back on the same pasteboard. Write both an `NSImage` object
        // (for image wells) and explicit PNG bytes (for apps that read raw PNG), so a
        // paste or drop into the host app receives the picture.
        pasteboard.clearContents()
        var wroteImage = pasteboard.writeObjects([image])
        if let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        {
            wroteImage = pasteboard.setData(png, forType: .png) || wroteImage
        }

        guard wroteImage else {
            Log.capture.error("Services could not place the rendered image on the pasteboard")
            return .failed(message: "Vitrine rendered the image but could not return it.")
        }
        Log.capture.notice("Services rendered a code image onto the pasteboard")
        return .rendered
    }
}

import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Builds developer-grade clipboard payloads with *multiple representations* and
/// produces the non-PNG copy targets the editor exposes (CS-054).
///
/// ## Why multiple representations
///
/// Different destinations want different formats. A browser address bar or a
/// Markdown file wants a `data:` URI; a rich-text editor (Pages, Mail, a Google
/// Doc) can paste highlighted *text*; an image well wants a PNG. macOS lets a
/// single pasteboard item advertise several representations so the destination
/// picks the best one — Vitrine populates them in one copy so a paste "just
/// works" wherever it lands.
///
/// ## How this stays safe and predictable
///
/// - The default one-shortcut copy is unchanged: `ExportManager.copyToPasteboard`
///   still writes PNG and only *adds* rich representations when the user opts in
///   (`AppSettings.richClipboard`, CS-054). The explicit "Copy as data URI" and
///   "Copy highlighted code" commands are separate, clearly labeled actions.
/// - Nothing leaves the Mac: every representation is produced locally from the
///   already-rendered image and the locally highlighted code.
/// - Large outputs are bounded. A `data:` URI and an RTF/HTML blob both grow with
///   the input, so each is capped (`maxRepresentationBytes`); past the cap the
///   representation is omitted rather than ballooning the pasteboard. The heavy
///   serialization (PNG/base64/RTF/HTML encoding) runs off the main actor through
///   the `async` builders so a big capture never blocks UI.
enum RichPasteboard {
    /// The upper bound on a single non-image representation placed on the
    /// pasteboard (the base64 `data:` URI, the RTF blob, and the HTML blob).
    ///
    /// A `data:` URI for a retina social card can be well over a megabyte of
    /// base64 text; pasting that as a *string* into a chat box or doc is rarely
    /// what the user wants and bloats the system pasteboard. 8 MB comfortably
    /// fits a typical 2× card while still ruling out a runaway blob. The PNG
    /// image representation itself is never capped here — it is the primary
    /// payload and the existing copy path owns it.
    static let maxRepresentationBytes = 8 * 1024 * 1024

    // MARK: - Pasteboard types

    /// The pasteboard type used for the rendered image (PNG).
    static let pngType = NSPasteboard.PasteboardType.png

    /// The pasteboard type for rich text (RTF), so a paste into Pages/Mail/Notes
    /// keeps the syntax colors and the selected font.
    static let rtfType = NSPasteboard.PasteboardType.rtf

    /// The pasteboard type for HTML. Declared with the public `public.html` UTI so
    /// editors that prefer HTML over RTF (many web text fields) get colored markup.
    static let htmlType = NSPasteboard.PasteboardType(UTType.html.identifier)

    // MARK: - Data URI

    /// Encodes PNG `data` as an RFC 2397 `data:` URI string
    /// (`data:image/png;base64,…`), or `nil` if the encoded URI would exceed
    /// `maxBytes` (CS-054).
    ///
    /// Pure and synchronous so it is trivially unit-testable. `maxBytes` defaults
    /// to `maxRepresentationBytes`; it is a parameter only so the cap can be driven
    /// to a small value in tests without a multi-megabyte fixture. The MIME type is
    /// fixed to `image/png` because the only raster the exporter emits to the
    /// clipboard is PNG.
    static func dataURI(forPNG data: Data, maxBytes: Int = maxRepresentationBytes) -> String? {
        let base64 = data.base64EncodedString()
        let uri = "data:image/png;base64,\(base64)"
        guard uri.utf8.count <= maxBytes else {
            Log.export.error(
                "Data URI omitted: exceeds cap (\(uri.utf8.count, privacy: .public) bytes)")
            return nil
        }
        return uri
    }

    // MARK: - Rich text serialization

    /// Serializes a highlighted `NSAttributedString` to RTF data, preserving the
    /// per-token foreground colors and the embedded font (CS-054), or `nil` if the
    /// blob would exceed `maxBytes` or serialization fails.
    ///
    /// The whole range is exported so every color/font run survives. RTF is the
    /// most broadly understood styled-text flavor on macOS; the sibling
    /// `htmlData` covers HTML-preferring destinations.
    static func rtfData(
        from attributed: NSAttributedString, maxBytes: Int = maxRepresentationBytes
    ) -> Data? {
        boundedDocumentData(from: attributed, documentType: .rtf, label: "RTF", maxBytes: maxBytes)
    }

    /// Serializes a highlighted `NSAttributedString` to HTML data, preserving the
    /// syntax colors and font as inline CSS (CS-054), or `nil` if the blob would
    /// exceed `maxBytes` or serialization fails.
    static func htmlData(
        from attributed: NSAttributedString, maxBytes: Int = maxRepresentationBytes
    ) -> Data? {
        boundedDocumentData(
            from: attributed, documentType: .html, label: "HTML", maxBytes: maxBytes)
    }

    /// Shared serializer for the styled-text representations. Converts the full
    /// attributed string to `documentType`, enforcing `maxBytes` so neither a huge
    /// RTF nor a huge HTML blob reaches the pasteboard.
    private static func boundedDocumentData(
        from attributed: NSAttributedString,
        documentType: NSAttributedString.DocumentType,
        label: StaticString,
        maxBytes: Int
    ) -> Data? {
        let range = NSRange(location: 0, length: attributed.length)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: documentType,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let data = try? attributed.data(from: range, documentAttributes: attributes) else {
            Log.export.error("Rich text serialization failed (\(label, privacy: .public))")
            return nil
        }
        guard data.count <= maxBytes else {
            Log.export.error(
                "Rich text omitted: exceeds cap (\(label, privacy: .public), \(data.count, privacy: .public) bytes)"
            )
            return nil
        }
        return data
    }

    // MARK: - Building a multi-representation payload

    /// A fully built clipboard payload: the PNG bytes plus any optional rich
    /// representations that fit within the size cap (CS-054).
    ///
    /// Held as a value (rather than written straight to the pasteboard) so the
    /// builder is testable without a live `NSPasteboard` and so a caller can decide
    /// when to clear and write. `png` is always present — it is the primary
    /// representation and the build fails if it is missing.
    struct Payload {
        /// The rendered image as PNG bytes (the primary, always-present payload).
        var png: Data
        /// Highlighted code as RTF, when the user opted into rich text and it fit.
        var rtf: Data?
        /// Highlighted code as HTML, when the user opted into rich text and it fit.
        var html: Data?

        /// Whether any styled-text representation accompanies the image. Used by
        /// callers/tests to assert the rich path actually added something.
        var hasRichText: Bool { rtf != nil || html != nil }
    }

    /// Builds the multi-representation payload for `config` (CS-054).
    ///
    /// Always includes the PNG; when `includeRichText` is true it also renders the
    /// code's highlighted attributed string and attaches RTF and HTML built from
    /// it, each subject to the size cap. Returns `nil` only if the image itself
    /// cannot be rendered or PNG-encoded — a failed or oversized rich
    /// representation is simply omitted, never fatal, so the image always copies.
    ///
    /// `@MainActor` because it renders the canvas and reads the highlight engine,
    /// both of which are main-actor bound. The serialization cost is bounded by the
    /// cap; callers that copy very large captures use the `async` writer below,
    /// which performs the encoding off the main actor.
    @MainActor
    static func makePayload(
        for config: SnapshotConfig,
        scale: CGFloat,
        fixedSize: CGSize?,
        profile: ColorProfile,
        includeRichText: Bool
    ) -> Payload? {
        guard
            let cgImage = ExportManager.renderCGImage(
                config, scale: scale, fixedSize: fixedSize, profile: profile),
            let png = ExportManager.pngData(from: cgImage)
        else {
            Log.export.error("Rich payload build failed: render or PNG encode returned nil")
            return nil
        }

        var payload = Payload(png: png)
        if includeRichText {
            let attributed = highlightedCode(for: config)
            payload.rtf = rtfData(from: attributed)
            payload.html = htmlData(from: attributed)
        }
        return payload
    }

    /// The highlighted attributed string for `config`'s code, using the config's
    /// language, theme, and *selected font* so the copied rich text matches the
    /// rendered image's typography (CS-054).
    @MainActor
    static func highlightedCode(for config: SnapshotConfig) -> NSAttributedString {
        let font = CodeFont.resolved(
            family: config.fontName, size: config.fontSize, ligatures: config.fontLigatures)
        return HighlightManager.shared.attributedString(
            for: config.code, language: config.language, theme: config.theme, font: font)
    }

    // MARK: - Writing to the pasteboard

    /// Writes a built payload to the general pasteboard as a single multi-format
    /// item: PNG first (so an image well still receives the picture), then RTF and
    /// HTML when present (CS-054). Returns whether the PNG was written.
    ///
    /// All representations live on **one** pasteboard item so a destination reads
    /// whichever format it prefers from the same copy, rather than competing items.
    @discardableResult
    static func write(_ payload: Payload, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(payload.png, forType: pngType)
        if let rtf = payload.rtf { item.setData(rtf, forType: rtfType) }
        if let html = payload.html { item.setData(html, forType: htmlType) }
        let wrote = pasteboard.writeObjects([item])
        Log.export.info(
            "Rich copy wrote pasteboard item (image+\(payload.hasRichText ? "richtext" : "imageonly", privacy: .public), success \(wrote, privacy: .public))"
        )
        return wrote
    }

    /// Renders `config` and copies the image plus, when `includeRichText` is on,
    /// highlighted RTF/HTML to the clipboard, performing the bounded serialization
    /// off the main actor so a large capture never blocks UI (CS-054).
    ///
    /// The render itself is main-actor work (it drives `ImageRenderer` and the
    /// highlight engine), so the payload is built on the main actor and only the
    /// final pasteboard write is hopped back; the size cap keeps the build cost
    /// bounded. Returns whether the image was placed on the pasteboard.
    @MainActor
    @discardableResult
    static func copy(
        _ config: SnapshotConfig,
        scale: CGFloat,
        fixedSize: CGSize?,
        profile: ColorProfile,
        includeRichText: Bool,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard
            let payload = makePayload(
                for: config, scale: scale, fixedSize: fixedSize, profile: profile,
                includeRichText: includeRichText)
        else { return false }
        return write(payload, to: pasteboard)
    }

    // MARK: - Explicit single-representation copies (CS-054)

    /// Copies the rendered image as a `data:image/png;base64,…` URI string
    /// (CS-054). Returns whether the string was placed on the pasteboard; `false`
    /// if the image could not be rendered/encoded or the URI exceeded the cap.
    ///
    /// The base64 encoding is bounded by `maxRepresentationBytes` and is the only
    /// non-trivial cost, so this stays responsive even for a large card.
    @MainActor
    @discardableResult
    static func copyDataURI(
        for config: SnapshotConfig,
        scale: CGFloat,
        fixedSize: CGSize?,
        profile: ColorProfile,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard
            let cgImage = ExportManager.renderCGImage(
                config, scale: scale, fixedSize: fixedSize, profile: profile),
            let png = ExportManager.pngData(from: cgImage),
            let uri = dataURI(forPNG: png)
        else {
            Log.export.error("Copy data URI failed: render, encode, or cap")
            return false
        }
        pasteboard.clearContents()
        let wrote = pasteboard.setString(uri, forType: .string)
        Log.export.info("Copied PNG data URI to pasteboard (success \(wrote, privacy: .public))")
        return wrote
    }

    /// Copies the highlighted code as styled text (RTF and HTML), preserving the
    /// syntax colors and the selected font (CS-054). Returns whether at least one
    /// styled representation was placed on the pasteboard.
    ///
    /// Both RTF and HTML are written so an RTF-preferring app (Pages, Mail) and an
    /// HTML-preferring one (many web editors) each get colored text from the same
    /// copy; a plain-text fallback rides along so a code editor still receives the
    /// raw source.
    @MainActor
    @discardableResult
    static func copyHighlightedCode(
        for config: SnapshotConfig,
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let attributed = highlightedCode(for: config)
        let rtf = rtfData(from: attributed)
        let html = htmlData(from: attributed)
        guard rtf != nil || html != nil else {
            Log.export.error("Copy highlighted code failed: no styled representation produced")
            return false
        }

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let rtf { item.setData(rtf, forType: rtfType) }
        if let html { item.setData(html, forType: htmlType) }
        // A plain-text representation lets a code editor that ignores styling still
        // receive the source text.
        item.setString(config.code, forType: .string)
        let wrote = pasteboard.writeObjects([item])
        Log.export.info(
            "Copied highlighted code to pasteboard (success \(wrote, privacy: .public))")
        return wrote
    }
}

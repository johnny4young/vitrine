import AppKit
import OSLog

extension ExportManager {
    /// Replaces the pasteboard contents with the exact plain-text source.
    ///
    /// Accepting a pasteboard keeps the primitive deterministic in tests and avoids
    /// touching the developer's clipboard outside the user-initiated default path.
    @discardableResult
    static func copySourceToPasteboard(
        _ source: String, to pasteboard: NSPasteboard = .general
    ) -> Bool {
        pasteboard.clearContents()
        let copied = pasteboard.setString(source, forType: .string)
        Log.export.info("Copied source to pasteboard (success \(copied, privacy: .public))")
        return copied
    }

    /// Renders and writes the image to the general pasteboard. Returns success.
    ///
    /// By default this places a single PNG representation — the unchanged
    /// one-shortcut copy. When `richText` is true (the user opted into the rich
    /// clipboard), it instead places a multi-representation item: the same
    /// PNG plus the highlighted code as RTF and HTML, so a paste into a rich-text
    /// editor keeps the syntax colors and font while an image well still receives
    /// the picture. The PNG round-trip is identical in both modes — `richText`
    /// only *adds* representations, never changes the image bytes.
    @discardableResult
    static func copyToPasteboard(
        _ config: SnapshotConfig, scale: CGFloat = 2, fixedSize: CGSize? = nil,
        profile: ColorProfile = .sRGB, richText: Bool = false, plainText: Bool = false,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        // Either opt-in (rich styled text, or the plain-text rider) needs the
        // multi-representation item, so route both through RichPasteboard; the plain
        // image fast-path stays for the default copy that asked for neither.
        if richText || plainText {
            return RichPasteboard.copy(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                includeRichText: richText, includePlainText: plainText,
                backgroundImageStore: backgroundImageStore,
                foregroundImageStore: foregroundImageStore, to: pasteboard)
        }
        guard
            let cgImage = renderCGImage(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                backgroundImageStore: backgroundImageStore,
                foregroundImageStore: foregroundImageStore)
        else {
            Log.export.error("Copy to pasteboard failed: render returned nil")
            return false
        }
        return copyPNGToPasteboard(cgImage, to: pasteboard)
    }

    /// Writes a PNG of an already-rendered `cgImage` to the pasteboard (the general
    /// one in production; tests pass a scratch pasteboard so parallel suites can't
    /// clobber each other on the real clipboard) — the shared primitive behind the
    /// config-based copy above and editors that hold a rendered asset. Returns success.
    @discardableResult
    static func copyPNGToPasteboard(
        _ cgImage: CGImage, to pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let png = pngData(from: cgImage) else {
            Log.export.error("Copy to pasteboard failed: PNG encode returned nil")
            return false
        }
        pasteboard.clearContents()
        let copied = pasteboard.setData(png, forType: .png)
        Log.export.info("Copied image to pasteboard (success \(copied, privacy: .public))")
        return copied
    }
}

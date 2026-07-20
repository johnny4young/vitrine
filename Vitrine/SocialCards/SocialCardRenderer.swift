import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Renders a `SocialCardModel` to an image and exports it to the clipboard, a
/// file, or the share sheet.
///
/// This is the social-card counterpart to `ExportManager`: it composes
/// `SocialCardCanvas` and rasterizes it through **`ImageRenderer`, not WebKit**
/// , so the render stays 100% local and deterministic — no
/// network, no remote render service, and the user's content never leaves the Mac.
/// The generic, format-level plumbing (PNG encoding, sRGB/P3 normalization with
/// preserved alpha) is shared with `ExportManager` rather than duplicated, so a
/// social card and a code snapshot encode pixels the same way.
///
/// Every export entry point first checks `model.isRenderable`: an empty model
/// (no title and no excerpt) yields `nil`/`false` rather than a blank image, so a
/// caller can give precise feedback instead of shipping an empty card.
enum SocialCardRenderer {
    /// Renders `model` to a `CGImage` at the default 1200×630 (or `size`), scaled by
    /// `scale` and normalized into `profile`'s color space (sRGB by default).
    ///
    /// Returns `nil` when the model has nothing to show (`isRenderable` is false) or
    /// the renderer itself fails. The render is wrapped in the same `os_signpost`
    /// interval the snapshot path uses, carrying only non-PII measures (the
    /// template and excerpt length), never the card's text.
    static func renderCGImage(
        _ model: SocialCardModel,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB
    ) -> CGImage? {
        guard model.isRenderable else {
            Log.render.error("Social card render skipped: model is empty")
            return nil
        }

        let signposter = RenderSignpost.signposter
        let state = signposter.beginInterval(
            RenderSignpost.renderName,
            "card template=\(model.template.rawValue) length=\(model.codeExcerpt.count)")
        defer { signposter.endInterval(RenderSignpost.renderName, state) }

        let renderer = ImageRenderer(content: SocialCardCanvas(model: model, size: size))
        renderer.scale = scale
        // Pin the layout size so the rendered pixel size is exactly `size × scale`
        // (1200×630 at 1×), independent of the card's content ("default
        // export is 1200×630").
        renderer.proposedSize = ProposedViewSize(size)
        guard let cgImage = renderer.cgImage else {
            Log.render.error("Social card render produced no image")
            return nil
        }
        return ExportManager.normalized(cgImage, to: profile)
    }

    /// Renders `model` to an `NSImage` (used by the share sheet).
    static func renderNSImage(
        _ model: SocialCardModel,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB
    ) -> NSImage? {
        guard let cgImage = renderCGImage(model, size: size, scale: scale, profile: profile) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Renders `model` to single-page PDF data at `size × 1` (PDF is a color-managed
    /// vector document, so the raster color-profile choice does not apply). Returns
    /// `nil` for an empty model or a render failure.
    static func pdfData(
        _ model: SocialCardModel, size: CGSize = SocialCardModel.defaultSize
    ) -> Data? {
        guard model.isRenderable else {
            Log.render.error("Social card PDF skipped: model is empty")
            return nil
        }
        // Shares the single-page PDF rasterizer with the snapshot path; only
        // the canvas differs.
        return ExportManager.pdfData(SocialCardCanvas(model: model, size: size), proposedSize: size)
    }

    // MARK: - Clipboard / save / share flows

    /// Renders the card and writes a PNG to the general pasteboard. Returns success.
    ///
    /// This is the clipboard flow: a single PNG representation, the same encode a
    /// snapshot copy uses, so a social card pastes into any image well.
    @discardableResult
    static func copyToPasteboard(
        _ model: SocialCardModel,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let cgImage = renderCGImage(model, size: size, scale: scale, profile: profile),
            let png = ExportManager.pngData(from: cgImage)
        else {
            Log.export.error("Social card copy failed: render or PNG encode returned nil")
            return false
        }
        pasteboard.clearContents()
        let copied = pasteboard.setData(png, forType: .png)
        Log.export.info("Copied social card to pasteboard (success \(copied, privacy: .public))")
        return copied
    }

    /// Presents an `NSSavePanel` and writes the card as PNG, PDF, HEIC, or AVIF, returning the
    /// outcome so a caller can give precise feedback: `.saved` on a write,
    /// `.cancelled` on dismiss, `.failed` on a render/encode/write error.
    ///
    /// `profile` applies to raster output only; PDF is unaffected by the raster
    /// color-profile choice. The destination path is never logged (privacy policy).
    @discardableResult
    static func saveToFile(
        _ model: SocialCardModel,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        format: ExportFormat = .png,
        profile: ColorProfile = .sRGB
    ) -> ExportManager.SaveOutcome {
        let payload = ExportManager.encodedPayload(
            format,
            png: { renderCGImage(model, size: size, scale: scale, profile: profile) },
            pdf: { pdfData(model, size: size) })
        guard let payload else {
            Log.export.error("Social card save failed: render or encode returned nil")
            return .failed
        }
        // The shared panel/write path — one logging point for every save flow.
        return ExportManager.saveToFile(payload: payload, suggestedName: "vitrine-card")
    }

    /// Renders the card and presents the macOS share sheet anchored to `view`.
    /// Returns `false` when the model is empty or the render fails, so
    /// the caller never shows an empty picker.
    @discardableResult
    static func share(
        _ model: SocialCardModel,
        relativeTo view: NSView,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB
    ) -> Bool {
        guard let image = renderNSImage(model, size: size, scale: scale, profile: profile) else {
            Log.export.error("Social card share failed: render returned nil")
            return false
        }
        ShareManager.share(image, relativeTo: view)
        return true
    }
}

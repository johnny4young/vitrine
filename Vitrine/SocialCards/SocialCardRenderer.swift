import AppKit
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Renders a `SocialCardModel` to an image and exports it to the clipboard or a file.
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
        try? renderCGImageChecked(model, size: size, scale: scale, profile: profile)
    }

    /// Checked social-card raster path. The fixed card layout is evaluated by the
    /// shared render budget before Core Graphics allocates its scaled bitmap.
    static func renderCGImageChecked(
        _ model: SocialCardModel,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB
    ) throws(RenderBudgetError) -> CGImage {
        guard model.isRenderable else {
            Log.render.error("Social card render skipped: model is empty")
            throw .encodingFailed
        }

        let signposter = RenderSignpost.signposter
        let state = signposter.beginInterval(
            RenderSignpost.renderName,
            "card template=\(model.template.rawValue) length=\(model.codeExcerpt.count)")
        defer { signposter.endInterval(RenderSignpost.renderName, state) }

        return try ExportManager.renderCGImageChecked(
            SocialCardCanvas(model: model, size: size), proposedSize: size,
            scale: scale, profile: profile)
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

    static func renderNSImageChecked(
        _ model: SocialCardModel,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB
    ) throws(RenderBudgetError) -> NSImage {
        let image = try renderCGImageChecked(model, size: size, scale: scale, profile: profile)
        return NSImage(
            cgImage: image, size: NSSize(width: image.width, height: image.height))
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

    // MARK: - Clipboard / save flows

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
        copyToPasteboardOutcome(
            model, size: size, scale: scale, profile: profile,
            pasteboard: pasteboard) == .copied
    }

    @discardableResult
    static func copyToPasteboardOutcome(
        _ model: SocialCardModel,
        size: CGSize = SocialCardModel.defaultSize,
        scale: CGFloat = 2,
        profile: ColorProfile = .sRGB,
        pasteboard: NSPasteboard = .general
    ) -> ExportManager.CopyOutcome {
        guard model.isRenderable else { return .failed }
        let cgImage: CGImage
        do {
            cgImage = try renderCGImageChecked(
                model, size: size, scale: scale, profile: profile)
        } catch let error {
            return .renderFailed(error)
        }
        guard let png = ExportManager.pngData(from: cgImage) else {
            Log.export.error("Social card copy failed: render or PNG encode returned nil")
            return .renderFailed(.encodingFailed)
        }
        pasteboard.clearContents()
        let copied = pasteboard.setData(png, forType: .png)
        Log.export.info("Copied social card to pasteboard (success \(copied, privacy: .public))")
        return copied ? .copied : .failed
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
        guard model.isRenderable else { return .failed }
        let payload: (data: Data, type: UTType, ext: String)
        do {
            payload = try ExportManager.encodedPayloadChecked(
                format,
                raster: { () throws(RenderBudgetError) -> CGImage in
                    try renderCGImageChecked(
                        model, size: size, scale: scale, profile: profile)
                },
                pdf: { pdfData(model, size: size) })
        } catch let error {
            Log.export.error("Social card save failed: render or encode returned nil")
            return .renderFailed(error)
        }
        // The shared panel/write path — one logging point for every save flow.
        return ExportManager.saveToFile(payload: payload, suggestedName: "vitrine-card")
    }
}

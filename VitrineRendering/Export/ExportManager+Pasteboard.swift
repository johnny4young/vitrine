import AppKit
import OSLog
import VitrineDomain

extension ExportManager {
    /// Replaces the pasteboard contents with the exact plain-text source.
    ///
    /// Accepting a pasteboard keeps the primitive deterministic in tests and avoids
    /// touching the developer's clipboard outside the user-initiated default path.
    @discardableResult
    public static func copySourceToPasteboard(
        _ source: String, concealed: Bool = false, to pasteboard: NSPasteboard = .general
    ) -> Bool {
        let copied = ClipboardWriter.copy(source, concealed: concealed, to: pasteboard)
        RenderingLog.export.info(
            "Copied source to pasteboard (success \(copied, privacy: .public))")
        return copied
    }

    /// Renders and writes the image to the pasteboard, as a single PNG by default.
    ///
    /// `richText` and `plainText` add RTF/HTML or plain-text representations beside the
    /// same PNG bytes. Pasteboard failures stay distinct from a render rejection so
    /// callers can present the right recovery action.
    @discardableResult
    public static func copyToPasteboardOutcome(
        _ config: SnapshotConfig, scale: CGFloat = 2, fixedSize: CGSize? = nil,
        profile: ColorProfile = .sRGB, richText: Bool = false, plainText: Bool = false,
        concealed: Bool = false,
        backgroundImageStore: BackgroundImageStore = .container,
        foregroundImageStore: BackgroundImageStore = .foregroundContainer,
        pasteboard: NSPasteboard = .general
    ) -> CopyOutcome {
        // Either opt-in (rich styled text, or the plain-text rider) needs the
        // multi-representation item, so route both through RichPasteboard; the plain
        // image fast-path stays for the default copy that asked for neither.
        if richText || plainText {
            do {
                return try RichPasteboard.copyChecked(
                    config, scale: scale, fixedSize: fixedSize, profile: profile,
                    includeRichText: richText, includePlainText: plainText, concealed: concealed,
                    backgroundImageStore: backgroundImageStore,
                    foregroundImageStore: foregroundImageStore, to: pasteboard)
                    ? .copied : .failed
            } catch let error {
                return .renderFailed(error)
            }
        }
        let cgImage: CGImage
        do {
            cgImage = try renderCGImageChecked(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                backgroundImageStore: backgroundImageStore,
                foregroundImageStore: foregroundImageStore)
        } catch let error {
            RenderingLog.export.error("Copy to pasteboard failed: render rejected or failed")
            return .renderFailed(error)
        }
        return copyPNGToPasteboardOutcome(cgImage, concealed: concealed, to: pasteboard)
    }

    /// Writes an already-rendered raster as PNG. Tests pass a scratch pasteboard
    /// instead of the general clipboard. Encoding and write failures stay distinct.
    @discardableResult
    public static func copyPNGToPasteboardOutcome(
        _ cgImage: CGImage, concealed: Bool = false, to pasteboard: NSPasteboard = .general
    ) -> CopyOutcome {
        guard let png = pngData(from: cgImage) else {
            RenderingLog.export.error("Copy to pasteboard failed: PNG encode returned nil")
            return .renderFailed(.encodingFailed)
        }
        let copied = ClipboardWriter.copy(png, type: .png, concealed: concealed, to: pasteboard)
        RenderingLog.export.info("Copied image to pasteboard (success \(copied, privacy: .public))")
        return copied ? .copied : .failed
    }

    public enum CopyOutcome: Equatable {
        case copied
        case failed
        case renderFailed(RenderBudgetError)
    }
}

import AppKit
import VitrineRendering

/// The one image-copy call for the copy commands. Output (scale, profile, rich text)
/// can come from an editor session, but clipboard privacy is always the app-wide
/// preference: a session keeps only the default, so reading it there would silently
/// drop the confidential marker.
enum RenderedImageCopy {
    static func copy(
        _ config: SnapshotConfig, output: AppSettings, appWide: AppSettings,
        pasteboard: NSPasteboard = .general
    ) -> ExportManager.CopyOutcome {
        copy(
            config, scale: CGFloat(output.effectiveExportScale),
            fixedSize: output.effectiveFixedSize, output: output, appWide: appWide,
            pasteboard: pasteboard)
    }

    /// The same copy at explicit geometry, for one-off destination presets.
    static func copy(
        _ config: SnapshotConfig, scale: CGFloat, fixedSize: CGSize?, output: AppSettings,
        appWide: AppSettings, pasteboard: NSPasteboard = .general
    ) -> ExportManager.CopyOutcome {
        ExportManager.copyToPasteboardOutcome(
            config, scale: scale, fixedSize: fixedSize, profile: output.export.colorProfile,
            richText: output.export.richClipboard, plainText: output.export.textSidecar,
            concealed: appWide.export.concealClipboard, pasteboard: pasteboard)
    }
}

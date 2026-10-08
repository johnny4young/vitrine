import AppKit
import VitrineRendering

/// The one image-copy call for the copy commands. Output (scale, profile, rich text)
/// is per capture; clipboard privacy is the app-wide ``OutputBehavior``.
enum RenderedImageCopy {
    /// Copies at `settings`' geometry and output. An editor session's `outputBehavior`
    /// is the app-wide instance, so this is right for a session and the default alike.
    static func copy(
        _ config: SnapshotConfig, settings: AppSettings, pasteboard: NSPasteboard = .general
    ) -> ExportManager.CopyOutcome {
        copy(
            config, output: settings.export, behavior: settings.outputBehavior,
            scale: CGFloat(settings.effectiveExportScale), fixedSize: settings.effectiveFixedSize,
            pasteboard: pasteboard)
    }

    /// The same copy at explicit geometry, for one-off destination presets.
    static func copy(
        _ config: SnapshotConfig, output: ExportSettings, behavior: OutputBehavior,
        scale: CGFloat, fixedSize: CGSize?, pasteboard: NSPasteboard = .general
    ) -> ExportManager.CopyOutcome {
        ExportManager.copyToPasteboardOutcome(
            config, scale: scale, fixedSize: fixedSize, profile: output.colorProfile,
            richText: output.richClipboard, plainText: output.textSidecar,
            concealed: behavior.concealClipboard, pasteboard: pasteboard)
    }
}

import Foundation
import VitrineRendering

/// The editor's Save Image, shared by the toolbar button and the File menu command.
enum EditorImageSave {
    static func embeddingPlan(_ settings: AppSettings) -> EmbeddedProject.Plan {
        EmbeddedProject.plan(
            for: settings.exportConfig, format: settings.export.format,
            enabled: settings.outputBehavior.embedsEditableProject)
    }

    static func run(_ settings: AppSettings) -> Notifier.CaptureFeedback? {
        let plan = embeddingPlan(settings)
        let outcome = ExportManager.saveToFile(
            settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            format: settings.export.format, fixedSize: settings.effectiveFixedSize,
            profile: settings.export.colorProfile, embeddedProject: plan.link)
        return ExportFeedback.saveOutcome(outcome, embedding: plan)
    }
}

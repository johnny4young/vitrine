import SwiftUI
import VitrineDomain
import VitrineRendering

extension AppSettings {
    /// Always read from the editor session, because the app-wide default knows nothing
    /// about a window's redaction or marks.
    var reproductionCommand: CLIReproductionCommand {
        CLIReproductionCommand(
            style: style,
            destinationPresetID: selectedPresetID,
            scale: export.scale,
            format: export.format,
            profile: export.colorProfile,
            watermark: exportWatermark)
    }
}

extension EditorView {
    /// `nil` when this copy of the app carries no CLI to run the line with.
    var reproductionCommandTitle: String? {
        guard CLIToolInstaller.embeddedCLI != nil else { return nil }
        return entitlements.isUnlocked(.automation)
            ? String(localized: "Copy Command")
            : String(localized: "Copy Command — Requires PRO")
    }

    /// Stays enabled when limited: a disabled menu item could not name what is missing.
    func copyReproductionCommand() {
        guard entitlements.isUnlocked(.automation) else {
            exportSheet = .automationPaywall
            return
        }
        let resolved = session.appliedRecipeID.flatMap {
            try? environment.workspaceRecipes.resolvedRecipe(id: $0)
        }
        let recipe = resolved.map {
            CLIReproductionCommand.RecipeFile(
                relativePath: $0.recipeRelativePath, recipe: $0.recipe)
        }
        session.feedback(reproductionFeedback(settings.reproductionCommand.outcome(recipe: recipe)))
    }

    private func reproductionFeedback(
        _ outcome: CLIReproductionCommand.Outcome
    ) -> Notifier.CaptureFeedback {
        switch outcome {
        case .unavailable(let limits):
            let names = ListFormatter.localizedString(byJoining: limits.map(\.displayName))
            return Notifier.failure(String(localized: "Copy Command can't include: \(names)"))
        case .command(let line):
            let concealed = settings.outputBehavior.concealClipboard
            guard ClipboardWriter.copy(line, concealed: concealed) else {
                return Notifier.failure(String(localized: "Couldn't copy the command"))
            }
            let placeholder = settings.reproductionCommand.inputPlaceholder
            return Notifier.confirmation(
                String(localized: "Copied. Run it in your project and replace \(placeholder)."))
        }
    }

    var reproductionPaletteCommands: [EditorCommand] {
        guard settings.hasRenderableContent, let title = reproductionCommandTitle else { return [] }
        return [
            EditorCommand(
                id: "export.reproductionCommand", title: title, group: String(localized: "Export"),
                keywords: ["cli", "terminal", "shell", "vitrine render"], symbol: "terminal"
            ) { copyReproductionCommand() }
        ]
    }
}

extension CLIReproductionCommand.Limit {
    fileprivate var displayName: String {
        switch self {
        case .annotations: String(localized: "annotations")
        case .pastedImage: String(localized: "pasted image")
        case .imageBackground: String(localized: "image background")
        case .customTheme: String(localized: "custom theme")
        case .customGradient: String(localized: "unevenly spaced gradient")
        case .brandMark: String(localized: "brand logo, QR or footer")
        case .controlCharacters: String(localized: "control characters in header text")
        case .likelySecret: String(localized: "likely secret in header text")
        case .recipeOutsideWorkspace: String(localized: "recipe outside its folder")
        }
    }
}

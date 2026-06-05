import AppIntents

/// Surfaces Vitrine's App Intents to Shortcuts, Spotlight, and Siri (CS-034).
///
/// Declaring the intents here makes them appear as ready-made actions in the
/// Shortcuts gallery and as Spotlight suggestions without the user assembling a
/// Shortcut by hand. The phrases keep `.applicationName` so they read naturally
/// ("Render code with Vitrine") and never collide with another app's vocabulary.
struct VitrineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RenderCodeImageIntent(),
            phrases: [
                "Render code with \(.applicationName)",
                "Make a code image with \(.applicationName)",
                "Create a code screenshot with \(.applicationName)",
            ],
            shortTitle: "Render Code to Image",
            systemImageName: "curlybraces.square")

        AppShortcut(
            intent: OpenCodeInEditorIntent(),
            phrases: [
                "Open code in \(.applicationName)",
                "Edit code in \(.applicationName)",
            ],
            shortTitle: "Open Code in Editor",
            systemImageName: "square.and.pencil")
    }
}

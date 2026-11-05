import SwiftUI
import VitrineRendering

/// The shell side of workspace recipes: copyable commands with their access tier, and the
/// order in which a recipe, a preset and explicit flags override each other.
struct WorkspaceRecipeCommandsSection: View {
    var settings: AppSettings

    @State private var copiedLine: String?

    var body: some View {
        TokenGroup(title: Text("Command line")) {
            ForEach(CLICookbookEntry.all) { entry in
                VStack(alignment: .leading, spacing: VitrineTokens.Spacing.xs) {
                    HStack(spacing: VitrineTokens.Spacing.xs) {
                        label(for: entry.id)
                            .font(.system(size: VitrineTokens.FontSize.caption))
                            .foregroundStyle(VitrineTokens.Text.tertiary)
                        tierBadge(requiresPro: entry.requiresPro)
                    }
                    ForEach(entry.lines.indices, id: \.self) { index in
                        commandRow(
                            entry.lines[index],
                            identifier: "recipe-command-\(entry.id.rawValue)-\(index)")
                    }
                    if entry.id == .terminal { terminalPrerequisites }
                }
                .padding(.vertical, 9)
            }
        }
        .task(id: copiedLine) {
            guard copiedLine != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copiedLine = nil
        }

        TokenGroup(title: Text("Precedence, low to high")) {
            VStack(alignment: .leading, spacing: 3) {
                precedenceStep(1) { Text("Vitrine defaults") }
                precedenceStep(2) { Text("Destination preset (--preset or recipe)") }
                precedenceStep(3) { Text("Recipe style and output defaults") }
                precedenceStep(4) { code("--style-preset") }
                precedenceStep(5) {
                    Text("Explicit flags")
                    code("--theme --padding --format, --out card.pdf")
                }
            }
            .padding(.vertical, 9)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recipe-precedence-ladder")
        }
    }

    private func commandRow(_ line: String, identifier: String) -> some View {
        HStack(alignment: .top, spacing: VitrineTokens.Spacing.xs) {
            code(line)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                let concealed = settings.outputBehavior.concealClipboard
                if ClipboardWriter.copy(line, concealed: concealed) { copiedLine = line }
            } label: {
                Image(systemName: copiedLine == line ? "checkmark" : "doc.on.doc")
                    .font(.system(size: VitrineTokens.FontSize.caption))
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .accessibilityLabel(Text("Copy"))
            .accessibilityValue(Text(verbatim: line))
            .accessibilityIdentifier(identifier)
        }
    }

    private var terminalPrerequisites: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Needs Shell integration. vpane also needs tmux, and PRO without -e.")
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Shell integration") {
                SettingsTab.general.select()
            }
            .buttonStyle(.link)
            .font(.system(size: VitrineTokens.FontSize.caption))
            .accessibilityIdentifier("recipe-command-shell-integration-link")
        }
    }

    private func label(for id: CLICookbookEntry.ID) -> Text {
        switch id {
        case .validate: Text("Check a recipe")
        case .render: Text("One file; the recipe decides theme, size and format")
        case .override: Text("Override one value; flags beat the recipe")
        case .multiSize: Text("Several sizes at once, into a folder")
        case .terminal: Text("Capture the terminal screen, or open it in the editor")
        }
    }

    @ViewBuilder
    private func tierBadge(requiresPro: Bool) -> some View {
        if requiresPro {
            ProBadge()
        } else {
            Text("Free to use")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .overlay(Capsule().strokeBorder(VitrineTokens.Line.border))
        }
    }

    private func precedenceStep<Content: View>(
        _ number: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VitrineTokens.Spacing.xs) {
            Text(verbatim: "\(number)")
                .foregroundStyle(VitrineTokens.Text.tertiary)
                .monospacedDigit()
            content()
        }
        .font(.system(size: VitrineTokens.FontSize.caption))
    }

    private func code(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: VitrineTokens.FontSize.caption, design: .monospaced))
            .foregroundStyle(VitrineTokens.Text.primary)
    }
}

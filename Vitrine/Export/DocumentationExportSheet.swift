import AppKit
import SwiftUI
import VitrineDomain
import VitrineRendering

/// One explicit snapshot, one render, and one transaction. No history or clipboard writes.
struct DocumentationExportSheet: View {
    let config: SnapshotConfig
    let scale: CGFloat
    let fixedSize: CGSize?
    let profile: ColorProfile
    let feedback: FeedbackDisplay
    @Environment(\.dismiss) private var dismiss
    @State private var representations: Set<DocumentationRepresentation> = [.markdown]
    @State private var name = ""
    @State private var writing = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export for Documentation").font(.headline)
            Text(
                "Save a PNG and selected copyable representations in a new folder. Existing files are never replaced."
            )
            .fixedSize(horizontal: false, vertical: true)
            TextField("Folder name", text: $name)
                .accessibilityIdentifier("documentation-folder-name")
                .disabled(writing)
            Toggle("Markdown", isOn: selected(.markdown)).disabled(writing)
                .accessibilityIdentifier("documentation-markdown")
            Toggle("HTML", isOn: selected(.html)).disabled(writing)
                .accessibilityIdentifier("documentation-html")
            Toggle("Plain text", isOn: selected(.text)).disabled(writing || config.usesImageContent)
                .accessibilityIdentifier("documentation-text")
            if config.usesImageContent {
                Text("Imported images have no original source transcript.").font(.caption)
            }
            if writing { ProgressView().accessibilityIdentifier("documentation-progress") }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier(
                    "documentation-error")
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    operation?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("documentation-cancel")
                Button("Choose Parent Folder…", action: export)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        writing || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("documentation-export")
            }
        }
        .padding(24).frame(width: 430)
        .onAppear { name = SuggestedFilename.basename(for: config) + "-documentation" }
        .onDisappear { operation?.cancel() }
    }

    private func selected(_ representation: DocumentationRepresentation) -> Binding<Bool> {
        Binding(
            get: { representations.contains(representation) },
            set: { enabled in
                if enabled {
                    representations.insert(representation)
                } else {
                    representations.remove(representation)
                }
            })
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Parent Folder…")
        panel.prompt = String(localized: "Export Here")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        writing = true
        errorMessage = nil
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let representations = representations
        operation = Task {
            let access = parent.startAccessingSecurityScopedResource()
            defer { if access { parent.stopAccessingSecurityScopedResource() } }
            do {
                try Task.checkCancellation()
                let image = try ExportManager.renderCGImageChecked(
                    config, scale: scale, fixedSize: fixedSize, profile: profile)
                guard let png = ExportManager.pngData(from: image) else {
                    throw RenderBudgetError.encodingFailed
                }
                let package = DocumentationPackage(
                    config: config, png: png, representations: representations)
                _ = try await DocumentationPackageWriter.write(package, parent: parent, name: name)
                feedback(Notifier.confirmation(String(localized: "Documentation exported")))
                dismiss()
            } catch is CancellationError {
                // Cancellation before commit is silent, just like a dismissed save panel.
            } catch let renderError as RenderBudgetError {
                writing = false
                errorMessage = ExportFeedback.renderFailure(renderError).message
            } catch {
                writing = false
                errorMessage = String(
                    localized:
                        "Couldn't export documentation. Choose a new folder name and check access to its parent."
                )
            }
        }
    }
}

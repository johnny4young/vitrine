import SwiftUI
import VitrineDomain
import VitrineRendering

/// Content metadata stays in the editor, not the reusable Settings header controls.
struct AlternativeTextField: View {
    @Bindable var settings: AppSettings
    @State private var draft = AlternativeTextDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Alternative text",
                text: Binding(
                    get: { draft.input },
                    set: { input in
                        do {
                            settings.style.altText = try draft.update(input)
                        } catch {
                            // Keep the last accepted model value; feedback explains rejection.
                        }
                    }), axis: .vertical
            )
            .lineLimit(2...4)
            .accessibilityIdentifier("alternative-text-field")
            HStack(alignment: .firstTextBaseline) {
                Text(
                    draft.rejected
                        ? String(
                            localized: "Alternative text must contain at most 1024 characters.")
                        : String(
                            localized:
                                "Describes this image in Markdown and HTML; not drawn on the image."
                        )
                )
                .font(.caption)
                .foregroundStyle(draft.rejected ? .red : .secondary)
                .accessibilityIdentifier("alternative-text-feedback")
                Spacer(minLength: 0)
                // Only an empty field offers a draft, so typed text is never replaced.
                if draft.input.isEmpty, !settings.style.usesImageContent {
                    Button("Draft") {
                        settings.style.altText = AlternativeTextDrafter.draft(for: settings.config)
                    }
                    .controlSize(.small)
                    .disabled(settings.documentIsEmpty)
                    .accessibilityIdentifier("alternative-text-draft-button")
                }
            }
        }
        .onAppear { draft.restore(settings.style.altText) }
        .onChange(of: settings.style.altText) { _, value in draft.synchronize(value) }
        // The generation, not the text, so typing never re-evaluates the inspector.
        .onChange(of: settings.documentGeneration) { _, _ in
            draft.contentChanged(settings.style.altText)
        }
        .onChange(of: settings.style.foregroundImage) { _, _ in
            draft.contentChanged(settings.style.altText)
        }
    }
}

/// A rejected, uncommitted input must not survive replacement when the model remains nil.
/// Accepted descriptions and spaces in an in-progress valid description survive ordinary edits.
struct AlternativeTextDraft {
    private(set) var input = ""
    private(set) var rejected = false

    mutating func update(_ input: String) throws -> SnapshotAltText? {
        self.input = input
        do {
            let value = try SnapshotAltText.normalized(input)
            rejected = false
            return value
        } catch {
            rejected = true
            throw error
        }
    }

    mutating func restore(_ value: SnapshotAltText?) {
        input = value?.text ?? ""
        rejected = false
    }

    mutating func synchronize(_ value: SnapshotAltText?) {
        if rejected || (try? SnapshotAltText.normalized(input)) != value { restore(value) }
    }

    mutating func contentChanged(_ value: SnapshotAltText?) {
        if rejected || (try? SnapshotAltText.normalized(input)) == nil { restore(value) }
    }
}

/// Describes a document from its own metadata, without reading the source's words or
/// calling any service. An image's pixels say nothing here, so it gets no draft.
enum AlternativeTextDrafter {
    static func draft(for config: SnapshotConfig) -> SnapshotAltText? {
        guard !config.usesImageContent, !config.code.isEmpty else { return nil }
        var rows = config.sidecarText.components(separatedBy: "\n")
        if rows.count > 1, rows.last?.isEmpty == true { rows.removeLast() }
        let summary =
            "\(subject(for: config.language)), " + String(localized: "\(rows.count) lines")
        // Header text travels further once it is in a description, so flagged text stays out.
        let safe = { (text: String?) in
            text.flatMap { SecretScanner.scan($0).isEmpty ? $0 : nil }
        }
        var detailed = summary
        if let filename = safe(config.metadata.filename) { detailed += ", \(filename)" }
        if let title = safe(config.metadata.title) { detailed += ": \(title)" }
        // Long header text must not cost the description itself.
        return (try? SnapshotAltText.normalized(detailed))
            ?? (try? SnapshotAltText.normalized(summary))
    }

    private static func subject(for language: Language) -> String {
        switch language {
        case .terminal: String(localized: "Terminal output")
        case .diff: String(localized: "Diff")
        case .plaintext: String(localized: "Plain text")
        default: String(localized: "\(language.displayName) code")
        }
    }
}

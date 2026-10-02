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
            Text(
                draft.rejected
                    ? String(localized: "Alternative text must contain at most 1024 characters.")
                    : String(
                        localized:
                            "Describes this image in Markdown and HTML; not drawn on the image.")
            )
            .font(.caption)
            .foregroundStyle(draft.rejected ? .red : .secondary)
            .accessibilityIdentifier("alternative-text-feedback")
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

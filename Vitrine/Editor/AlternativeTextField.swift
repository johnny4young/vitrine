import SwiftUI
import VitrineDomain
import VitrineRendering

/// Content metadata stays in the editor, not the reusable Settings header controls.
struct AlternativeTextField: View {
    @Bindable var settings: AppSettings
    @State private var rejected = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Alternative text",
                text: Binding(
                    get: { draft },
                    set: { input in
                        draft = input
                        do {
                            settings.style.altText = try SnapshotAltText.normalized(input)
                            rejected = false
                        } catch { rejected = true }
                    }), axis: .vertical
            )
            .lineLimit(2...4)
            .accessibilityIdentifier("alternative-text-field")
            Text(
                rejected
                    ? String(localized: "Alternative text must contain at most 1024 characters.")
                    : String(
                        localized:
                            "Describes this image in Markdown and HTML; not drawn on the image.")
            )
            .font(.caption)
            .foregroundStyle(rejected ? .red : .secondary)
            .accessibilityIdentifier("alternative-text-feedback")
        }
        .onAppear { draft = settings.style.altText?.text ?? "" }
        .onChange(of: settings.style.altText) { _, value in
            // Keep whitespace while typing, but adopt descriptions restored from another document.
            if rejected || (try? SnapshotAltText.normalized(draft)) != value {
                draft = value?.text ?? ""
                rejected = false
            }
        }
    }
}

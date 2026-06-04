import SwiftUI

/// The SwiftUI view that becomes the exported PNG (CS-005). WYSIWYG: what you see
/// here is exactly what `ImageRenderer` exports.
///
/// The card hugs its content (like ray.so) with a subtle border and an offset
/// shadow. Highlighting is computed synchronously in `body` (not via `.task`)
/// because `ImageRenderer` does not run async view lifecycle, so the exported
/// image must be fully highlighted at render time.
struct SnapshotCanvas: View {
    let config: SnapshotConfig

    var body: some View {
        codeCard
            .padding(config.padding)
            .background(BackgroundView(style: config.background))
            .fixedSize()
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if config.showChrome {
                WindowChrome()
            }
            Text(highlightedCode)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(minWidth: 360, alignment: .leading)
        .background(HighlightManager.shared.backgroundColor(for: config.theme))
        .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: config.effectiveShadowRadius, x: 0, y: 8)
    }

    private var highlightedCode: AttributedString {
        let placeholder = "// Paste or type code…"
        let source = config.code.isEmpty ? placeholder : config.code
        let font =
            NSFont(name: config.fontName, size: config.fontSize)
            ?? .monospacedSystemFont(ofSize: config.fontSize, weight: .regular)
        let attributed = HighlightManager.shared.attributedString(
            for: source,
            language: config.language,
            theme: config.theme,
            font: font
        )
        return AttributedString(attributed)
    }
}

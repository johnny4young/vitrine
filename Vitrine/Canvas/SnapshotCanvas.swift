import SwiftUI

/// The SwiftUI view that becomes the exported PNG (CS-005). WYSIWYG: what you see
/// here is exactly what `ImageRenderer` exports.
///
/// Highlighting is computed synchronously in `body` (not via `.task`) because
/// `ImageRenderer` does not run async view lifecycle, so the exported image must
/// be fully highlighted at render time.
struct SnapshotCanvas: View {
    let config: SnapshotConfig

    var body: some View {
        ZStack {
            BackgroundView(style: config.background)
            codeCard
                .padding(config.padding)
        }
        .frame(minWidth: 480)
        .fixedSize()
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if config.showChrome {
                WindowChrome()
            }
            Text(highlightedCode)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(config.theme.background)
        .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
        .shadow(radius: config.effectiveShadowRadius)
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

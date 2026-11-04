import SwiftUI
import VitrineDomain

/// The row above a diff: the changed file's path (or a file count), the added and removed
/// line counts, and a five-cell diffstat bar. It holds no copy, so an exported image reads
/// the same in every locale.
struct DiffStatsHeader: View {
    static let fontSize: CGFloat = 12
    private static let cellCount = 5
    static let maximumPathLength = 64
    private static let addedColor = Color(hex: "#2EA043")
    private static let removedColor = Color(hex: "#F85149")

    let document: DiffDocument
    /// The path to show; `nil` when there are several files or its row is redacted.
    let path: String?
    let font: NSFont
    let textColor: Color

    var body: some View {
        HStack(spacing: Brand.Spacing.xs) {
            subject
            Spacer(minLength: Brand.Spacing.md)
            Text(verbatim: "+\(document.additions)").foregroundStyle(Self.addedColor)
            Text(verbatim: "−\(document.deletions)").foregroundStyle(Self.removedColor)
            cells
        }
        .font(Font(font))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var subject: some View {
        if let path {
            Text(verbatim: Self.truncated(path)).foregroundStyle(textColor)
        } else if document.files.count > 1 {
            HStack(spacing: Brand.Spacing.xxs) {
                Image(systemName: "doc.on.doc")
                Text(verbatim: "\(document.files.count)")
            }
            .foregroundStyle(textColor)
        }
    }

    private var cells: some View {
        let added = document.additionCells(of: Self.cellCount)
        let hasChanges = document.additions + document.deletions > 0
        return HStack(spacing: 1) {
            ForEach(0..<Self.cellCount, id: \.self) { cell in
                Rectangle()
                    .fill(
                        !hasChanges
                            ? textColor.opacity(0.2)
                            : cell < added ? Self.addedColor : Self.removedColor
                    )
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var accessibilityText: String {
        let counts = String(
            localized: "Added: \(document.additions), removed: \(document.deletions)")
        if let path { return "\(path), \(counts)" }
        guard document.files.count > 1 else { return counts }
        return "\(String(localized: "Files: \(document.files.count)")), \(counts)"
    }

    /// Keeps the end of a long path, the part that names the file. A fixed length, because
    /// the card hugs its content and has no width to truncate against.
    static func truncated(_ path: String) -> String {
        guard path.count > maximumPathLength else { return path }
        return "…" + path.suffix(maximumPathLength - 1)
    }
}

/// The mutually exclusive export surfaces presented from the editor toolbar.
///
/// Both the expanded toolbar buttons and the compact actions menu route through
/// this value so presentation ownership does not change when the toolbar changes
/// density.
enum EditorExportSheet: String, Hashable, Identifiable {
    case multiSizeExport
    case multiSizePaywall
    case carouselExport
    case carouselPaywall

    var id: String { rawValue }

    static func multiSize(isUnlocked: Bool) -> Self {
        isUnlocked ? .multiSizeExport : .multiSizePaywall
    }

    static func carousel(isUnlocked: Bool) -> Self {
        isUnlocked ? .carouselExport : .carouselPaywall
    }
}

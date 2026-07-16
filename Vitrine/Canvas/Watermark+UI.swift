import SwiftUI

/// SwiftUI presentation for the watermark placement, kept in the UI layer so
/// `Watermark`/`SnapshotConfig` stay UI-free (VitrineCore prerequisite). The model owns
/// the placement cases and their labels; this adapter supplies the `Alignment` the
/// watermark overlay pins to.
extension Watermark.Placement {
    /// The SwiftUI alignment used to pin the mark to its corner. `.free` has no corner
    /// anchor (it is positioned by `freePosition`); it returns `.center` only as an
    /// exhaustive fallback.
    var alignment: Alignment {
        switch self {
        case .bottomTrailing: .bottomTrailing
        case .bottomLeading: .bottomLeading
        case .topTrailing: .topTrailing
        case .topLeading: .topLeading
        case .free: .center
        case .footerBar: .bottom
        }
    }
}

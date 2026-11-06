import Foundation
import VitrineDomain

/// A size shown before any file exists. It comes from real renders, and the mark says the
/// files themselves are not written yet.
enum ExportSizeEstimate {
    /// Shown at least as wide as any estimate from 1 kB up, so a hidden copy can hold room
    /// for one. A rendered image is never smaller.
    static let widestBytes = 888_800_000

    static func shown(_ bytes: Int) -> String {
        "~" + Int64(bytes).formatted(.byteCount(style: .file))
    }

    static func spoken(_ bytes: Int, bundle: Bundle = .main) -> String {
        let size = Int64(bytes).formatted(.byteCount(style: .file))
        return String(localized: "about \(size)", bundle: bundle)
    }

    /// The format and estimated size together, as shown and as VoiceOver reads them.
    static func summary(
        format: ExportFormat, bytes: Int, bundle: Bundle = .main
    ) -> (text: String, spokenText: String) {
        let name = format.displayName
        return (
            "\(name) · \(shown(bytes))", "\(name), \(spoken(bytes, bundle: bundle))"
        )
    }
}

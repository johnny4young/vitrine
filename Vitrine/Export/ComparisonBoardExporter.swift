import Foundation
import UniformTypeIdentifiers

/// Encodes a board through the shared export formats at the scale captured by its draft.
@MainActor
enum ComparisonBoardExporter {
    static func encodedPayload(
        for draft: ComparisonBoardDraft,
        format: ExportFormat,
        profile: ColorProfile
    ) -> (data: Data, type: UTType, ext: String)? {
        ExportManager.encodedPayload(
            format,
            png: {
                try? draft.compose(scale: draft.exportScale, profile: profile).cgImage
            },
            pdf: {
                guard
                    let image = try? draft.compose(
                        scale: draft.exportScale,
                        profile: profile)
                else { return nil }
                return ExportManager.pdfData(from: image.cgImage)
            })
    }
}

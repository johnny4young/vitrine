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
        try? encodedPayloadChecked(for: draft, format: format, profile: profile)
    }

    static func encodedPayloadChecked(
        for draft: ComparisonBoardDraft,
        format: ExportFormat,
        profile: ColorProfile
    ) throws(RenderBudgetError) -> (data: Data, type: UTType, ext: String) {
        let asset: RenderedAsset
        do {
            asset = try draft.compose(scale: draft.exportScale, profile: profile)
        } catch ComparisonBoardComposer.CompositionError.renderFailure(let error) {
            throw error
        } catch {
            throw .allocationFailed
        }

        if case .pdf = format {
            guard let data = ExportManager.pdfData(from: asset.cgImage) else {
                throw .encodingFailed
            }
            return (data, .pdf, "pdf")
        }
        guard let data = ExportManager.rasterData(from: asset.cgImage, format: format),
            let metadata = ExportManager.rasterMetadata(for: format)
        else {
            throw .encodingFailed
        }
        return (data, metadata.type, metadata.ext)
    }
}

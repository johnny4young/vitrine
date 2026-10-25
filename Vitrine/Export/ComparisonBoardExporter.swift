import Foundation
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// Encodes a board through the shared export formats at the scale captured by its draft.
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

        return try ExportManager.encodedPayloadChecked(
            format,
            raster: { asset.cgImage },
            pdf: { ExportManager.pdfData(from: asset.cgImage, scale: draft.exportScale) })
    }
}

import Foundation
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// Encodes a board through the shared export formats at the scale captured by its draft.
enum ComparisonBoardExporter {
    static func encodedPayloadChecked(
        for draft: ComparisonBoardDraft,
        format: ExportFormat,
        profile: ColorProfile
    ) throws(RenderBudgetError) -> (data: Data, type: UTType, ext: String) {
        guard format.isEncodingAvailable else { throw .encodingFailed }
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

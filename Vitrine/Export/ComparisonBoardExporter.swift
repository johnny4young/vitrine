import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// Encodes a board through the shared export formats at the scale its draft resolves.
enum ComparisonBoardExporter {
    static func encodedPayloadChecked(
        for draft: ComparisonBoardDraft,
        format: ExportFormat,
        profile: ColorProfile
    ) throws(RenderBudgetError) -> (data: Data, type: UTType, ext: String) {
        guard format.isEncodingAvailable else { throw .encodingFailed }
        let scale = draft.resolvedExportScale
        let asset = try composed(draft, profile: profile)

        return try ExportManager.encodedPayloadChecked(
            format,
            raster: { asset.cgImage },
            pdf: { ExportManager.pdfData(from: asset.cgImage, scale: scale) })
    }

    /// Crops each scene from one composition of the board, so a scene holds only pixels the
    /// board export has, with its redactions.
    static func sceneImagesChecked(
        for draft: ComparisonBoardDraft, profile: ColorProfile
    ) throws(RenderBudgetError) -> [CGImage] {
        guard !draft.scenes.isEmpty else { return [] }
        let board = try composed(draft, profile: profile).cgImage
        var images: [CGImage] = []
        for scene in draft.scenes {
            let rect = scene.viewport.pixelRect(width: board.width, height: board.height)
            guard let image = board.cropping(to: rect) else { throw .allocationFailed }
            images.append(image)
        }
        return images
    }

    /// One page per scene, each made by the board's single-image PDF writer and joined.
    static func scenePDFChecked(
        for draft: ComparisonBoardDraft, profile: ColorProfile
    ) throws(RenderBudgetError) -> Data {
        let images = try sceneImagesChecked(for: draft, profile: profile)
        let data = NSMutableData()
        guard !images.isEmpty, let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw .encodingFailed }
        for image in images {
            guard
                let page = ExportManager.pdfData(from: image, scale: draft.resolvedExportScale),
                let provider = CGDataProvider(data: page as CFData),
                let document = CGPDFDocument(provider), let first = document.page(at: 1)
            else { throw .encodingFailed }
            var mediaBox = first.getBoxRect(.mediaBox)
            context.beginPage(mediaBox: &mediaBox)
            context.drawPDFPage(first)
            context.endPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Writes `scene-01.png` and on into `directory` without replacing any file there.
    static func writeScenePNGs(
        for draft: ComparisonBoardDraft, profile: ColorProfile, to directory: URL,
        writeFile: (Data, URL) throws -> Void = { try BatchOutputFiles.publish($0, to: $1) }
    ) throws -> Int {
        let images = try sceneImagesChecked(for: draft, profile: profile)
        let outputs = try BatchOutputFiles.plan(
            filenames: images.indices.map { String(format: "scene-%02d.png", $0 + 1) },
            in: directory)
        for (image, output) in zip(images, outputs) {
            guard let data = ExportManager.rasterData(from: image, format: .png) else {
                throw RenderBudgetError.encodingFailed
            }
            try writeFile(data, output.image)
        }
        return images.count
    }

    private static func composed(
        _ draft: ComparisonBoardDraft, profile: ColorProfile
    ) throws(RenderBudgetError) -> RenderedAsset {
        do {
            return try draft.compose(scale: draft.resolvedExportScale, profile: profile)
        } catch ComparisonBoardComposer.CompositionError.renderFailure(let error) {
            throw error
        } catch {
            throw .allocationFailed
        }
    }
}

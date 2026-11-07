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

    /// One page per scene, sized in points like the single-board PDF.
    static func scenePDFChecked(
        for draft: ComparisonBoardDraft, profile: ColorProfile
    ) throws(RenderBudgetError) -> Data {
        let images = try sceneImagesChecked(for: draft, profile: profile)
        let scale = draft.resolvedExportScale
        let data = NSMutableData()
        guard !images.isEmpty, let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: nil, nil)
        else { throw .encodingFailed }
        for image in images {
            var mediaBox = CGRect(
                x: 0, y: 0, width: CGFloat(image.width) / scale,
                height: CGFloat(image.height) / scale)
            context.beginPage(mediaBox: &mediaBox)
            context.draw(image, in: mediaBox)
            context.endPage()
        }
        context.closePDF()
        return data as Data
    }

    /// Writes `scene-01.png` and on into `directory` without replacing any file there. The
    /// board is cropped on the main actor; each encode and write runs off it, and a failed
    /// scene doesn't stop the rest.
    static func exportScenePNGs(
        for draft: ComparisonBoardDraft, profile: ColorProfile, to directory: URL,
        onProgress: ((_ completed: Int, _ total: Int) -> Void)? = nil,
        writeFile: @escaping @Sendable (Data, URL) throws -> Void = {
            try BatchOutputFiles.publish($0, to: $1)
        }
    ) async -> ExportManager.BatchExportResult {
        let total = draft.scenes.count
        let images: [CGImage]
        let outputs: [BatchOutputFiles.Item]
        do throws(RenderBudgetError) {
            images = try sceneImagesChecked(for: draft, profile: profile)
        } catch let error {
            return .init(written: 0, failed: total, firstRenderFailure: error)
        }
        do {
            outputs = try BatchOutputFiles.plan(
                filenames: images.indices.map { String(format: "scene-%02d.png", $0 + 1) },
                in: directory)
        } catch {
            return .init(written: 0, failed: total, firstRenderFailure: nil)
        }
        var written = 0
        for (index, (image, output)) in zip(images, outputs).enumerated() {
            if !Task.isCancelled, await writeScene(image, to: output.image, writeFile) {
                written += 1
            }
            onProgress?(index + 1, total)
        }
        return .init(written: written, failed: total - written, firstRenderFailure: nil)
    }

    @concurrent nonisolated private static func writeScene(
        _ image: CGImage, to url: URL, _ writeFile: @Sendable (Data, URL) throws -> Void
    ) async -> Bool {
        guard let data = ExportManager.rasterData(from: image, format: .png) else { return false }
        return (try? writeFile(data, url)) != nil
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

import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("Comparison board preview")
struct ComparisonBoardPreviewTests {
    @Test func invalidInputSkipsRendering() async {
        let preview = ComparisonBoardPreview()
        var renderCount = 0

        await preview.refresh(isValid: false, debounce: .zero) {
            renderCount += 1
            return asset()
        }

        #expect(preview.phase == .invalid)
        #expect(preview.asset == nil)
        #expect(renderCount == 0)
    }

    @Test func successfulRenderBecomesReady() async {
        let preview = ComparisonBoardPreview()

        await preview.refresh(isValid: true, debounce: .zero) { asset() }

        #expect(preview.phase == .ready)
        #expect(preview.asset?.pixelSize == CGSize(width: 32, height: 18))
    }

    @Test func renderFailureDoesNotLeaveAnInfiniteLoadingState() async {
        enum Failure: Error { case expected }
        let preview = ComparisonBoardPreview()

        await preview.refresh(isValid: true, debounce: .zero) {
            throw Failure.expected
        }

        #expect(preview.phase == .failed)
        #expect(preview.asset == nil)
    }

    @Test func captionFramesArriveWithTheirAsset() async {
        let preview = ComparisonBoardPreview()
        let id = UUID()
        let frame = CGRect(x: 1, y: 2, width: 3, height: 4)

        await preview.refresh(
            isValid: true, debounce: .zero, captionFrames: { [id: frame] },
            render: { asset() })

        #expect(preview.captionFrames == [id: frame])
    }

    @Test func invalidInputKeepsTheLastFrameOnlyWhileACaptionIsBeingEdited() async {
        let preview = ComparisonBoardPreview()
        let id = UUID()
        let frames = [id: CGRect(x: 1, y: 2, width: 3, height: 4)]
        await preview.refresh(
            isValid: true, debounce: .zero, captionFrames: { frames },
            render: { asset() })

        await preview.refresh(isValid: false, keepsLastFrame: true, debounce: .zero) { asset() }
        #expect(preview.phase == .invalid)
        #expect(preview.asset != nil)
        #expect(preview.captionFrames == frames)

        await preview.refresh(isValid: false, debounce: .zero) { asset() }
        #expect(preview.asset == nil)
        #expect(preview.captionFrames.isEmpty)
    }

    @Test func renderFailureDropsTheCaptionFrames() async {
        enum Failure: Error { case expected }
        let preview = ComparisonBoardPreview()
        await preview.refresh(
            isValid: true, debounce: .zero, captionFrames: { [UUID(): .zero] },
            render: { asset() })

        await preview.refresh(isValid: true, debounce: .zero) { throw Failure.expected }

        #expect(preview.captionFrames.isEmpty)
    }

    private func asset() -> RenderedAsset {
        let context = CGContext(
            data: nil,
            width: 32,
            height: 18,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return RenderedAsset(cgImage: context.makeImage()!, profile: .sRGB)
    }
}

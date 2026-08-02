import CoreGraphics
import Testing

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

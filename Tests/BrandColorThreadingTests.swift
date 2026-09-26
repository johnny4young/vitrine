import AppKit
import Testing

@testable import VitrineRendering

@Suite("Brand color threading")
struct BrandColorThreadingTests {
    /// SwiftUI's display-link renderer resolves dynamic colors off the main thread.
    @Test func dynamicBrandColorsResolveOffTheMainThread() async {
        let accent = Brand.Palette.accent.nsColor
        let resolved = await Task.detached {
            (offMain: pthread_main_np() == 0, color: accent.usingColorSpace(.sRGB))
        }.value
        #expect(resolved.offMain)
        #expect(resolved.color != nil)
    }
}

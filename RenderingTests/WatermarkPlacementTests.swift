import SwiftUI
import Testing

@testable import VitrineRendering

@MainActor
@Suite("Watermark placement")
struct WatermarkPlacementTests {
    @Test func everyPlacementHasALabelAndAlignment() {
        for placement in Watermark.Placement.allCases {
            #expect(!placement.label.isEmpty)
        }
        // The four corner placements map to a real corner alignment; `.free` has no
        // corner anchor — it is positioned by `freePosition`, so `.center` is just its
        // exhaustive fallback.
        for placement in Watermark.Placement.allCases where placement != .free {
            #expect(placement.alignment != .center)
        }
    }

}

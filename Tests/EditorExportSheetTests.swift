import Testing

@testable import Vitrine

@Suite("Editor export presentation routing")
struct EditorExportSheetTests {
    @Test func unlockedFeaturesRouteToTheirExportSurface() {
        #expect(EditorExportSheet.multiSize(isUnlocked: true) == .multiSizeExport)
        #expect(EditorExportSheet.carousel(isUnlocked: true) == .carouselExport)
    }

    @Test func lockedFeaturesRouteToTheirOwnPaywall() {
        #expect(EditorExportSheet.multiSize(isUnlocked: false) == .multiSizePaywall)
        #expect(EditorExportSheet.carousel(isUnlocked: false) == .carouselPaywall)
    }

    @Test func everyDestinationHasAStableDistinctIdentity() {
        let destinations: [EditorExportSheet] = [
            .multiSizeExport,
            .multiSizePaywall,
            .carouselExport,
            .carouselPaywall,
        ]

        #expect(Set(destinations.map(\.id)).count == destinations.count)
    }
}

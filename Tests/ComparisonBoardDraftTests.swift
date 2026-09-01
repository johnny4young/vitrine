import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Comparison board draft")
struct ComparisonBoardDraftTests {
    @Test func rejectsSelectionsOutsideTheSupportedRange() {
        #expect(throws: ComparisonBoardDraft.CreationError.invalidSelection(1)) {
            try makeDraft(captures: [capture("only")])
        }
        #expect(throws: ComparisonBoardDraft.CreationError.invalidSelection(5)) {
            try makeDraft(captures: (1...5).map { capture("\($0)") })
        }
    }

    @Test func renderingFailureIdentifiesTheCapturePosition() {
        let captures = [capture("before"), capture("after")]
        func render(
            _ config: SnapshotConfig,
            _ scale: CGFloat,
            _ profile: ColorProfile
        ) throws(RenderBudgetError) -> CGImage {
            _ = scale
            _ = profile
            guard config.code == "before" else { throw .allocationFailed }
            return solidImage()
        }

        #expect(
            throws: ComparisonBoardDraft.CreationError.renderFailure(
                index: 1, .allocationFailed)
        ) {
            try ComparisonBoardDraft(
                captures: captures,
                baseConfig: SnapshotConfig(),
                profile: .sRGB,
                render: render)
        }
    }

    @Test func rejectsUnsupportedSourceRenderScales() {
        #expect(throws: ComparisonBoardDraft.CreationError.invalidRenderScale(0)) {
            try ComparisonBoardDraft(
                captures: [capture("before"), capture("after")],
                baseConfig: SnapshotConfig(),
                profile: .sRGB,
                renderScale: 0,
                render: { _, _, _ in solidImage() })
        }
    }

    @Test func createsUsefulDefaultsAndRendersEachCaptureOnce() throws {
        let captures = [
            capture("old", language: .swift, theme: .oneDark),
            capture("new", language: .python, theme: .dracula),
        ]
        var renderedCodes: [String] = []
        var renderedScales: [CGFloat] = []

        let draft = try ComparisonBoardDraft(
            captures: captures,
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            renderScale: 2,
            render: { config, scale, _ in
                renderedCodes.append(config.code)
                renderedScales.append(scale)
                return solidImage()
            })

        #expect(renderedCodes == ["old", "new"])
        #expect(renderedScales == [2, 2])
        #expect(Set(draft.items.map(\.id)).count == captures.count)
        #expect(Set(draft.items.map(\.id)).isDisjoint(with: captures.map(\.id)))
        #expect(draft.items.map(\.label) == ["Before", "After"])
        #expect(draft.exportScale == 2)
        #expect(draft.items[0].detail.contains(captures[0].language.displayName))
        #expect(draft.items[1].detail.contains(captures[1].theme.displayName))
    }

    @Test func threeCaptureDefaultsRemainOrderedAndDescriptive() throws {
        let captures = [capture("one"), capture("two"), capture("three")]
        let draft = try makeDraft(captures: captures)

        #expect(draft.items.map(\.label) == ["Capture 1", "Capture 2", "Capture 3"])
    }

    @Test func reordersWithinBounds() throws {
        let captures = [capture("one"), capture("two"), capture("three")]
        let draft = try makeDraft(captures: captures)
        let originalOrder = draft.items.map(\.id)

        draft.moveItem(id: originalOrder[0], offset: -1)
        draft.moveItem(id: originalOrder[2], offset: 1)
        #expect(draft.items.map(\.id) == originalOrder)

        draft.moveItem(id: originalOrder[0], offset: 1)
        #expect(draft.items.map(\.id) == [originalOrder[1], originalOrder[0], originalOrder[2]])
    }

    @Test func previewKeyTracksIdentityOrderAndColorProfile() throws {
        let captures = [capture("one"), capture("two")]
        let draft = try makeDraft(captures: captures)
        draft.items[0].label = "Same"
        draft.items[1].label = "Same"
        draft.items[0].detail = ""
        draft.items[1].detail = ""
        let initial = draft.previewKey(profile: .sRGB)
        let firstID = draft.items[0].id

        draft.moveItem(id: firstID, offset: 1)

        #expect(draft.previewKey(profile: .sRGB) != initial)
        #expect(draft.previewKey(profile: .displayP3) != draft.previewKey(profile: .sRGB))
    }

    @Test func retainsTheMinimumPairWhenRemoving() throws {
        let captures = [capture("one"), capture("two"), capture("three")]
        let draft = try makeDraft(captures: captures)
        let originalOrder = draft.items.map(\.id)

        draft.removeItem(id: originalOrder[1])
        #expect(draft.items.map(\.id) == [originalOrder[0], originalOrder[2]])
        draft.removeItem(id: originalOrder[0])
        #expect(draft.items.map(\.id) == [originalOrder[0], originalOrder[2]])
    }

    @Test func boardReflectsCaptionAndLayoutEdits() throws {
        let draft = try makeDraft(captures: [capture("one"), capture("two")])
        draft.layout = .vertical
        draft.items[0].label = "Original"
        draft.items[1].detail = "Refined output"

        let board = try draft.board()

        #expect(board.layout == .vertical)
        #expect(board.items.map(\.label) == ["Original", "After"])
        #expect(board.items[1].detail == "Refined output")
    }

    @Test func invalidCaptionsDisablePreviewAndExport() throws {
        let draft = try makeDraft(captures: [capture("one"), capture("two")])

        draft.items[0].label = "   "

        #expect(!draft.isValid)
        #expect(throws: ComparisonBoard.ValidationError.emptyLabel(index: 0)) {
            try draft.board()
        }
    }

    @Test func composeUsesTheRequestedScaleAndProfile() throws {
        let draft = try makeDraft(captures: [capture("one"), capture("two")])

        let oneX = try draft.compose(scale: 1, profile: .sRGB)
        let twoX = try draft.compose(scale: 2, profile: .displayP3)

        #expect(twoX.pixelWidth == oneX.pixelWidth * 2)
        #expect(twoX.pixelHeight == oneX.pixelHeight * 2)
        #expect(twoX.profile == .displayP3)
    }

    private func makeDraft(captures: [Capture]) throws -> ComparisonBoardDraft {
        try ComparisonBoardDraft(
            captures: captures,
            baseConfig: SnapshotConfig(),
            profile: .sRGB,
            render: { _, _, _ in solidImage() })
    }

    private func capture(
        _ code: String,
        language: Language = .swift,
        theme: Theme = .oneDark
    ) -> Capture {
        Capture(code: code, languageID: language.rawValue, themeID: theme.id)
    }

    private func solidImage(width: Int = 320, height: Int = 180) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

@MainActor
@Suite("Comparison board selection")
struct ComparisonBoardSelectionTests {
    @Test func selectionIsOrderedToggleableAndCapped() {
        let captures = (1...5).map {
            Capture(code: "\($0)", languageID: "swift", themeID: "one-dark")
        }
        var selection = ComparisonBoardSelection()

        for capture in captures {
            selection.toggle(capture.id)
        }

        #expect(selection.count == 4)
        #expect(selection.resolved(in: captures).map(\.id) == Array(captures.prefix(4)).map(\.id))
        #expect(selection.index(of: captures[2].id) == 2)
        #expect(selection.canCreateBoard)

        selection.toggle(captures[1].id)
        #expect(
            selection.resolved(in: captures).map(\.id) == [
                captures[0].id, captures[2].id, captures[3].id,
            ])
    }

    @Test func resetAndMissingCapturesDoNotLeakStaleReferences() {
        let first = Capture(code: "one", languageID: "swift", themeID: "one-dark")
        let second = Capture(code: "two", languageID: "swift", themeID: "one-dark")
        var selection = ComparisonBoardSelection()
        selection.toggle(first.id)
        selection.toggle(second.id)

        #expect(selection.resolved(in: [second]).map(\.id) == [second.id])

        selection.reset()
        #expect(selection.ids.isEmpty)
        #expect(!selection.canCreateBoard)
    }
}

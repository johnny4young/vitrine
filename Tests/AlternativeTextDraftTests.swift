import Testing
import VitrineDomain

@testable import Vitrine

@MainActor @Suite("Content-bound alternative text editing")
struct AlternativeTextDraftTests {
    @Test func typingKeepsSpacesAndAnAcceptedDescriptionAcrossOrdinaryCodeEdits() throws {
        var draft = AlternativeTextDraft()
        let value = try draft.update("  Two words ")
        draft.synchronize(value)
        draft.contentChanged(value)
        #expect(draft.input == "  Two words ")
        #expect(value?.text == "Two words")
        #expect(!draft.rejected)
    }

    @Test func replacementClearsRejectedInputEvenWhenTheModelWasAlreadyNil() throws {
        var draft = AlternativeTextDraft()
        #expect(throws: SnapshotAltText.ValidationError.tooLong) {
            try draft.update(String(repeating: "x", count: 1_025))
        }
        #expect(draft.rejected)
        draft.contentChanged(nil)
        #expect(draft.input.isEmpty)
        #expect(!draft.rejected)
    }

    @Test func failedInputRestoresOnlyItsOwnLastAcceptedValue() throws {
        let accepted = try SnapshotAltText.normalized("This document")
        var draft = AlternativeTextDraft()
        draft.restore(accepted)
        #expect(throws: SnapshotAltText.ValidationError.tooLong) {
            try draft.update(String(repeating: "x", count: 1_025))
        }
        draft.contentChanged(accepted)
        #expect(draft.input == "This document")
        #expect(!draft.rejected)
        draft.synchronize(nil)
        #expect(draft.input.isEmpty)
    }

    @Test func draftsAreIndependentAndBlankInputDoesNotTravelToNewContent() throws {
        var first = AlternativeTextDraft()
        var second = AlternativeTextDraft()
        _ = try first.update("First window")
        _ = try second.update("  ")
        second.contentChanged(nil)
        #expect(second.input.isEmpty)
        #expect(first.input == "First window")
    }
}

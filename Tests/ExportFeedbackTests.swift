import Testing

@testable import Vitrine

@MainActor
@Suite("Export feedback mapping")
struct ExportFeedbackTests {
    @Test func mapsImageCopyOutcomes() {
        #expect(
            ExportFeedback.copyOutcome(true)
                == Notifier.confirmation(String(localized: "Image copied to clipboard")))
        #expect(
            ExportFeedback.copyOutcome(false)
                == Notifier.failure(String(localized: "Couldn't copy the image")))
    }

    @Test func mapsSourceCopyOutcomesWithoutCallingTheSourceAnImage() {
        #expect(
            ExportFeedback.sourceCopyOutcome(true)
                == Notifier.confirmation(String(localized: "Source copied to clipboard")))
        #expect(
            ExportFeedback.sourceCopyOutcome(false)
                == Notifier.failure(String(localized: "Couldn't copy the source")))
    }

    @Test func keepsCancelledSavesSilent() {
        #expect(
            ExportFeedback.saveOutcome(.saved)
                == Notifier.confirmation(String(localized: "Image saved")))
        #expect(
            ExportFeedback.saveOutcome(.failed)
                == Notifier.failure(String(localized: "Couldn't save the image")))
        #expect(ExportFeedback.saveOutcome(.cancelled) == nil)
    }

    @Test func mapsShareFailure() {
        #expect(
            ExportFeedback.shareFailure
                == Notifier.failure(String(localized: "Couldn't share the image")))
    }
}

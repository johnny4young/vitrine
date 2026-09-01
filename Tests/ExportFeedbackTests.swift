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
        #expect(
            ExportFeedback.copyOutcome(
                .renderFailed(.tooLarge(.arithmeticOverflow)))
                == Notifier.failure(
                    String(
                        localized:
                            "The image is too large to render safely. Reduce the canvas size or scale."
                    )))
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
        #expect(
            ExportFeedback.saveOutcome(.renderFailed(.allocationFailed))
                == Notifier.failure(
                    String(
                        localized:
                            "Vitrine couldn't allocate the image buffer. Reduce the canvas size or scale and try again."
                    )))
        #expect(ExportFeedback.saveOutcome(.cancelled) == nil)
    }

    @Test func mapsShareFailure() {
        #expect(
            ExportFeedback.shareFailure
                == Notifier.failure(String(localized: "Couldn't share the image")))
    }
}

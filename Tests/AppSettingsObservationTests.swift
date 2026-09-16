import Foundation
import Observation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

private nonisolated final class InvalidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() {
        lock.withLock { value = true }
    }

    var isMarked: Bool {
        lock.withLock { value }
    }
}

@Suite("App settings observation boundaries")
struct AppSettingsObservationTests {
    private func settings() -> AppSettings {
        AppSettings(defaults: testDefaults())
    }

    @Test func documentTextDoesNotInvalidateRenderConfigurationObservers() {
        let settings = settings()
        let invalidated = InvalidationProbe()

        withObservationTracking {
            _ = settings.renderConfiguration
        } onChange: {
            invalidated.mark()
        }

        settings.config.code = "let answer = 42"

        #expect(!invalidated.isMarked)
        #expect(settings.documentCode == "let answer = 42")
        #expect(settings.renderConfiguration.code.isEmpty)
    }

    @Test func renderConfigurationStillPublishesPresentationChanges() {
        let settings = settings()
        let invalidated = InvalidationProbe()

        withObservationTracking {
            _ = settings.renderConfiguration
        } onChange: {
            invalidated.mark()
        }

        settings.config.padding = 48

        #expect(invalidated.isMarked)
        #expect(settings.renderConfiguration.padding == 48)
    }

    @Test func presentationChangesDoNotInvalidateDocumentTextObservers() {
        let settings = settings()
        let invalidated = InvalidationProbe()

        withObservationTracking {
            _ = settings.documentCode
        } onChange: {
            invalidated.mark()
        }

        settings.config.theme = .dracula

        #expect(!invalidated.isMarked)
        #expect(settings.documentCode.isEmpty)
    }

    @Test func configFacadeRoundTripsDocumentAndRenderInputs() {
        let settings = settings()
        var replacement = SnapshotConfig()
        replacement.code = "print(\"hello\")"
        replacement.theme = .dracula
        replacement.padding = 56

        settings.config = replacement

        #expect(settings.documentCode == replacement.code)
        #expect(settings.renderConfiguration.code.isEmpty)
        #expect(settings.renderConfiguration.theme.id == Theme.dracula.id)
        #expect(settings.renderConfiguration.padding == 56)
        #expect(settings.config == replacement)
    }

    @Test func documentTextDoesNotInvalidateStyleObservers() {
        let settings = settings()
        let invalidated = InvalidationProbe()

        withObservationTracking {
            _ = settings.style.padding
        } onChange: {
            invalidated.mark()
        }

        settings.documentCode = "let answer = 42"

        #expect(!invalidated.isMarked)
    }

    @Test func styleWritesChangeRenderInputsAndLeaveTheDocumentAlone() {
        let settings = settings()
        settings.documentCode = "print(\"kept\")"
        let invalidated = InvalidationProbe()
        withObservationTracking {
            _ = settings.style
        } onChange: {
            invalidated.mark()
        }

        var style = settings.style
        style.padding = 40
        style.code = "ignored"
        settings.style = style

        #expect(invalidated.isMarked)
        #expect(settings.renderConfiguration.padding == 40)
        #expect(settings.style.code.isEmpty)
        #expect(settings.documentCode == "print(\"kept\")")
    }

    /// A keystroke that leaves the document non-empty must not reach a view that only
    /// asks whether there is any code.
    @Test func documentEmptinessInvalidatesOnlyWhenTheAnswerChanges() {
        let settings = settings()
        #expect(settings.documentIsEmpty)

        func typing(_ text: String) -> Bool {
            let invalidated = InvalidationProbe()
            withObservationTracking {
                _ = settings.documentIsEmpty
                _ = settings.hasRenderableContent
            } onChange: {
                invalidated.mark()
            }
            settings.documentCode = text
            return invalidated.isMarked
        }

        #expect(typing("l"))
        #expect(!settings.documentIsEmpty)
        #expect(!typing("le"))
        #expect(!typing("let"))
        #expect(typing(""))
        #expect(settings.documentIsEmpty)
    }

    @Test func renderableContentMatchesTheCompleteConfiguration() {
        let settings = settings()
        #expect(settings.hasRenderableContent == settings.config.hasRenderableContent)

        settings.documentCode = "x"
        #expect(settings.hasRenderableContent == settings.config.hasRenderableContent)

        settings.documentCode = ""
        settings.style.foregroundImage = ImageReference(fileName: "capture.png")
        #expect(settings.hasRenderableContent)
        #expect(settings.hasRenderableContent == settings.config.hasRenderableContent)
    }

    /// Restoration, hand-off, and a new window's copy of the default all load a whole
    /// configuration at once, so emptiness has to follow the `config` setter too.
    @Test func loadingAWholeConfigurationUpdatesDocumentEmptiness() {
        let settings = settings()

        settings.config = SnapshotConfig(code: "print(\"loaded\")", language: .swift)
        #expect(!settings.documentIsEmpty)

        settings.config = SnapshotConfig()
        #expect(settings.documentIsEmpty)
    }
}

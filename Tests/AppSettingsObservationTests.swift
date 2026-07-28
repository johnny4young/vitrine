import Foundation
import Observation
import Testing

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
        let name = "AppSettingsObservationTests-\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: name)!)
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
}

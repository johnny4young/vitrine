import Foundation
import Testing

@testable import Vitrine

@Suite("Image operation ownership", .timeLimit(.minutes(1)))
struct ImageProcessingControllerTests {
    private enum Failure: Error { case recognition }

    @Test func successfulWorkPublishesOnceAndClearsProgress() async {
        let controller = ImageProcessingController()
        var values: [String] = []
        let task = controller.start(
            .copyText, work: { "recognized" },
            publish: {
                values.append($0)
            }, onFailure: { _ in Issue.record("Unexpected error") })
        #expect(controller.operation == .copyText)
        await task.value
        #expect(values == ["recognized"])
        #expect(!controller.isProcessing)
    }

    @Test func currentFailureIsReportedAndClearsProgress() async {
        let controller = ImageProcessingController()
        await confirmation("Recognition failure is reported once") { reported in
            let task = controller.start(
                .redactSecrets,
                work: { () throws -> String in
                    throw Failure.recognition
                }, publish: { _ in Issue.record("Failed work published") },
                onFailure: { error in
                    #expect(error is Failure)
                    reported()
                })
            await task.value
        }
        #expect(!controller.isProcessing)
    }

    @Test(arguments: [false, true])
    func replacedWorkCannotPublishOrClearTheNewOperation(fails: Bool) async {
        let controller = ImageProcessingController()
        let old = SuspendedImageWork<String>()
        let new = SuspendedImageWork<String>()
        var values: [String] = []
        let first = controller.start(
            .copyText, work: { try await old.run() },
            publish: {
                values.append($0)
            }, onFailure: { _ in Issue.record("Replaced error was shown") })
        await old.waitUntilStarted()
        let second = controller.start(
            .redactSecrets, work: { try await new.run() },
            publish: {
                values.append($0)
            }, onFailure: { _ in Issue.record("Unexpected new error") })
        await new.waitUntilStarted()
        old.complete(fails ? .failure(Failure.recognition) : .success("stale"))
        await first.value
        #expect(values.isEmpty)
        #expect(controller.operation == .redactSecrets)
        new.complete(.success("current"))
        await second.value
        #expect(values == ["current"])
        #expect(!controller.isProcessing)
    }

    @Test(arguments: [false, true])
    func cancellationClearsProgressBeforeUncooperativeWorkFinishes(fails: Bool) async {
        let controller = ImageProcessingController()
        let work = SuspendedImageWork<String>()
        let task = controller.start(
            .copyText, work: { try await work.run() },
            publish: { _ in
                Issue.record("Cancelled work published")
            }, onFailure: { _ in Issue.record("Cancelled error was shown") })
        await work.waitUntilStarted()
        controller.cancel()
        #expect(!controller.isProcessing)
        work.complete(fails ? .failure(Failure.recognition) : .success("cancelled"))
        await task.value
        #expect(!controller.isProcessing)
    }

    @Test func cancellationBeforeTaskStartsDoesNotRunTheRecognizer() async {
        let controller = ImageProcessingController()
        let task = controller.start(
            .copyText,
            work: {
                Issue.record("Cancelled job started expensive work")
            }, publish: { _ in Issue.record("Cancelled job published") },
            onFailure: { _ in
                Issue.record("Cancelled job failed")
            })
        controller.cancel()
        await task.value
        #expect(!controller.isProcessing)
    }

    @Test func aRecognizerCancellationIsSilentAndReleasesOwnership() async {
        let controller = ImageProcessingController()
        let task = controller.start(
            .copyText,
            work: { () throws -> String in
                throw CancellationError()
            }, publish: { _ in Issue.record("Cancelled recognizer published") },
            onFailure: { _ in
                Issue.record("Cancellation was shown as an error")
            })
        await task.value
        #expect(!controller.isProcessing)
    }

    @Test func taskDoesNotRetainItsEditorOwnerWhileSuspended() async {
        var controller: ImageProcessingController? = ImageProcessingController()
        weak let owner = controller
        let work = SuspendedImageWork<String>()
        let task = controller?.start(
            .copyText, work: { try await work.run() },
            publish: { _ in
                Issue.record("Closed editor received a result")
            }, onFailure: { _ in Issue.record("Closed editor received an error") })
        await work.waitUntilStarted()
        controller = nil
        #expect(owner == nil)
        work.complete(.success("late"))
        await task?.value
    }

    @Test func publishingCanStartAReplacementWithoutOldCleanupClearingIt() async {
        let controller = ImageProcessingController()
        let replacement = SuspendedImageWork<String>()
        var second: Task<Void, Never>?
        let first = controller.start(
            .copyText, work: { "first" },
            publish: { _ in
                second = controller.start(
                    .redactSecrets, work: { try await replacement.run() }, publish: { _ in },
                    onFailure: { _ in
                        Issue.record("Replacement unexpectedly failed")
                    })
            }, onFailure: { _ in Issue.record("Initial work unexpectedly failed") })
        await first.value
        await replacement.waitUntilStarted()
        #expect(controller.operation == .redactSecrets)
        replacement.complete(.success("second"))
        await second?.value
        #expect(!controller.isProcessing)
    }

    #if DEBUG
        @Test func pendingFixtureRequiresAnExplicitIsolatedLaunch() {
            #expect(!ManagedImageUITestFixture.isRequested(environment: [:]))
            #expect(
                !ManagedImageUITestFixture.isRequested(environment: [
                    "VITRINE_MANAGED_IMAGE_UI_TEST": "pending"
                ]))
            #expect(
                !ManagedImageUITestFixture.isRequested(environment: [
                    "VITRINE_MANAGED_IMAGE_UI_TEST": "pending",
                    "VITRINE_USER_DEFAULTS_SUITE": " \n",
                ]))
            #expect(
                !ManagedImageUITestFixture.isRequested(environment: [
                    "VITRINE_MANAGED_IMAGE_UI_TEST": "unknown",
                    "VITRINE_USER_DEFAULTS_SUITE": "isolated",
                ]))
            #expect(
                ManagedImageUITestFixture.isRequested(environment: [
                    "VITRINE_MANAGED_IMAGE_UI_TEST": "pending",
                    "VITRINE_USER_DEFAULTS_SUITE": "isolated",
                ]))
        }

        @Test func pendingFixtureExitsWhenCancelled() async {
            let task = Task { try await ManagedImageUITestFixture.waitForCancellation() }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    #endif
}

/// Intentionally ignores cancellation, like an external recognizer may do. Tests
/// control arrival explicitly; no timing, polling, or arbitrary sleeps are needed.
private final class SuspendedImageWork<Value: Sendable> {
    private var result: CheckedContinuation<Value, Error>?
    private var start: CheckedContinuation<Void, Never>?
    private var didStart = false

    func run() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            result = continuation
            didStart = true
            start?.resume()
            start = nil
        }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { start = $0 }
    }

    func complete(_ value: Result<Value, Error>) {
        let continuation = result
        result = nil
        continuation?.resume(with: value)
    }
}

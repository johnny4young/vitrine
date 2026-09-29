#if DEBUG
    import Foundation

    /// A pending recognizer for deterministic progress/cancellation UI tests. It
    /// never changes recognition on a normal launch and is absent from Release.
    enum ManagedImageUITestFixture {
        nonisolated static func isRequested(environment: [String: String]) -> Bool {
            guard environment["VITRINE_MANAGED_IMAGE_UI_TEST"] == "pending",
                let suite = environment["VITRINE_USER_DEFAULTS_SUITE"]
            else { return false }
            return !suite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        nonisolated static func waitForCancellation() async throws {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            defer { continuation.finish() }
            var iterator = stream.makeAsyncIterator()
            _ = await iterator.next()
            try Task.checkCancellation()
        }
    }
#endif

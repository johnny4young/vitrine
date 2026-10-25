import Darwin
import Foundation
import MachO

private struct ProbeFailure: Error {
    let message: String
}

private final class Oracle {
    var checks = 0
    var cases: [String] = []

    func expect(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        checks += 1
        guard condition() else { throw ProbeFailure(message: label) }
    }

    func error<E: Error & Equatable>(
        _ expected: E, _ label: String, _ body: () async throws -> Void
    )
        async throws
    {
        var matches = false
        do { try await body() } catch { matches = (error as? E) == expected }
        try expect(matches, label)
    }

    func cancellation(_ label: String, _ body: () async throws -> Void) async throws {
        var matches = false
        do { try await body() } catch is CancellationError { matches = true } catch {}
        try expect(matches, label)
    }

    func completed(_ label: String) {
        cases.append(label)
    }

    func frameworkBoundary(_ phase: String) throws {
        let images = (0..<_dyld_image_count()).compactMap { index in
            _dyld_get_image_name(index).map { String(cString: $0) }
        }.filter { $0.contains("/WebKit.framework/") || $0.contains("/WebKitLegacy.framework/") }
        let receipt: [String: Any] = [
            "kind": "framework-boundary", "phase": phase, "webKitImages": images,
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        try expect(images.isEmpty, "WebKit framework loaded at \(phase)")
    }
}

@main
private struct WebRuleStoreProbe {
    static func main() async {
        do {
            let oracle = Oracle()
            try oracle.frameworkBoundary("before")
            try await waiterCases(oracle)
            #if INCLUDE_STORE_SELECTOR
                try selectorCases(oracle)
            #endif
            try oracle.frameworkBoundary("after")
            let receipt: [String: Any] = [
                "kind": "summary", "status": "passed", "checks": oracle.checks,
                "cases": oracle.cases, "frameworkBoundariesPassed": 2,
                "WebKitObjectsCreated": 0, "appHostLaunched": false,
            ]
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            let message = (error as? ProbeFailure)?.message ?? String(describing: type(of: error))
            print("Contract probe failed: \(message)")
            exit(1)
        }
    }

    private static func waiterCases(_ oracle: Oracle) async throws {
        let early = WebLoadWaiter()
        early.complete(.success(()))
        try await early.wait(timeout: .seconds(1))
        try await oracle.error(WebLoadWaiter.UsageError.alreadyCompleted, "early consumed once") {
            try await early.wait(timeout: .seconds(1))
        }
        oracle.completed("waiter-early-outcome")

        let first = WebLoadWaiter()
        first.complete(.failure(WebSnapshotError.loadFailed))
        first.complete(.success(()))
        try await oracle.error(WebSnapshotError.loadFailed, "first outcome wins") {
            try await first.wait(timeout: .seconds(1))
        }
        oracle.completed("waiter-first-outcome")

        let concurrent = WebLoadWaiter()
        var entered = false
        let pending = Task {
            entered = true
            try await concurrent.wait(timeout: .seconds(10))
        }
        defer { pending.cancel() }
        while !entered { await Task.yield() }
        try await oracle.error(WebLoadWaiter.UsageError.alreadyWaiting, "concurrent wait refused") {
            try await concurrent.wait(timeout: .seconds(1))
        }
        concurrent.complete(.success(()))
        try await pending.value
        oracle.completed("waiter-concurrent-rejection")

        let timed = WebLoadWaiter()
        try await oracle.error(WebSnapshotError.timedOut, "bounded timeout") {
            try await timed.wait(timeout: .milliseconds(2))
        }
        timed.complete(.success(()))
        try await oracle.error(WebLoadWaiter.UsageError.alreadyCompleted, "late result ignored") {
            try await timed.wait(timeout: .seconds(1))
        }
        oracle.completed("waiter-timeout")

        let cancelled = WebLoadWaiter()
        var waiting = false
        let task = Task {
            waiting = true
            try await cancelled.wait(timeout: .seconds(10))
        }
        defer { task.cancel() }
        while !waiting { await Task.yield() }
        try await oracle.error(
            WebLoadWaiter.UsageError.alreadyWaiting, "wait installed before cancel"
        ) {
            try await cancelled.wait(timeout: .seconds(1))
        }
        task.cancel()
        try await oracle.cancellation("pending cancellation") { try await task.value }
        cancelled.complete(.success(()))
        try await oracle.error(WebLoadWaiter.UsageError.alreadyCompleted, "cancel consumed once") {
            try await cancelled.wait(timeout: .seconds(1))
        }
        oracle.completed("waiter-pending-cancellation")

        let preCancelled = WebLoadWaiter()
        let preTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await preCancelled.wait(timeout: .seconds(10))
        }
        try await oracle.cancellation("pre-cancelled wait") { try await preTask.value }
        try await oracle.error(
            WebLoadWaiter.UsageError.alreadyCompleted, "pre-cancel consumed once"
        ) {
            try await preCancelled.wait(timeout: .seconds(1))
        }
        oracle.completed("waiter-pre-cancellation")
    }

    #if INCLUDE_STORE_SELECTOR
        private static func selectorCases(_ oracle: Oracle) throws {
            let defaultSource = WebContentRuleListStoreSource.applicationDefault
            var defaults = 0
            var directories = 0
            let defaultStore: String? = defaultSource.makeStore(
                applicationDefault: {
                    defaults += 1
                    return "application"
                },
                directory: { _ in
                    directories += 1
                    return "unexpected"
                })
            try oracle.expect(defaultStore == "application", "default store selected")
            try oracle.expect(defaults == 1 && directories == 0, "default factory called alone")
            try oracle.expect(defaultSource.usesSharedCache, "default cache preserved")
            oracle.completed("selector-default")

            let url = URL(filePath: "/tmp/synthetic-content-rules", directoryHint: .isDirectory)
            let owned = WebContentRuleListStoreSource.directory(url)
            var received: [URL] = []
            let custom: String? = owned.makeStore(
                applicationDefault: {
                    defaults += 1
                    return "unexpected"
                },
                directory: {
                    received.append($0)
                    return "owned"
                })
            try oracle.expect(custom == "owned" && received == [url], "exact owned URL forwarded")
            try oracle.expect(defaults == 1, "custom factory did not call default")
            try oracle.expect(!owned.usesSharedCache, "custom cache stays separate")
            oracle.completed("selector-directory")

            let absentDefault: String? = defaultSource.makeStore(
                applicationDefault: { nil },
                directory: { _ in
                    directories += 1
                    return "bad"
                })
            try oracle.expect(
                absentDefault == nil && directories == 0, "default failure no fallback")
            oracle.completed("selector-missing-default")

            let absentCustom: String? = owned.makeStore(
                applicationDefault: {
                    defaults += 1
                    return "bad"
                }, directory: { _ in nil })
            try oracle.expect(absentCustom == nil && defaults == 1, "directory failure no fallback")
            oracle.completed("selector-missing-directory")

            let invalid = [
                "https://example.invalid/rules", "file://remote.invalid/rules", "file:relative",
                "file:///tmp/rules?query", "file:///tmp/rules#fragment",
            ]
            for (index, value) in invalid.enumerated() {
                guard let invalidURL = URL(string: value) else {
                    throw ProbeFailure(message: "invalid URL fixture did not parse")
                }
                let source = WebContentRuleListStoreSource.directory(invalidURL)
                var calls = 0
                let result: String? = source.makeStore(
                    applicationDefault: {
                        calls += 1
                        return "bad"
                    },
                    directory: { _ in
                        calls += 1
                        return "bad"
                    })
                try oracle.expect(
                    result == nil && calls == 0, "invalid location rejected before factory")
                try oracle.expect(
                    !source.usesSharedCache, "invalid location cannot reuse default cache")
                oracle.completed("selector-invalid-\(index)")
            }
        }
    #endif
}

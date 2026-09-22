import Foundation
import Network
import Testing
import WebKit

@testable import Vitrine

/// Explicit integration lane: every request terminates at our loopback fixture,
/// including URLs that name other hosts. No system proxy or DNS settings change.
@MainActor
@Suite(
    "Controlled WebKit capture",
    .enabled(
        if: ProcessInfo.processInfo.environment["VITRINE_WEB_FIXTURE_PORT"].flatMap(UInt16.init)
            != nil))
struct WebCaptureIntegrationTests {
    private var port: UInt16 {
        get throws {
            try #require(
                ProcessInfo.processInfo.environment["VITRINE_WEB_FIXTURE_PORT"].flatMap(UInt16.init)
            )
        }
    }

    private func url(_ path: String) throws -> URL {
        try #require(URL(string: "http://127.0.0.1:\(try port)/\(path)"))
    }

    private func isolatedStore() throws -> WKWebsiteDataStore {
        let store = WKWebsiteDataStore.nonPersistent()
        var proxy = ProxyConfiguration(
            httpCONNECTProxy: .hostPort(
                host: .ipv4(.loopback), port: try #require(NWEndpoint.Port(rawValue: port))))
        proxy.allowFailover = false
        proxy.excludedDomains = []
        store.proxyConfigurations = [proxy]
        return store
    }

    private func config(_ path: String) throws -> WebSnapshotConfig {
        try WebSnapshotConfig(
            captureURL: url(path),
            viewportPreset: .custom(width: 320, height: 240), scale: 1, allowsLoopbackCapture: true)
    }

    private func events() async throws -> [[String: String]] {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url("ledger"))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        return try JSONDecoder().decode([[String: String]].self, from: data)
    }

    @Test func controlledRedirectProducesARealImage() async throws {
        let key = UUID().uuidString
        let image = try await URLSnapshotEngine(websiteDataStore: isolatedStore()).snapshot(
            of: config("redirect/\(key)"))
        #expect(image.width == 320)
        #expect(image.height == 240)
        let ledger = try await events()
        #expect(ledger.contains { $0["path"] == "/redirect/\(key)" })
        #expect(ledger.contains { $0["path"] == "/page/\(key)" })
    }

    @Test func privateRedirectFailsBeforeReachingTheDestination() async throws {
        let key = UUID().uuidString
        do {
            _ = try await URLSnapshotEngine(websiteDataStore: isolatedStore()).snapshot(
                of: config("private-redirect/\(key)"))
            Issue.record("Private redirect unexpectedly produced an image")
        } catch let error as WebSnapshotError {
            #expect(error == .loadFailed)
        }
        let ledger = try await events()
        #expect(ledger.contains { $0["path"] == "/private-redirect/\(key)" })
        #expect(!ledger.contains { $0["path"] == "/blocked/\(key)" })
    }

    @Test func privateResourcesAreBlockedWithAReachablePositiveControl() async throws {
        let control = UUID().uuidString
        // Deliberately unfiltered WebKit proves the fake private resources really
        // reach this non-forwarding fixture. It cannot reach an external host.
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = try isolatedStore()
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: configuration)
        let waiter = FixtureNavigation()
        view.navigationDelegate = waiter
        defer {
            view.stopLoading()
            view.navigationDelegate = nil
        }
        view.load(URLRequest(url: try url("resources/\(control)")))
        try await waiter.waiter.wait(timeout: .seconds(10))
        let before = try await events()
        for route in ["image", "style", "script", "frame"] {
            #expect(
                before.contains {
                    $0["path"] == "/\(route)/\(control)"
                        && $0["host"]?.hasPrefix("10.0.0.1:") == true
                })
        }

        let filtered = UUID().uuidString
        _ = try await URLSnapshotEngine(websiteDataStore: isolatedStore()).snapshot(
            of: config("resources/\(filtered)"))
        let after = try await events()
        #expect(
            after.contains {
                $0["path"] == "/image/\(filtered)" && $0["host"]?.hasPrefix("127.0.0.1:") == true
            })
        #expect(
            !after.contains {
                $0["path"]?.hasSuffix(filtered) == true
                    && $0["host"]?.hasPrefix("10.0.0.1:") == true
            })
    }

    @Test func loopbackSubresourcesRequireExplicitOptIn() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineWebAccess-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for allowed in [false, true] {
            let key = UUID().uuidString
            let file = directory.appendingPathComponent("\(key).html")
            let source = try url("image/\(key)").absoluteString
            try "<!doctype html><body><img src='\(source)'></body>".write(
                to: file, atomically: true, encoding: .utf8)
            var request = try WebSnapshotConfig(
                localFileURL: file,
                viewportPreset: .custom(width: 320, height: 240), scale: 1)
            request.allowsLoopbackCapture = allowed
            _ = try await URLSnapshotEngine(websiteDataStore: isolatedStore()).snapshot(of: request)
            let reached = try await events().contains { $0["path"] == "/image/\(key)" }
            #expect(reached == allowed)
        }
    }

    @Test func cancellationStopsAnActuallyPendingLoad() async throws {
        let key = UUID().uuidString
        let engine = URLSnapshotEngine(websiteDataStore: try isolatedStore())
        let request = try config("hold/\(key)")
        let task = Task { try await engine.snapshot(of: request) }
        defer { task.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(try await events()).contains(where: { $0["path"] == "/hold/\(key)" }) {
            try #require(
                ContinuousClock.now < deadline, "The fixture never received the pending load")
            try await Task.sleep(for: .milliseconds(20))
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled capture unexpectedly produced an image")
        } catch is CancellationError {
            // Expected; the request was observed before cancellation, not skipped.
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        _ = try await session.data(from: url("release/\(key)"))
        #expect(ContinuousClock.now < deadline)
    }

    @Test func pendingLoadHonorsItsTimeout() async throws {
        let key = UUID().uuidString
        var request = try config("hold/\(key)")
        // A cold WebKit process on the hosted Sequoia runner can consume a one-second
        // budget before dispatching any request. Keep the real-load assertion and use
        // the same startup allowance as the cancellation journey, not a blind sleep.
        // The unit waiter tests independently cover short timer expiration.
        request.safetyCaps.maxTimeout = .seconds(5)
        let started = ContinuousClock.now
        do {
            _ = try await URLSnapshotEngine(websiteDataStore: isolatedStore()).snapshot(of: request)
            Issue.record("Unreleased capture unexpectedly produced an image")
        } catch let error as WebSnapshotError {
            #expect(error == .timedOut)
        }
        let elapsed = started.duration(to: .now)
        #expect(elapsed >= request.safetyCaps.maxTimeout)
        #expect(elapsed < .seconds(10))
        #expect(try await events().contains { $0["path"] == "/hold/\(key)" })
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        _ = try await session.data(from: url("release/\(key)"))
    }

    @Test func realFullPageCaptureHonorsTheHeightCap() async throws {
        var request = try config("tall/\(UUID().uuidString)")
        request.captureMode = .fullPage
        request.safetyCaps.maxPageHeight = 480
        let image = try await URLSnapshotEngine(websiteDataStore: isolatedStore()).snapshot(
            of: request)
        #expect(image.width == 320)
        #expect(image.height == 480)
    }

    @Test func clearingSessionsRemovesCachedPrivateResponses() async throws {
        let port = try #require(
            ProcessInfo.processInfo.environment["VITRINE_WEB_FIXTURE_PORT"].flatMap(UInt16.init))
        let store = WKWebsiteDataStore.nonPersistent()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240), configuration: configuration)
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: true)
        view.navigationDelegate = coordinator
        defer {
            view.stopLoading()
            view.navigationDelegate = nil
        }
        view.load(URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/session"))))
        try await coordinator.waitForLoad(timeout: .seconds(10))
        let seeded = try await view.callAsyncJavaScript(
            """
            document.cookie = 'fixture=synthetic; SameSite=Strict';
            localStorage.setItem('fixture', 'synthetic');
            const cache = await caches.open('fixture-private');
            await cache.put('/private-response', new Response('synthetic private content'));
            return (await cache.match('/private-response')) !== undefined;
            """, arguments: [:], in: nil, contentWorld: .page)
        #expect(seeded as? Bool == true)
        #expect((await store.httpCookieStore.allCookies()).contains { $0.name == "fixture" })
        let nextCapture = URLSnapshotEngine().dataStore(for: .nonPersistent)
        #expect((await nextCapture.httpCookieStore.allCookies()).isEmpty)
        #expect(!(await WebSessionStore.signedInHosts(in: store)).isEmpty)
        await WebSessionStore.clearSessions(in: store)
        let retained = try await view.callAsyncJavaScript(
            "return await caches.has('fixture-private');",
            arguments: [:], in: nil, contentWorld: .page)
        #expect(retained as? Bool == false)
        #expect((await WebSessionStore.signedInHosts(in: store)).isEmpty)
        await store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

}

/// No production policy: used only to prove fixture destinations are reachable.
@MainActor
private final class FixtureNavigation: NSObject, WKNavigationDelegate {
    let waiter = WebLoadWaiter()
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waiter.complete(.success(()))
    }
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        waiter.complete(.failure(error))
    }
}

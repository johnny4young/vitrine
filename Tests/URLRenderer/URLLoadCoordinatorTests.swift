import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("URL load coordination")
struct URLLoadCoordinatorTests {
    @Test func aLoadWithoutADelegateOutcomeTimesOut() async {
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: false)

        await #expect(throws: WebSnapshotError.timedOut) {
            try await coordinator.waitForLoad(timeout: .milliseconds(1))
        }
    }

    @Test func taskCancellationResumesThePendingLoad() async {
        let coordinator = URLLoadCoordinator(allowsLoopbackCapture: false)
        let task = Task {
            try await coordinator.waitForLoad(timeout: .seconds(10))
        }

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
    // MARK: - Navigation policy

    private typealias Policy = URLLoadCoordinator.NavigationPolicy

    /// The gap this closes: the delegate gated on host alone, and a URL with no host
    /// failed that `if let` and fell through to allow. Every one of these carries no
    /// host, so each was previously allowed into the main frame of a capture.
    @Test(arguments: [
        "file:///etc/passwd",
        "data:text/html,<script>fetch('http://169.254.169.254/')</script>",
        "about:blank",
        "blob:https://example.com/0-0",
        "javascript:alert(1)",
    ])
    func mainFrameRefusesEverySchemeThatIsNotWeb(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(
            Policy.decision(for: url, isMainFrame: true, allowsLoopback: false)
                == .cancel(reason: "unsupported scheme"))
    }

    @Test func mainFrameRefusesAWebURLWithNoHost() throws {
        let url = try #require(URL(string: "https:///nowhere"))
        #expect(
            Policy.decision(for: url, isMainFrame: true, allowsLoopback: false)
                == .cancel(reason: "missing host"))
        #expect(Policy.decision(for: nil, isMainFrame: true, allowsLoopback: false) != .allow)
    }

    @Test func mainFrameStillRefusesPrivateHostsAndAllowsPublicOnes() throws {
        let metadata = try #require(URL(string: "http://169.254.169.254/latest/meta-data/"))
        #expect(
            Policy.decision(for: metadata, isMainFrame: true, allowsLoopback: false)
                == .cancel(reason: "private host"))

        let publicPage = try #require(URL(string: "https://example.com/page"))
        #expect(
            Policy.decision(for: publicPage, isMainFrame: true, allowsLoopback: false) == .allow)
    }

    @Test func loopbackFollowsTheExplicitOptIn() throws {
        let local = try #require(URL(string: "http://127.0.0.1:8080/"))
        #expect(
            Policy.decision(for: local, isMainFrame: true, allowsLoopback: false)
                == .cancel(reason: "private host"))
        #expect(Policy.decision(for: local, isMainFrame: true, allowsLoopback: true) == .allow)
    }

    /// Subframes keep the narrower rule: `about:srcdoc` and `data:` iframes are ordinary
    /// page furniture, and refusing them would break real pages without closing any path
    /// to private content. A local file subframe is still refused.
    @Test func subframesAllowInlineDocumentsButNotLocalFiles() throws {
        for raw in ["about:srcdoc", "data:text/html,<p>ad</p>"] {
            let url = try #require(URL(string: raw))
            #expect(Policy.decision(for: url, isMainFrame: false, allowsLoopback: false) == .allow)
        }

        let file = try #require(URL(string: "file:///Users/someone/.ssh/id_ed25519"))
        #expect(
            Policy.decision(for: file, isMainFrame: false, allowsLoopback: false)
                == .cancel(reason: "local file subframe"))

        let metadata = try #require(URL(string: "http://169.254.169.254/"))
        #expect(
            Policy.decision(for: metadata, isMainFrame: false, allowsLoopback: false)
                == .cancel(reason: "private host"))
    }

    /// The refusal reason reaches the log, so it must never carry a host or a path.
    @Test func refusalReasonsNeverCarryTheUserSDestination() throws {
        let url = try #require(URL(string: "https://private.example.internal/secret-path"))
        for isMainFrame in [true, false] {
            if case .cancel(let reason) = Policy.decision(
                for: url, isMainFrame: isMainFrame, allowsLoopback: false)
            {
                #expect(!reason.contains("example"))
                #expect(!reason.contains("secret-path"))
            }
        }
    }

}

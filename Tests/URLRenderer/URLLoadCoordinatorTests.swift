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
                == .cancel(.unsupportedScheme))
    }

    @Test func mainFrameRefusesAWebURLWithNoHost() throws {
        let url = try #require(URL(string: "https:///nowhere"))
        #expect(
            Policy.decision(for: url, isMainFrame: true, allowsLoopback: false)
                == .cancel(.missingHost))
        #expect(Policy.decision(for: nil, isMainFrame: true, allowsLoopback: false) != .allow)
    }

    @Test func mainFrameStillRefusesPrivateHostsAndAllowsPublicOnes() throws {
        let metadata = try #require(URL(string: "http://169.254.169.254/latest/meta-data/"))
        #expect(
            Policy.decision(for: metadata, isMainFrame: true, allowsLoopback: false)
                == .cancel(.privateHost))

        let publicPage = try #require(URL(string: "https://example.com/page"))
        #expect(
            Policy.decision(for: publicPage, isMainFrame: true, allowsLoopback: false) == .allow)
    }

    @Test func loopbackFollowsTheExplicitOptIn() throws {
        let local = try #require(URL(string: "http://127.0.0.1:8080/"))
        #expect(
            Policy.decision(for: local, isMainFrame: true, allowsLoopback: false)
                == .cancel(.privateHost))
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
                == .cancel(.localFileSubframe))

        let metadata = try #require(URL(string: "http://169.254.169.254/"))
        #expect(
            Policy.decision(for: metadata, isMainFrame: false, allowsLoopback: false)
                == .cancel(.privateHost))
    }

    /// The refusal reason reaches the log, so it must never carry a host or a path. The
    /// earlier version of this test used a host the policy does not refuse, so both
    /// decisions were `.allow` and it asserted nothing at all — it passed by never
    /// entering its own body.
    @Test func refusalReasonsNeverCarryTheUserSDestination() throws {
        let url = try #require(URL(string: "https://169.254.169.254/latest/meta-data/secret"))
        for isMainFrame in [true, false] {
            let decision = Policy.decision(
                for: url, isMainFrame: isMainFrame, allowsLoopback: false)
            // Fail loudly rather than skip: a decision that stopped refusing this host
            // would be the bug this file exists to catch.
            guard case .cancel(let refusal) = decision else {
                Issue.record("the cloud-metadata endpoint must be refused in every frame")
                continue
            }
            #expect(refusal == .privateHost)
            #expect(!refusal.rawValue.contains("169.254"))
            #expect(!refusal.rawValue.contains("secret"))
        }

        // Structural, not conventional: every case of the closed set is a fixed label, so
        // a future refusal cannot carry a destination into the log even by accident.
        for refusal in [
            Policy.Refusal.unsupportedScheme, .missingHost, .localFileSubframe, .privateHost,
        ] {
            #expect(!refusal.rawValue.contains("://"))
            #expect(refusal.rawValue.allSatisfy { $0.isLetter || $0 == " " })
        }
    }

    /// `WKNavigationAction.targetFrame` is `nil` when the navigation targets a new
    /// browsing context — a `_blank` link or a `window.open` — not this web view's main
    /// frame. Treating that as the main frame made a page that pops open an `about:`
    /// window cancel *and* fail the whole capture, which is a page rendering correctly
    /// today being reported as a failure.
    @Test func onlyAnExplicitlyMainTargetGetsTheMainFrameRules() {
        #expect(Policy.appliesMainFrameRules(isMainTarget: true))
        #expect(!Policy.appliesMainFrameRules(isMainTarget: false))
        #expect(!Policy.appliesMainFrameRules(isMainTarget: nil))

        // The consequence: a popup to a non-web scheme is dropped, not fatal.
        let popup = URL(string: "about:blank")
        let asNewWindow = Policy.appliesMainFrameRules(isMainTarget: nil)
        #expect(
            Policy.decision(for: popup, isMainFrame: asNewWindow, allowsLoopback: false)
                == .allow)
        // ...while the same URL in the main frame is still refused.
        #expect(
            Policy.decision(for: popup, isMainFrame: true, allowsLoopback: false)
                == .cancel(.unsupportedScheme))
    }

    // MARK: - The hermetic local-file capture

    /// `WebSnapshotConfig(localFileURL:)` is the one path that legitimately loads a
    /// `file:` document: URL validation rejects the scheme for anything a user could
    /// type, so only that explicit hook produces such a capture. Refusing the scheme
    /// outright broke the live render suite, which is what this pins.
    @Test func aLocalFileCaptureLoadsItsOwnDocument() {
        let file = URL(fileURLWithPath: "/tmp/fixture.html")
        #expect(
            Policy.decision(
                for: file, isMainFrame: true, allowsLoopback: false, allowsLocalFile: true)
                == .allow)
        // The permission covers that capture's main document only.
        #expect(
            Policy.decision(
                for: file, isMainFrame: false, allowsLoopback: false, allowsLocalFile: true)
                == .cancel(.localFileSubframe))
        // An ordinary web capture still refuses the scheme outright.
        #expect(
            Policy.decision(
                for: file, isMainFrame: true, allowsLoopback: false, allowsLocalFile: false)
                == .cancel(.unsupportedScheme))
        // Permission to load a local file is not permission to reach a private host.
        #expect(
            Policy.decision(
                for: URL(string: "http://169.254.169.254/latest/meta-data/"),
                isMainFrame: true, allowsLoopback: false, allowsLocalFile: true)
                == .cancel(.privateHost))
    }

}

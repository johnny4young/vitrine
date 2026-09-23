import Foundation
import Testing
import WebKit

@testable import Vitrine

/// Capturing a page behind a login needs a session, and the offscreen capture engine can
/// never establish one — it rasterizes, it never types. These cover the rule that decides
/// when Vitrine offers to sign in for the user, and in what order it asks for the pieces.
@MainActor
@Suite("Web capture sign-in availability")
struct WebSessionAvailabilityTests {
    private let site = "https://github.com/cognosos/node-packages/releases"

    @Test func signInIsOfferedOnceEveryRequirementIsMet() {
        #expect(
            WebSessionAvailability.canSignIn(
                isCaptureEnabled: true, usesLoggedInSession: true, urlText: site))
        #expect(
            WebSessionAvailability.blocker(
                isCaptureEnabled: true, usesLoggedInSession: true, urlText: site) == nil)
    }

    /// The opt-in is the whole point: without a persistent store the session would be
    /// discarded the moment the sign-in window closed, so signing in would be theatre.
    @Test func aSessionThatWouldNotPersistBlocksSigningIn() {
        #expect(
            WebSessionAvailability.blocker(
                isCaptureEnabled: true, usesLoggedInSession: false, urlText: site)
                == .sessionNotEnabled)
    }

    /// A build without the network entitlement cannot load any page to sign in to, and
    /// the user cannot fix that — so it outranks the settings toggle they *could* fix.
    @Test func aBuildWithoutNetworkAccessOutranksTheOtherBlockers() {
        #expect(
            WebSessionAvailability.blocker(
                isCaptureEnabled: false, usesLoggedInSession: false, urlText: "")
                == .captureUnavailable)
    }

    @Test func anUnusableAddressBlocksSigningIn() {
        for text in ["", "   ", "not a url", "ftp://example.com", "javascript:alert(1)"] {
            #expect(
                WebSessionAvailability.blocker(
                    isCaptureEnabled: true, usesLoggedInSession: true, urlText: text)
                    == .noValidURL,
                "\(text) is not a capturable address")
        }
    }

    /// Loopback is its own opt-in; the sign-in rule must honour it rather than deciding
    /// separately what counts as a reachable address.
    @Test func loopbackFollowsItsOwnOptIn() {
        #expect(
            WebSessionAvailability.blocker(
                isCaptureEnabled: true, usesLoggedInSession: true,
                urlText: "http://localhost:3000", allowsLoopback: false) == .noValidURL)
        #expect(
            WebSessionAvailability.canSignIn(
                isCaptureEnabled: true, usesLoggedInSession: true,
                urlText: "http://localhost:3000", allowsLoopback: true))
    }

    /// The button names the site, so the user can tell what a sign-in would apply to.
    @Test func theSiteLabelIsTheHost() {
        #expect(WebSessionAvailability.siteLabel(for: site) == "github.com")
        #expect(WebSessionAvailability.siteLabel(for: "https://example.com") == "example.com")
        #expect(WebSessionAvailability.siteLabel(for: "not a url") == nil)
    }

    /// Clearing must remove storage that can retain private content, not cookies alone.
    @Test func clearingCoversEveryRecordTypeASessionLivesIn() {
        let types = WebSessionStore.sessionDataTypes
        #expect(types.contains(WKWebsiteDataTypeCookies))
        #expect(types.contains(WKWebsiteDataTypeLocalStorage))
        #expect(types.contains(WKWebsiteDataTypeSessionStorage))
        #expect(types.contains(WKWebsiteDataTypeIndexedDBDatabases))
        // Cached responses and workers can retain private content after cookie removal.
        #expect(types.contains(WKWebsiteDataTypeDiskCache))
        #expect(types.contains(WKWebsiteDataTypeFetchCache))
        #expect(types.contains(WKWebsiteDataTypeServiceWorkerRegistrations))
        #expect(types == WKWebsiteDataStore.allWebsiteDataTypes())
    }

    @Test(.timeLimit(.minutes(1)))
    func clearingAnEmptyStoreReturnsNoSiteLabelsAndNotifiesObservers() async {
        // The ordinary sandboxed lane verifies the empty-state command contract.
        // Populated cookies, storage, and cached responses are qualified by the
        // controlled WebKit lane, whose host can launch the network process.
        let store = WKWebsiteDataStore.nonPersistent()
        #expect((await WebSessionStore.storedSiteLabels(in: store)).isEmpty)
        await confirmation("Session observers refresh exactly once even when no sites are stored") {
            confirmed in
            let observer = NotificationCenter.default.addObserver(
                forName: WebSessionStore.didChange, object: nil, queue: nil
            ) { _ in confirmed() }
            defer { NotificationCenter.default.removeObserver(observer) }
            #expect((await WebSessionStore.clearSessions(in: store)).isEmpty)
            #expect((await WebSessionStore.storedSiteLabels(in: store)).isEmpty)
        }
    }
}

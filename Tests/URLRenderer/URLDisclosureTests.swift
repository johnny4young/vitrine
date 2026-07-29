import Testing

@testable import Vitrine

// MARK: - First-use disclosure (no web process needed)

@Suite("URL capture first-use disclosure")
struct URLFirstUseDisclosureTests {
    @Test func theDisclosureExplainsLocalWebKitLoading() {
        // The first-use copy must make the privacy fact explicit: the page is loaded
        // locally in WebKit, and there is no remote screenshot service.
        let disclosure = WebSnapshotConfig.firstUseDisclosure
        #expect(!disclosure.title.isEmpty)
        #expect(disclosure.message.localizedCaseInsensitiveContains("locally"))
        #expect(disclosure.message.localizedCaseInsensitiveContains("WebKit"))
        #expect(!disclosure.confirmTitle.isEmpty)
        #expect(!disclosure.cancelTitle.isEmpty)
    }

    @Test func theDisclosurePromisesNoRemoteRenderService() {
        // The copy explicitly rules out a remote render service, preserving the
        // privacy promise.
        let message = WebSnapshotConfig.firstUseDisclosure.message
        #expect(message.localizedCaseInsensitiveContains("remote"))
        #expect(message.localizedCaseInsensitiveContains("on-device"))
    }
}

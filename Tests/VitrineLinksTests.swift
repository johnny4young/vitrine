import Foundation
import Testing

@testable import Vitrine

@Suite("Vitrine links")
struct VitrineLinksTests {
    @Test func staticExternalURLsAreCentralizedAndValid() throws {
        #expect(
            try #require(VitrineLinks.githubRepository).absoluteString
                == "https://github.com/johnny4young/vitrine")
        #expect(
            try #require(VitrineLinks.lemonSqueezyActivationEndpoint).absoluteString
                == "https://api.lemonsqueezy.com/v1/licenses/activate")
        #expect(
            try #require(VitrineLinks.lemonSqueezyDeactivationEndpoint).absoluteString
                == "https://api.lemonsqueezy.com/v1/licenses/deactivate")
        #expect(
            try #require(VitrineLinks.lemonSqueezyCheckout).absoluteString
                == "https://johnny4young.lemonsqueezy.com/checkout/buy/"
                + "314e7d43-efa1-41be-a319-7474628e5185")
    }

    @Test func trustedParserRejectsRelativeInsecureAndCredentialedURLs() {
        for invalid in [
            "",
            "/relative",
            "vitrine.example/path",
            "http://example.com/path",
            "https:///missing-host",
            "https://user:secret@example.com/path",
        ] {
            #expect(VitrineLinks.trustedHTTPSURL(invalid) == nil)
        }

        #expect(
            VitrineLinks.trustedHTTPSURL("HTTPS://example.com/path")?.absoluteString
                == "HTTPS://example.com/path")
    }
}

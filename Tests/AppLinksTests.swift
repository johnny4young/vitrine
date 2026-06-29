import Foundation
import Testing

@testable import Vitrine

@Suite("App links")
struct AppLinksTests {
    @Test func staticExternalURLsAreCentralizedAndValid() {
        #expect(
            VitrineLinks.githubRepository.absoluteString
                == "https://github.com/johnny4young/vitrine")
        #expect(
            VitrineLinks.lemonSqueezyActivationEndpoint.absoluteString
                == "https://api.lemonsqueezy.com/v1/licenses/activate")
    }
}

import Foundation
import Testing

@testable import Vitrine

@Suite("Privacy manifest")
struct PrivacyManifestTests {
    @Test func declaresNoTrackingAndOnlyUserDefaults() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy must be bundled with the app (CS-011)")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any] ?? []).isEmpty)

        let apiTypes = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let categories = apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(categories == ["NSPrivacyAccessedAPICategoryUserDefaults"])
    }
}

import Foundation
import Testing

@testable import Vitrine

/// The test-facing name for Vitrine's process-local defaults implementation.
///
/// UUID-named `UserDefaults(suiteName:)` instances still create persistent plist files
/// inside the sandbox even when a test later calls `removePersistentDomain`. Repeated
/// local and CI runs therefore leak one file per fixture. Tests inherit the exact store
/// used by real editor sessions rather than maintaining a second simulation that can
/// drift from production behavior.
nonisolated class TestUserDefaults: InMemoryUserDefaults {}

/// Creates a fresh in-memory defaults graph for one test.
nonisolated func testDefaults(initialValues: [String: Any] = [:]) -> UserDefaults {
    TestUserDefaults(initialValues: initialValues)
}

@Suite("In-memory test defaults")
struct TestUserDefaultsTests {
    @Test func typedAccessorsAndRegistrationBehaveLikeUserDefaults() {
        let defaults = testDefaults()
        defaults.register(defaults: ["fallback": "registered", "overridden": 1])
        defaults.set(42, forKey: "integer")
        defaults.set(true, forKey: "boolean")
        defaults.set("stored", forKey: "overridden")

        #expect(defaults.string(forKey: "fallback") == "registered")
        #expect(defaults.integer(forKey: "integer") == 42)
        #expect(defaults.bool(forKey: "boolean"))
        #expect(defaults.string(forKey: "overridden") == "stored")
        #expect(defaults.dictionaryRepresentation()["fallback"] as? String == "registered")
    }

    @Test func storesAreIndependentAndPersistentDomainRemovalKeepsRegistration() {
        let first = testDefaults(initialValues: ["stored": "first"])
        let second = testDefaults(initialValues: ["stored": "second"])
        first.register(defaults: ["fallback": "registered"])

        first.removePersistentDomain(forName: "ignored")

        #expect(first.object(forKey: "stored") == nil)
        #expect(first.string(forKey: "fallback") == "registered")
        #expect(second.string(forKey: "stored") == "second")
    }

    @Test func discardedStorePermanentlyRejectsLateWrites() {
        let defaults = TestUserDefaults(initialValues: ["stored": "value"])
        defaults.register(defaults: ["fallback": "registered"])

        defaults.discard()
        defaults.set("late", forKey: "stored")
        defaults.removeObject(forKey: "stored")
        defaults.register(defaults: ["fallback": "late"])
        defaults.setPersistentDomain(["domain": "late"], forName: "ignored")
        defaults.removePersistentDomain(forName: "ignored")
        defaults.removeAllStoredValues()
        defaults.removeAllValues()

        #expect(defaults.dictionaryRepresentation().isEmpty)

        defaults.set("next", forKey: "stored")
        #expect(defaults.object(forKey: "stored") == nil)
    }

    @Test func persistentSuiteConstructionIsExplicitlyLimited() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let construction = try NSRegularExpression(
            pattern: #"UserDefaults\s*\(\s*suiteName:"#)
        var offenders: [String] = []

        for directoryName in ["Vitrine", "Tests"] {
            let directory = projectRoot.appendingPathComponent(directoryName, isDirectory: true)
            let enumerator = try #require(
                FileManager.default.enumerator(
                    at: directory, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]))
            for case let url as URL in enumerator
            where url.pathExtension == "swift" && url.lastPathComponent != "TestUserDefaults.swift"
            {
                let source = sourceCodeWithoutLineComments(
                    try String(contentsOf: url, encoding: .utf8))
                let count = construction.numberOfMatches(
                    in: source, range: NSRange(source.startIndex..., in: source))
                if count > 0 {
                    let directoryMarker = "/\(directoryName)/"
                    let relativePath: String
                    if let markerRange = url.path.range(of: directoryMarker, options: .backwards) {
                        relativePath = directoryName + "/" + url.path[markerRange.upperBound...]
                    } else {
                        relativePath = url.lastPathComponent
                    }
                    offenders.append("\(relativePath): \(count)")
                }
            }
        }

        #expect(
            offenders == ["Vitrine/Support/AppDefaults.swift: 1"],
            "Only the opt-in cross-launch UI-test store may create a persistent suite: \(offenders)"
        )
    }
}

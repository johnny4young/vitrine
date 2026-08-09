import Foundation
import Testing

/// A process-local `UserDefaults` test double.
///
/// UUID-named `UserDefaults(suiteName:)` instances still create persistent plist files
/// inside the sandbox even when a test later calls `removePersistentDomain`. Repeated
/// local and CI runs therefore leak one file per fixture. This implementation preserves
/// the `UserDefaults` API that Vitrine consumes while keeping every value in memory.
/// Tests that explicitly exercise cross-instance cfprefsd persistence continue to use
/// real named suites at their call sites.
nonisolated class TestUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String: Any]
    private var registeredValues: [String: Any]

    init(initialValues: [String: Any] = [:]) {
        self.storedValues = initialValues
        self.registeredValues = [:]
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { storedValues[defaultName] ?? registeredValues[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock {
            if let value {
                storedValues[defaultName] = value
            } else {
                storedValues.removeValue(forKey: defaultName)
            }
        }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { _ = storedValues.removeValue(forKey: defaultName) }
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        lock.withLock { registeredValues.merge(registrationDictionary) { _, new in new } }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock {
            registeredValues.merging(storedValues) { _, stored in stored }
        }
    }

    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        lock.withLock { storedValues }
    }

    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        lock.withLock { storedValues = domain }
    }

    override func removePersistentDomain(forName domainName: String) {
        lock.withLock { storedValues.removeAll(keepingCapacity: false) }
    }

    override func synchronize() -> Bool { true }
}

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

    @Test func persistentSuiteConstructionIsExplicitlyLimited() throws {
        let testsRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let construction = try NSRegularExpression(
            pattern: #"UserDefaults\s*\(\s*suiteName:"#)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: testsRoot, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))
        var offenders: [String] = []

        for case let url as URL in enumerator
        where url.pathExtension == "swift" && url.lastPathComponent != "TestUserDefaults.swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let count = construction.numberOfMatches(
                in: source, range: NSRange(source.startIndex..., in: source))
            if count > 0 {
                offenders.append("\(url.lastPathComponent): \(count)")
            }
        }

        #expect(
            offenders == ["WindowStateTests.swift: 1"],
            "Persistent defaults are reserved for the explicit cfprefsd teardown contract: \(offenders)"
        )
    }
}

import Foundation

/// A process-local `UserDefaults` store with no `cfprefsd` or filesystem backing.
///
/// Vitrine uses the familiar `UserDefaults` API throughout its settings graph, but an
/// editor window's draft is session state rather than a preference. Giving every window
/// a UUID-named persistent suite left plist files behind after crashes and even after
/// `removePersistentDomain`. This store preserves the API expected by `AppSettings` while
/// keeping the draft in memory, where its lifetime follows the owning editor session.
///
/// `UserDefaults` is otherwise documented as thread-safe. The override state therefore
/// uses a lock as well, preserving the inherited `Sendable` contract without an unsafe
/// conformance escape hatch.
nonisolated class InMemoryUserDefaults: UserDefaults {
    private let lock = NSLock()
    private var storedValues: [String: Any]
    private var registeredValues: [String: Any]
    private var acceptsWrites = true

    init(initialValues: [String: Any] = [:]) {
        self.storedValues = initialValues
        self.registeredValues = [:]
        // `UserDefaults.init()` is a convenience initializer, so subclasses must call
        // this designated initializer. Foundation defines `nil` as the standard search
        // list and always returns an instance for it; all consumed storage operations
        // are overridden below and never reach that backing domain.
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { storedValues[defaultName] ?? registeredValues[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock {
            guard acceptsWrites else { return }
            if let value {
                storedValues[defaultName] = value
            } else {
                _ = storedValues.removeValue(forKey: defaultName)
            }
        }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { _ = storedValues.removeValue(forKey: defaultName) }
    }

    override func register(defaults registrationDictionary: [String: Any]) {
        lock.withLock {
            guard acceptsWrites else { return }
            registeredValues.merge(registrationDictionary) { _, new in new }
        }
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
        lock.withLock {
            guard acceptsWrites else { return }
            storedValues = domain
        }
    }

    override func removePersistentDomain(forName domainName: String) {
        removeAllStoredValues()
    }

    override func synchronize() -> Bool { true }

    /// Removes explicitly stored values while preserving registered fallbacks, matching
    /// `removePersistentDomain` semantics without creating or touching a domain on disk.
    func removeAllStoredValues() {
        lock.withLock { storedValues.removeAll(keepingCapacity: false) }
    }

    /// Releases both stored values and registered fallbacks without changing whether the
    /// store accepts writes. Session composition uses this only on a fresh, exclusive store.
    func removeAllValues() {
        lock.withLock {
            storedValues.removeAll(keepingCapacity: false)
            registeredValues.removeAll(keepingCapacity: false)
        }
    }

    /// Releases every retained value and permanently suppresses late writes. Stores are
    /// intentionally single-lifecycle so an old owner can never write into a new session.
    func discard() {
        lock.withLock {
            storedValues.removeAll(keepingCapacity: false)
            registeredValues.removeAll(keepingCapacity: false)
            acceptsWrites = false
        }
    }

    /// A copy of the explicitly stored values for lifecycle assertions and diagnostics.
    var storedValuesSnapshot: [String: Any] {
        lock.withLock { storedValues }
    }
}

import Foundation
import WebKit

/// Vitrine's own store of website data for signed-in captures.
///
/// This is `WKWebsiteDataStore.default()` — the same store `URLRenderer` loads with when
/// the user opts into `DataStoreMode.persistent`, and the one the sign-in window writes
/// to. It belongs to Vitrine alone: WebKit isolates website data per application, so
/// nothing here is read from or written to Safari, Chrome, or any other app.
///
/// Everything a signed-in capture relies on lives here, which makes this also the place
/// that has to be able to throw it all away again.
enum WebSessionStore {
    /// Refresh visible inventories after sign-in or website-data removal.
    static let didChange = Notification.Name("VitrineWebSessionDataDidChange")

    /// Private responses and credentials can live in caches and service workers as
    /// well as cookies and local storage. Sign-out clears every WebKit data type in
    /// Vitrine's store, including types introduced by newer system versions.
    static var sessionDataTypes: Set<String> { WKWebsiteDataStore.allWebsiteDataTypes() }

    /// WebKit site labels with stored website data, sorted for stable display.
    ///
    /// These are site labels, not a complete hostname inventory or proof of login.
    /// Lets the UI show stored sites rather than asking users to trust
    /// an opaque switch — and lets "clear" show what it is about to remove.
    static func storedSiteLabels(in store: WKWebsiteDataStore = .default()) async -> [String] {
        let records = await store.dataRecords(ofTypes: sessionDataTypes)
        return records.map(\.displayName).sorted()
    }

    /// Removes every saved website-data record, returning its site labels.
    ///
    /// Includes cached private responses and service worker registrations. This cannot
    /// revoke server-side sessions or remove data in another application.
    @discardableResult
    static func clearSessions(in store: WKWebsiteDataStore = .default()) async -> [String] {
        let records = await store.dataRecords(ofTypes: sessionDataTypes)
        // Clear by time rather than only the inventory snapshot: another record
        // may be committed while the asynchronous inventory is being fetched.
        await store.removeData(ofTypes: sessionDataTypes, modifiedSince: .distantPast)
        NotificationCenter.default.post(name: didChange, object: nil)
        return records.map(\.displayName).sorted()
    }
}

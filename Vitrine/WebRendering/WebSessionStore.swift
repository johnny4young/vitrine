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
@MainActor
enum WebSessionStore {
    /// Installs the store behind `WebSessionPresenter`, so the settings pane — which the
    /// WebKit-free CLI also compiles — can list and clear sessions without linking WebKit.
    /// Called once at launch from the app-only entry point.
    static func registerPresenter() {
        WebSessionPresenter.readSignedInHosts = { await signedInHosts() }
        WebSessionPresenter.clearSessions = { await clearSessions() }
    }

    /// The record types a sign-in leaves behind. Cookies carry the session itself; the
    /// storage types are what a site uses to keep a login alive across loads, so leaving
    /// them behind after a "sign out" would keep the user signed in.
    static let sessionDataTypes: Set<String> = [
        WKWebsiteDataTypeCookies,
        WKWebsiteDataTypeLocalStorage,
        WKWebsiteDataTypeSessionStorage,
        WKWebsiteDataTypeIndexedDBDatabases,
        WKWebsiteDataTypeWebSQLDatabases,
    ]

    /// The hosts Vitrine currently holds session data for, sorted for stable display.
    ///
    /// Lets the UI tell the user exactly what is stored rather than asking them to trust
    /// an opaque switch — and lets "clear" show what it is about to remove.
    static func signedInHosts(in store: WKWebsiteDataStore = .default()) async -> [String] {
        let records = await store.dataRecords(ofTypes: sessionDataTypes)
        return records.map(\.displayName).sorted()
    }

    /// Removes every stored session, returning the hosts that were cleared.
    ///
    /// Scoped to ``sessionDataTypes`` rather than every WebKit data type: caches and
    /// service workers are not a session, and dropping them would only make the next
    /// capture slower.
    @discardableResult
    static func clearSessions(in store: WKWebsiteDataStore = .default()) async -> [String] {
        let records = await store.dataRecords(ofTypes: sessionDataTypes)
        guard !records.isEmpty else { return [] }
        await store.removeData(ofTypes: sessionDataTypes, for: records)
        return records.map(\.displayName).sorted()
    }
}

import Foundation

/// Selects the content-rule store without creating it. An explicit directory never
/// falls back to the application's store or reuses its process-wide compiled list.
enum WebContentRuleListStoreSource: Equatable {
    case applicationDefault
    case directory(URL)

    var usesSharedCache: Bool { self == .applicationDefault }

    /// Resolves lazily so construction and failure contracts can be exercised with
    /// inert stores. Directory ownership and cleanup belong to the caller.
    func makeStore<Store>(
        applicationDefault: () -> Store?, directory: (URL) -> Store?
    ) -> Store? {
        switch self {
        case .applicationDefault:
            return applicationDefault()
        case .directory(let url):
            guard url.isFileURL, url.host?.isEmpty != false,
                url.path.hasPrefix("/"), url.query == nil, url.fragment == nil
            else { return nil }
            return directory(url)
        }
    }
}

import Foundation

extension URL {
    /// This file's path below `root`, or `nil` when it is not inside it.
    ///
    /// Both sides resolve symlinks first: `#filePath` keeps the path the checkout was
    /// built from (`/tmp/…`), while a directory enumerator can hand back the resolved one
    /// (`/private/tmp/…`), so a plain string prefix does not match.
    func relativePath(from root: URL) -> String? {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let components = standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard components.count > base.count, components.starts(with: base) else { return nil }
        return components.dropFirst(base.count).joined(separator: "/")
    }
}

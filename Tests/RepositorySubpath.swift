import Foundation

extension URL {
    /// This file's path below `root`, or `nil` when it is not inside it.
    ///
    /// Directories on both sides resolve symlinks first: `#filePath` keeps the path the
    /// checkout was built from (`/tmp/…`), while a directory enumerator can hand back the
    /// resolved one (`/private/tmp/…`). The file's own name is kept as listed.
    func subpath(under root: URL) -> String? {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let file = standardizedFileURL
        let components =
            file.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents
            + [file.lastPathComponent]
        guard components.count > base.count, components.starts(with: base) else { return nil }
        return components.dropFirst(base.count).joined(separator: "/")
    }
}

import Darwin
import Foundation
import VitrineRendering

/// App-owned transactional directory writing. Only an explicitly selected parent is used.
enum DocumentationPackageWriter {
    nonisolated enum WriteError: Error, Equatable {
        case invalidName, invalidParent, destinationExists
        case commitFailed(Int32)
    }

    /// Inject individual writes to exercise disk failures and commit-time collisions.
    @concurrent static func write(
        _ package: DocumentationPackage, parent: URL, name: String,
        writeFile: @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }
    ) async throws -> URL {
        try writeSynchronously(package, parent: parent, name: name, writeFile: writeFile)
    }

    nonisolated static func writeSynchronously(
        _ package: DocumentationPackage, parent: URL, name: String,
        writeFile: @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }
    ) throws -> URL {
        let manager = FileManager.default
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
            !name.contains("/"), !name.contains("\\"), !name.contains("\0")
        else { throw WriteError.invalidName }
        guard parent.isFileURL else { throw WriteError.invalidParent }
        let parent = parent.resolvingSymlinksInPath().standardizedFileURL
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw WriteError.invalidParent }
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        // attributesOfItem also detects dangling symlinks; never follow an output link.
        if (try? manager.attributesOfItem(atPath: destination.path)) != nil {
            throw WriteError.destinationExists
        }
        try Task.checkCancellation()
        let staging = parent.appendingPathComponent(
            ".vitrine-export-\(UUID().uuidString)", isDirectory: true)
        // Default attributes honor the umask, so the committed folder matches its siblings.
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? manager.removeItem(at: staging) } }
        for (filename, data) in package.files.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            try writeFile(data, staging.appendingPathComponent(filename))
        }
        try Task.checkCancellation()
        // RENAME_EXCL makes a commit-time collision fail atomically, including empty directories.
        let result = staging.path.withCString { source in
            destination.path.withCString { target in renamex_np(source, target, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw WriteError.destinationExists }
            throw WriteError.commitFailed(code)
        }
        committed = true
        // A completed rename is success even if cancellation arrives immediately afterwards.
        return destination
    }
}

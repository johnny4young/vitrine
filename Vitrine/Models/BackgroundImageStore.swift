import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

/// Stores and resolves image-background files inside the app container (CS-051).
///
/// Vitrine never uploads a background and never asks for a broad file
/// entitlement. The user picks an image through an `NSOpenPanel` (covered by the
/// existing `com.apple.security.files.user-selected.read-write` entitlement); the
/// store reads it under a security-scoped resource access and copies the bytes
/// into a private directory under Application Support. Persistence then stores
/// only the in-container file name (`ImageReference`), so a saved background:
///
/// - resolves back to a readable file on relaunch without re-prompting, and
/// - degrades gracefully when the copied file is missing/relocated — `url(for:)`
///   returns `nil` and callers fall back to a safe default background.
///
/// The base directory is injectable so the import/resolve/missing-file behavior
/// is unit-testable without touching the real container.
struct BackgroundImageStore {
    /// Errors surfaced while importing a user-selected image.
    enum ImportError: Error, Equatable {
        /// The chosen file was not a decodable image.
        case notAnImage
        /// The bytes could not be read or written into the container.
        case copyFailed
    }

    /// The directory holding copied background images. Created on demand.
    let directory: URL

    /// The store rooted at the app's Application Support container — the path used
    /// in the running app. Falls back to a temporary directory if Application
    /// Support is somehow unavailable, so the store is always usable.
    static var container: BackgroundImageStore {
        let base =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return BackgroundImageStore(
            directory: base.appendingPathComponent("Backgrounds", isDirectory: true))
    }

    /// Copies the user-selected image at `sourceURL` into the container and
    /// returns a stable reference to the copy (CS-051).
    ///
    /// `sourceURL` is a user-chosen file: access is bracketed by
    /// `startAccessingSecurityScopedResource()` so the read works under the
    /// sandbox without a broad entitlement. The bytes are validated as a decodable
    /// image before being written, and the destination name is content-addressed
    /// (a hash of the bytes) so re-importing the same image reuses one file
    /// instead of accumulating duplicates.
    func importImage(from sourceURL: URL) throws -> ImageReference {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw ImportError.copyFailed
        }

        // Validate it is genuinely an image before storing it; never trust the
        // extension alone.
        guard NSImage(data: data) != nil else { throw ImportError.notAnImage }

        let ext = sanitizedExtension(for: sourceURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fileName = ext.isEmpty ? digest : "\(digest).\(ext)"
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            // Re-importing identical bytes is a no-op: the content-addressed name
            // already points at the same image.
            if !FileManager.default.fileExists(atPath: destination.path) {
                try data.write(to: destination, options: .atomic)
            }
        } catch {
            Log.export.error("Background image copy failed; not storing the file")
            throw ImportError.copyFailed
        }

        Log.export.info("Imported a background image into the container")
        return ImageReference(fileName: fileName)
    }

    /// Resolves a reference to the on-disk image URL, or `nil` when the file is
    /// missing or the name is unsafe — the signal callers use to fall back to a
    /// safe default background (CS-051 graceful degradation).
    func url(for reference: ImageReference) -> URL? {
        // Reject any name that is not a plain file component (path separators,
        // `..`) so a hand-edited store cannot escape the backgrounds directory.
        let name = reference.fileName
        guard !name.isEmpty, !name.contains("/"), name != "..", name != "." else { return nil }
        let candidate = directory.appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    /// Loads the referenced image, or `nil` if it cannot be resolved or decoded.
    func image(for reference: ImageReference) -> NSImage? {
        guard let url = url(for: reference) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// A lowercased, image-only file extension for the destination name, or an
    /// empty string when the source has none. Restricting to known image types
    /// keeps the stored name tidy and predictable.
    private func sanitizedExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty,
            let type = UTType(filenameExtension: ext),
            type.conforms(to: .image)
        else { return "" }
        return ext
    }
}

extension EnvironmentValues {
    /// The store used to resolve image backgrounds (CS-051).
    ///
    /// Defaults to the real app-container store; injected with an isolated store
    /// in tests and previews so the render path can resolve fixture images without
    /// touching the user's container.
    @Entry var backgroundImageStore: BackgroundImageStore = .container
}

import Foundation
import UniformTypeIdentifiers

/// The editor's drag-and-drop input: reading a dropped source file or text and
/// loading it into the live document (CS-028).
extension EditorView {
    // MARK: - Drag-and-drop input (CS-028)

    /// Handles a drop onto the editor: reads a source file (preferred) or selected
    /// text from the providers, then either loads it straight away (empty editor)
    /// or asks whether to replace or append (non-empty editor). A binary, oversized,
    /// or unreadable file is rejected with a clear alert (CS-028).
    func handleDrop(_ providers: [NSItemProvider]) async {
        // An image — a dropped picture file or an in-app drag carrying image bytes —
        // becomes the beautified foreground content (CS "beautify any image"), so it must
        // be intercepted before the source-file path (which would reject a binary image).
        for provider in providers {
            if let reference = await readImageReference(from: provider) {
                applyImage(reference)
                return
            }
        }

        // A dragged file is the richer source, so try file URLs before text — a
        // Finder drag often advertises both.
        for provider in providers {
            if let url = await readFileURL(from: provider) {
                do {
                    offerLoaded(try FileInputLoader.load(from: url))
                } catch let error as FileInputLoader.LoadError {
                    dropError = error
                } catch {
                    dropError = .unreadable
                }
                return
            }
        }

        // No file: fall back to dropped text, inferring the language from content.
        for provider in providers {
            if let text = await readText(from: provider),
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                let interpreted = LanguageDetector.interpret(text)
                offerLoaded(
                    FileInputLoader.LoadedFile(
                        text: interpreted.code, language: interpreted.language, filename: ""))
                return
            }
        }
    }

    /// Loads immediately into an empty editor, or defers to the replace/append
    /// prompt when the editor already holds code (CS-028 "clear prompt").
    func offerLoaded(_ loaded: FileInputLoader.LoadedFile) {
        if settings.config.code.isEmpty {
            apply(loaded, replacing: true)
        } else {
            pendingDrop = PendingDrop(loaded: loaded)
        }
    }

    /// Resolves a pending replace/append choice from the confirmation dialog.
    func applyDrop(replacing: Bool) {
        guard let pending = pendingDrop else { return }
        apply(pending.loaded, replacing: replacing)
        pendingDrop = nil
    }

    /// Writes a loaded drop into the live config. Replacing swaps the whole
    /// document and adopts the inferred language and filename; appending keeps the
    /// current language (the existing code defines it) and only grows the text.
    ///
    /// Either way this just fills the editor — it never records a Recent. The
    /// filename rides along in `metadata.filename` (CS-022) so a *later*
    /// capture/export reflects the source, honoring "Recents record loaded file
    /// metadata only when the user captures/exports" (CS-028).
    func apply(_ loaded: FileInputLoader.LoadedFile, replacing: Bool) {
        loaded.apply(to: &settings.config, replacing: replacing)
        settings.noteLanguageUsed(settings.config.language)
        Log.capture.info(
            "Editor drop loaded (\(loaded.text.count, privacy: .public) chars, \(loaded.language.rawValue, privacy: .public))"
        )
    }

    /// Imports a dropped image into the foreground store and returns its reference, or
    /// `nil` when the provider carries no image. Handles both a dropped image **file**
    /// (Finder) and an in-app drag carrying image **bytes** (Preview, a browser).
    func readImageReference(from provider: NSItemProvider) async -> ImageReference? {
        if let url = await readImageFileURL(from: provider) {
            return try? foregroundImageStore.importImage(from: url)
        }
        if let (data, ext) = await readImageData(from: provider) {
            return try? foregroundImageStore.importImage(data: data, preferredExtension: ext)
        }
        return nil
    }

    /// A dropped file URL that points at an image file, or `nil` for a non-image file.
    func readImageFileURL(from provider: NSItemProvider) async -> URL? {
        guard let url = await readFileURL(from: provider),
            let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image)
        else { return nil }
        return url
    }

    /// Reads raw image bytes (and a preferred extension) from a provider that carries an
    /// image directly, or `nil` when it carries none. Loading the original data preserves
    /// the source format instead of re-encoding through `NSImage`.
    func readImageData(from provider: NSItemProvider) async -> (Data, String)? {
        let imageType = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
        guard let imageType, let type = UTType(imageType) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (data, type.preferredFilenameExtension ?? ""))
            }
        }
    }

    /// Loads a beautified foreground image into the live document, replacing any prior
    /// content marks. The existing `code` is kept (rendered again if the image is later
    /// cleared), so switching to image mode is non-destructive.
    func applyImage(_ reference: ImageReference) {
        settings.config.clearContentMarks()
        settings.config.foregroundImage = reference
        Log.capture.info("Editor drop loaded a foreground image")
    }

    /// Reads a dropped file's URL from a provider, or `nil` when it carries none.
    /// The coerced item is a `URL` (or URL bytes), which `FileInputLoader` then
    /// reads under a security-scoped access — no broad file entitlement is
    /// involved (CS-028).
    func readFileURL(from provider: NSItemProvider) async -> URL? {
        let type = UTType.fileURL.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Reads dropped plain text from a provider, or `nil` when it carries none.
    func readText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { string, _ in
                continuation.resume(returning: string)
            }
        }
    }
}

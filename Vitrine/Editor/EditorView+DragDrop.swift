import AppKit
import Foundation
import UniformTypeIdentifiers

/// The editor's drag-and-drop input: reading a dropped source file or text and
/// loading it into the live document.
extension EditorView {
    // MARK: - Drag-and-drop input

    /// Local item-provider reads should settle quickly, but iCloud-backed or
    /// cross-process providers get a generous bounded window before Vitrine gives up.
    static let itemProviderLoadTimeout: Duration = .seconds(10)

    /// Handles a drop onto the editor: reads a source file (preferred) or selected
    /// text from the providers, then either loads it straight away (empty editor)
    /// or asks whether to replace or append (non-empty editor). A binary, oversized,
    /// or unreadable file is rejected with a clear alert.
    func handleDrop(_ providers: [NSItemProvider]) async {
        // An image — a dropped picture file or an in-app drag carrying image bytes —
        // becomes the beautified foreground content (CS "beautify any image"), so it must
        // be intercepted before the source-file path (which would reject a binary image).
        for provider in providers {
            do {
                if let reference = try await readImageReference(from: provider) {
                    applyImage(reference)
                    return
                }
            } catch is CancellationError {
                return
            } catch let error as BackgroundImageStore.ImportError {
                imageDropError = error
                return
            } catch {
                imageDropError = .copyFailed
                return
            }
        }

        // A dragged file is the richer source, so try file URLs before text — a
        // Finder drag often advertises both.
        var fileProviderFailed = false
        for provider in providers {
            do {
                guard let url = try await readFileURL(from: provider) else { continue }
                do {
                    offerLoaded(try FileInputLoader.load(from: url))
                } catch let error as FileInputLoader.LoadError {
                    dropError = error
                } catch {
                    dropError = .unreadable
                }
                return
            } catch is CancellationError {
                return
            } catch {
                // A provider can advertise a file URL and fail only that coercion.
                // Keep looking so another provider or its plain-text representation
                // can still satisfy the drop before showing an error.
                fileProviderFailed = true
                continue
            }
        }

        // No file: fall back to dropped text, inferring the language from content.
        for provider in providers {
            do {
                guard let text = try await readText(from: provider),
                    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                let interpreted = LanguageDetector.interpret(text)
                offerLoaded(
                    FileInputLoader.LoadedFile(
                        text: interpreted.code, language: interpreted.language, filename: ""))
                return
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }

        if fileProviderFailed {
            dropError = .unreadable
        }
    }

    /// Loads immediately into an empty editor, or defers to the replace/append
    /// prompt when the editor already holds code.
    func offerLoaded(
        _ loaded: FileInputLoader.LoadedFile,
        startsLivingSnapshot: Bool = false
    ) {
        if settings.config.code.isEmpty {
            apply(
                loaded, replacing: true,
                startsLivingSnapshot: startsLivingSnapshot)
        } else {
            pendingDrop = PendingDrop(
                loaded: loaded,
                startsLivingSnapshot: startsLivingSnapshot)
        }
    }

    /// Resolves a pending replace/append choice from the confirmation dialog.
    func applyDrop(replacing: Bool) {
        guard let pending = pendingDrop else { return }
        apply(
            pending.loaded,
            replacing: replacing,
            startsLivingSnapshot: replacing && pending.startsLivingSnapshot)
        pendingDrop = nil
    }

    /// Writes a loaded drop into the live config. Replacing swaps the whole
    /// document and adopts the inferred language and filename; appending keeps the
    /// current language (the existing code defines it) and only grows the text.
    ///
    /// Either way this just fills the editor — it never records a Recent. The
    /// filename rides along in `metadata.filename` so a *later*
    /// capture/export reflects the source, honoring "Recents record loaded file
    /// metadata only when the user captures/exports".
    func apply(
        _ loaded: FileInputLoader.LoadedFile,
        replacing: Bool,
        startsLivingSnapshot: Bool = false
    ) {
        if replacing {
            session.livingSnapshot.stop()
        }
        if replacing, let sourceURL = loaded.sourceURL,
            environment.workspaceRecipes.applyRecipe(for: sourceURL, to: settings) != nil
        {
            Log.capture.info("Applied a workspace recipe to an explicitly loaded file")
        }
        loaded.apply(to: &settings.config, replacing: replacing)
        settings.noteLanguageUsed(settings.config.language)
        if startsLivingSnapshot {
            session.livingSnapshot.start(with: loaded)
        }
        Log.capture.info(
            "Editor drop loaded (\(loaded.text.count, privacy: .public) chars, \(loaded.language.rawValue, privacy: .public))"
        )
    }

    /// Presents a standard one-file picker and starts a volatile living snapshot after
    /// the selected text file replaces the editor. The picker is the consent boundary:
    /// no directory is scanned, no bookmark is stored, and access ends with this window.
    func openLivingSnapshotFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open a Live File")
        panel.message = String(
            localized:
                "Choose one source file. Vitrine will refresh clean editor content when that file is saved, only while this window remains open."
        )
        panel.prompt = String(localized: "Open & Watch")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task(name: "Open living snapshot") { [session] in
            do {
                let loaded = try await session.livingSnapshot.loadForOpening(from: url)
                try Task.checkCancellation()
                offerLoaded(loaded, startsLivingSnapshot: true)
            } catch is CancellationError {
                // Replacing the picker request or closing the window is ordinary lifecycle.
            } catch let error as FileInputLoader.LoadError {
                dropError = error
            } catch {
                dropError = .unreadable
            }
        }
    }

    /// Imports a dropped image into the foreground store and returns its reference, or
    /// `nil` when the provider carries no image. Handles both a dropped image **file**
    /// (Finder) and an in-app drag carrying image **bytes** (Preview, a browser).
    func readImageReference(from provider: NSItemProvider) async throws -> ImageReference? {
        let fileURL: URL?
        do {
            fileURL = try await readImageFileURL(from: provider)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Some providers advertise a file URL but fail that representation while
            // still serving their image bytes. Preserve the direct-data fallback.
            fileURL = nil
        }

        if let url = fileURL {
            let reference = try await foregroundImageStore.importImageConcurrently(from: url)
            guard await foregroundImageStore.preloadImage(for: reference) != nil else {
                throw BackgroundImageStore.ImportError.notAnImage
            }
            return reference
        }
        if let (data, ext) = try await readImageData(from: provider) {
            let reference = try await foregroundImageStore.importImageConcurrently(
                data: data, preferredExtension: ext)
            guard await foregroundImageStore.preloadImage(for: reference) != nil else {
                throw BackgroundImageStore.ImportError.notAnImage
            }
            return reference
        }
        return nil
    }

    /// A dropped file URL that points at an image file, or `nil` for a non-image file.
    func readImageFileURL(from provider: NSItemProvider) async throws -> URL? {
        guard let url = try await readFileURL(from: provider),
            let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image)
        else { return nil }
        return url
    }

    /// Reads raw image bytes (and a preferred extension) from a provider that carries an
    /// image directly, or `nil` when it carries none. Loading the original data preserves
    /// the source format instead of re-encoding through `NSImage`.
    func readImageData(from provider: NSItemProvider) async throws -> (Data, String)? {
        let imageType = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        }
        guard let imageType, let type = UTType(imageType) else { return nil }
        let waiter = ItemProviderLoadWaiter<Data?>()
        let data = try await waiter.wait(timeout: Self.itemProviderLoadTimeout) { completion in
            provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(data))
                }
            }
        }
        guard let data else { throw BackgroundImageStore.ImportError.copyFailed }
        return (data, type.preferredFilenameExtension ?? "")
    }

    /// Loads a beautified foreground image into the live document, replacing any prior
    /// content marks. The existing `code` is kept (rendered again if the image is later
    /// cleared), so switching to image mode is non-destructive.
    func applyImage(_ reference: ImageReference) {
        session.livingSnapshot.stop()
        settings.config.clearContentMarks()
        settings.config.foregroundImage = reference
        Log.capture.info("Editor drop loaded a foreground image")
    }

    /// Reads a dropped file's URL from a provider, or `nil` when it carries none.
    /// The coerced item is a `URL` (or URL bytes), which `FileInputLoader` then
    /// reads under a security-scoped access — no broad file entitlement is
    /// involved.
    func readFileURL(from provider: NSItemProvider) async throws -> URL? {
        let type = UTType.fileURL.identifier
        guard provider.hasItemConformingToTypeIdentifier(type) else { return nil }
        let waiter = ItemProviderLoadWaiter<URL?>()
        return try await waiter.wait(timeout: Self.itemProviderLoadTimeout) { completion in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                if let url = item as? URL {
                    completion(.success(url))
                } else if let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                {
                    completion(.success(url))
                } else {
                    completion(.success(nil))
                }
            }
            // Unlike the representation/object APIs, this legacy file-URL overload
            // exposes no Progress to cancel. The waiter still bounds its continuation.
            return nil
        }
    }

    /// Reads dropped plain text from a provider, or `nil` when it carries none.
    func readText(from provider: NSItemProvider) async throws -> String? {
        let waiter = ItemProviderLoadWaiter<String?>()
        return try await waiter.wait(timeout: Self.itemProviderLoadTimeout) { completion in
            provider.loadObject(ofClass: String.self) { string, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(string))
                }
            }
        }
    }
}

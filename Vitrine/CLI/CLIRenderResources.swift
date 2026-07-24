import AppKit
import Foundation

/// Prepares invocation-scoped image resources without touching persistent app storage.
enum CLIRenderResources {
    /// A local background imported for exactly one CLI invocation. The default store
    /// preserves normal app rendering when no path was requested; an imported image
    /// carries its temporary directory so the caller can remove it after every output
    /// in a render or batch has finished.
    struct PreparedBackground {
        var reference: ImageReference?
        var store: BackgroundImageStore
        var temporaryDirectory: URL?

        func removeTemporaryFiles() {
            guard let temporaryDirectory else { return }
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    /// Validated local watermark bytes plus the image decoded once for this invocation.
    struct PreparedWatermarkLogo {
        var data: Data
        var image: NSImage
    }

    /// Loads and validates a local watermark logo once per invocation. Keeping the
    /// bytes inline matches Brand Kit's self-contained render model and lets batch
    /// outputs reuse the same decoded source without touching persistent app storage.
    static func prepareWatermarkLogo(_ options: CLIOptions) throws -> PreparedWatermarkLogo? {
        guard let path = options.watermarkLogoPath else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        } catch {
            throw CLIError.inputUnreadable(path: path)
        }
        guard let image = NSImage(data: data) else {
            throw CLIError.inputNotImage(path: path)
        }
        return PreparedWatermarkLogo(data: data, image: image)
    }

    /// Imports a requested local background into an invocation-scoped store. The
    /// source is read-only and the copy is removed by the caller after rendering, so
    /// CLI automation never changes the user's persistent background collection.
    static func prepareBackground(_ options: CLIOptions) throws -> PreparedBackground {
        guard let path = options.backgroundImagePath else {
            return PreparedBackground(reference: nil, store: .container, temporaryDirectory: nil)
        }
        let sourceURL = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw CLIError.inputUnreadable(path: path)
        }

        let directory = temporaryImageDirectory()
        let store = BackgroundImageStore(directory: directory)
        do {
            let reference = try store.importImage(
                data: data, preferredExtension: sourceURL.pathExtension)
            return PreparedBackground(
                reference: reference, store: store, temporaryDirectory: directory)
        } catch BackgroundImageStore.ImportError.notAnImage {
            try? FileManager.default.removeItem(at: directory)
            throw CLIError.inputNotImage(path: path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw CLIError.renderFailed
        }
    }

    static func temporaryImageDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "VitrineCLI-\(UUID().uuidString)", isDirectory: true)
    }
}

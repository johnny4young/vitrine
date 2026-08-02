import Foundation

/// Keeps one explicitly selected source file connected to an editor window for
/// the lifetime of that window only.
///
/// The session never stores a bookmark or scans for files. It retains the file's
/// security-scoped access while active, compares a lightweight filesystem stamp,
/// and reloads only after the source changes. That stamp includes the file resource
/// identifier so saves implemented as atomic replacement are detected even when the
/// replacement has the same size.
///
/// External content is applied automatically only while the editor still matches
/// the last version loaded from disk. Once the user edits locally, a newer disk
/// version becomes pending and requires an explicit reload, so a background refresh
/// can never overwrite work in progress.
@MainActor
@Observable
final class LivingSnapshotSession {
    enum Status: Equatable {
        case inactive
        case watching
        case changeAvailable
        case unavailable
    }

    /// Filesystem operations are grouped behind value-typed closures so reconciliation
    /// can be exercised deterministically without broad filesystem access or timers.
    struct FileClient {
        var startAccess: @MainActor (URL) -> Bool
        var stopAccess: @MainActor (URL) -> Void
        var stamp: @MainActor (URL) throws -> FileStamp
        var load: @MainActor (URL) throws -> FileInputLoader.LoadedFile

        static let live = FileClient(
            startAccess: { $0.startAccessingSecurityScopedResource() },
            stopAccess: { $0.stopAccessingSecurityScopedResource() },
            stamp: FileStamp.read(from:),
            load: FileInputLoader.load(from:))
    }

    struct FileStamp: Equatable {
        var byteCount: Int
        var modificationDate: Date?
        var resourceIdentifier: String?
        var fileNumber: UInt64?
        var volumeNumber: UInt64?

        static func read(from url: URL) throws -> FileStamp {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .fileResourceIdentifierKey,
            ])
            guard values.isRegularFile == true else {
                throw FileInputLoader.LoadError.unreadable
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return FileStamp(
                byteCount: values.fileSize ?? -1,
                modificationDate: values.contentModificationDate,
                resourceIdentifier: values.fileResourceIdentifier.map(String.init(describing:)),
                fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
                volumeNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value)
        }
    }

    private(set) var status: Status = .inactive
    private(set) var displayName = ""

    var isActive: Bool { status != .inactive }

    private let settings: AppSettings
    private let client: FileClient
    private let pollingInterval: Duration
    private var sourceURL: URL?
    private var lastStamp: FileStamp?
    private var lastLoadedText = ""
    private var pollingTask: Task<Void, Never>?
    private var retainedSecurityScope = false

    init(
        settings: AppSettings,
        client: FileClient = .live,
        pollingInterval: Duration = .milliseconds(650)
    ) {
        self.settings = settings
        self.client = client
        self.pollingInterval = pollingInterval
    }

    /// Starts watching an already-loaded, explicitly selected file. The caller applies
    /// the initial document first; this method records it as the clean baseline and
    /// retains access only until ``stop()`` or the editor window closes.
    func start(with loaded: FileInputLoader.LoadedFile) {
        guard let sourceURL = loaded.sourceURL?.standardizedFileURL else {
            stop()
            return
        }

        stop()
        self.sourceURL = sourceURL
        displayName = loaded.filename.isEmpty ? sourceURL.lastPathComponent : loaded.filename
        lastLoadedText = loaded.text
        retainedSecurityScope = client.startAccess(sourceURL)
        // Re-read once after retaining access rather than trusting bytes selected before
        // a replace confirmation. If the source changed while that dialog was open, the
        // editor starts from the newest coherent version instead of recording a stale
        // baseline that no later fingerprint could distinguish.
        lastStamp = nil
        status = .unavailable
        checkForChanges()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await Task.sleep(for: self.pollingInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.checkForChanges()
            }
        }
    }

    /// Reads the current file stamp and reconciles a changed version. Kept internal so
    /// unit tests can advance the state without sleeping for the production interval.
    func checkForChanges() {
        guard let sourceURL else { return }

        let stamp: FileStamp
        do {
            stamp = try client.stamp(sourceURL)
        } catch {
            status = .unavailable
            return
        }

        guard stamp != lastStamp else {
            guard status == .unavailable else { return }
            do {
                reconcile(try client.load(sourceURL))
            } catch {
                // Metadata can remain readable after content access is revoked. Do not
                // claim recovery until the actual source bytes are readable again.
            }
            return
        }
        do {
            let loaded = try client.load(sourceURL)
            lastStamp = stamp
            reconcile(loaded)
        } catch {
            // An atomic save can briefly replace the destination between the stamp and
            // the read. Leave the session active; the next poll retries the exact path.
            status = .unavailable
        }
    }

    /// Discards local editor changes and adopts the newest readable version on disk.
    /// Returns whether a version was loaded so the UI can keep error feedback in state.
    @discardableResult
    func reloadFromDisk() -> Bool {
        guard let sourceURL else { return false }
        do {
            let loaded = try client.load(sourceURL)
            lastStamp = try? client.stamp(sourceURL)
            apply(loaded)
            return true
        } catch {
            status = .unavailable
            return false
        }
    }

    /// Dismisses the currently pending disk version without stopping the watcher. A
    /// later save can still be offered, while the editor's local text remains intact.
    func keepEditing() {
        guard status == .changeAvailable else { return }
        status = .watching
    }

    /// Releases the file access and all volatile source state. Nothing from a living
    /// snapshot is persisted into window restoration or app defaults.
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        if retainedSecurityScope, let sourceURL {
            client.stopAccess(sourceURL)
        }
        retainedSecurityScope = false
        sourceURL = nil
        lastStamp = nil
        lastLoadedText = ""
        displayName = ""
        status = .inactive
    }

    private func reconcile(_ loaded: FileInputLoader.LoadedFile) {
        guard loaded.text != lastLoadedText else {
            status = .watching
            return
        }

        guard settings.documentCode == lastLoadedText else {
            status = .changeAvailable
            return
        }
        apply(loaded)
    }

    private func apply(_ loaded: FileInputLoader.LoadedFile) {
        guard settings.documentCode != loaded.text else {
            lastLoadedText = loaded.text
            status = .watching
            return
        }
        loaded.apply(to: &settings.config, replacing: true)
        settings.noteLanguageUsed(settings.config.language)
        lastLoadedText = loaded.text
        status = .watching
        Log.capture.info(
            "Living snapshot refreshed (\(loaded.text.count, privacy: .public) chars)")
    }
}

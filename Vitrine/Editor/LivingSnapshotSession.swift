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

    /// Async filesystem operations live behind a Sendable value so production I/O can leave the
    /// main actor and tests can provide deterministic actors instead of touching the real disk.
    /// Security-scope ownership remains on the main actor because it follows the editor session's
    /// synchronous start/stop lifecycle.
    nonisolated struct FileClient: Sendable {
        var startAccess: @MainActor @Sendable (URL) -> Bool
        var stopAccess: @MainActor @Sendable (URL) -> Void
        var stamp: @Sendable (URL) async throws -> FileStamp
        var load: @Sendable (URL) async throws -> FileInputLoader.LoadedFile

        static let live = FileClient(
            startAccess: { $0.startAccessingSecurityScopedResource() },
            stopAccess: { $0.stopAccessingSecurityScopedResource() },
            stamp: { try await readStampConcurrently(from: $0) },
            load: { try await FileInputLoader.loadConcurrently(from: $0) })

        /// Metadata APIs are synchronous, so `@concurrent` is the explicit Swift 6.2 executor
        /// hop that prevents inode/resource-value inspection from blocking UI interaction.
        @concurrent
        private static func readStampConcurrently(from url: URL) async throws -> FileStamp {
            try Task.checkCancellation()
            let stamp = try FileStamp.read(from: url)
            try Task.checkCancellation()
            return stamp
        }

    }

    nonisolated struct FileStamp: Equatable, Sendable {
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

    private enum ReadRequest: Sendable {
        case reconcile(previousStamp: FileStamp?, recoverContent: Bool)
        case reload
    }

    private enum ReadResult: Sendable {
        case unchanged
        case loaded(
            FileInputLoader.LoadedFile,
            stamp: FileStamp?,
            replacingLocalEdits: Bool)
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
    private var fileReadTask: Task<Bool, Never>?
    private var openingTask: Task<FileInputLoader.LoadedFile, Error>?
    private var readGeneration: UInt64 = 0
    private var openingGeneration: UInt64 = 0
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

    /// Loads a candidate selected by the live-file picker without blocking the main actor.
    /// A newer picker request or session teardown invalidates the generation and cancels the
    /// stored task, so a late result cannot reopen or mutate a closed editor.
    func loadForOpening(from url: URL) async throws -> FileInputLoader.LoadedFile {
        openingTask?.cancel()
        openingGeneration &+= 1
        let generation = openingGeneration
        let client = client
        let task = Task(name: "Living snapshot initial read") {
            try await client.load(url)
        }
        openingTask = task

        do {
            let loaded = try await task.value
            try Task.checkCancellation()
            guard generation == openingGeneration else { throw CancellationError() }
            openingTask = nil
            return loaded
        } catch {
            if generation == openingGeneration {
                openingTask = nil
            }
            throw error
        }
    }

    /// Starts watching an already-loaded, explicitly selected file. The caller applies
    /// the initial document first; this method records it as the clean baseline and
    /// retains access only until ``stop()`` or the editor window closes.
    ///
    /// The returned task represents the immediate coherent re-read. Callers normally ignore it;
    /// tests await it directly rather than sleeping or racing the production polling interval.
    @discardableResult
    func start(with loaded: FileInputLoader.LoadedFile) -> Task<Bool, Never>? {
        guard let sourceURL = loaded.sourceURL?.standardizedFileURL else {
            stop()
            return nil
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
        status = .watching
        let initialRead = checkForChanges()

        pollingTask = Task(name: "Living snapshot polling") { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pollingInterval else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let read = self?.checkForChanges() else { return }
                _ = await read.value
            }
        }
        return initialRead
    }

    /// Reads the current file stamp and reconciles a changed version. The task is session-owned,
    /// cancellable, and generation-guarded so file replacement or window teardown cannot publish
    /// an obsolete result after an `await`.
    @discardableResult
    func checkForChanges() -> Task<Bool, Never>? {
        guard sourceURL != nil else { return nil }
        return scheduleRead(
            .reconcile(
                previousStamp: lastStamp,
                recoverContent: status == .unavailable))
    }

    /// Discards local editor changes and adopts the newest readable version on disk.
    /// The returned task resolves to whether a version was loaded; UI callers can ignore it while
    /// focused tests await the exact operation.
    @discardableResult
    func reloadFromDisk() -> Task<Bool, Never>? {
        guard sourceURL != nil else { return nil }
        return scheduleRead(.reload)
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
        readGeneration &+= 1
        openingGeneration &+= 1
        pollingTask?.cancel()
        pollingTask = nil
        fileReadTask?.cancel()
        fileReadTask = nil
        openingTask?.cancel()
        openingTask = nil
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

    private func scheduleRead(_ request: ReadRequest) -> Task<Bool, Never>? {
        guard let sourceURL else { return nil }

        fileReadTask?.cancel()
        readGeneration &+= 1
        let generation = readGeneration
        let client = client
        let task = Task(name: "Living snapshot file read") { [weak self] in
            do {
                let result = try await Self.read(
                    request, from: sourceURL, using: client)
                try Task.checkCancellation()
                guard let self else { return false }
                return self.finishRead(result, sourceURL: sourceURL, generation: generation)
            } catch is CancellationError {
                return false
            } catch {
                guard let self else { return false }
                return self.failRead(sourceURL: sourceURL, generation: generation)
            }
        }
        fileReadTask = task
        return task
    }

    nonisolated private static func read(
        _ request: ReadRequest,
        from sourceURL: URL,
        using client: FileClient
    ) async throws -> ReadResult {
        try Task.checkCancellation()
        switch request {
        case .reconcile(let previousStamp, let recoverContent):
            let stamp = try await client.stamp(sourceURL)
            try Task.checkCancellation()
            guard stamp != previousStamp || recoverContent else { return .unchanged }
            let loaded = try await client.load(sourceURL)
            try Task.checkCancellation()
            return .loaded(loaded, stamp: stamp, replacingLocalEdits: false)

        case .reload:
            let loaded = try await client.load(sourceURL)
            try Task.checkCancellation()
            let stamp: FileStamp?
            do {
                stamp = try await client.stamp(sourceURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The content is already coherent and bounded. Preserve existing behavior by
                // accepting it even when a following metadata lookup races an atomic save.
                stamp = nil
            }
            try Task.checkCancellation()
            return .loaded(loaded, stamp: stamp, replacingLocalEdits: true)
        }
    }

    private func finishRead(
        _ result: ReadResult,
        sourceURL: URL,
        generation: UInt64
    ) -> Bool {
        guard generation == readGeneration, self.sourceURL == sourceURL else { return false }
        fileReadTask = nil
        switch result {
        case .unchanged:
            return false
        case .loaded(let loaded, let stamp, let replacingLocalEdits):
            lastStamp = stamp
            if replacingLocalEdits {
                apply(loaded)
            } else {
                reconcile(loaded)
            }
            return true
        }
    }

    private func failRead(sourceURL: URL, generation: UInt64) -> Bool {
        guard generation == readGeneration, self.sourceURL == sourceURL else { return false }
        fileReadTask = nil
        // An atomic save can briefly replace the destination between metadata and content reads.
        // Leave the session active; the next poll retries the exact path and stamp.
        status = .unavailable
        return false
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

import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Living snapshot sessions")
struct LivingSnapshotSessionTests {
    private actor TestDisk {
        enum Failure: Error { case unavailable }

        var revision: Int
        var text: String
        var isReadable: Bool
        var shouldFailNextRead = false
        var failedAttempts = 0

        init(revision: Int = 1, text: String, isReadable: Bool = true) {
            self.revision = revision
            self.text = text
            self.isReadable = isReadable
        }

        func currentText() -> String { text }

        func update(
            revision: Int? = nil,
            text: String? = nil,
            isReadable: Bool? = nil
        ) {
            if let revision { self.revision = revision }
            if let text { self.text = text }
            if let isReadable { self.isReadable = isReadable }
        }

        func failNextRead() {
            shouldFailNextRead = true
        }

        func failedAttemptCount() -> Int { failedAttempts }

        func fileStamp() -> LivingSnapshotSession.FileStamp {
            LivingSnapshotSession.FileStamp(
                byteCount: revision,
                modificationDate: Date(timeIntervalSince1970: TimeInterval(revision)),
                resourceIdentifier: "revision-\(revision)",
                fileNumber: UInt64(revision),
                volumeNumber: 1)
        }

        func loadedFile(for url: URL) throws -> FileInputLoader.LoadedFile {
            guard isReadable else { throw Failure.unavailable }
            if shouldFailNextRead {
                failedAttempts += 1
                shouldFailNextRead = false
                throw Failure.unavailable
            }
            return FileInputLoader.LoadedFile(
                text: text,
                language: .swift,
                filename: url.lastPathComponent,
                sourceURL: url)
        }
    }

    /// A cancellation-insensitive filesystem double. Production cancellation cannot force a
    /// blocking POSIX read to return, so these continuations prove the generation guard rejects
    /// late bytes even after the owning task has been cancelled.
    private actor ControlledReads {
        private var requested: Set<URL> = []
        private var requestWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]
        private var loadContinuations:
            [URL: CheckedContinuation<FileInputLoader.LoadedFile, Never>] = [:]

        func load(_ url: URL) async -> FileInputLoader.LoadedFile {
            requested.insert(url)
            for waiter in requestWaiters.removeValue(forKey: url) ?? [] {
                waiter.resume()
            }
            return await withCheckedContinuation { continuation in
                loadContinuations[url] = continuation
            }
        }

        func waitUntilRequested(_ url: URL) async {
            guard !requested.contains(url) else { return }
            await withCheckedContinuation { continuation in
                requestWaiters[url, default: []].append(continuation)
            }
        }

        func resume(_ url: URL, text: String) {
            guard let continuation = loadContinuations.removeValue(forKey: url) else {
                Issue.record("No suspended read exists for \(url.lastPathComponent)")
                return
            }
            continuation.resume(
                returning: FileInputLoader.LoadedFile(
                    text: text,
                    language: .swift,
                    filename: url.lastPathComponent,
                    sourceURL: url))
        }
    }

    private func settings() -> AppSettings {
        AppSettings(
            defaults: testDefaults())
    }

    nonisolated private func loaded(
        _ text: String, url: URL
    ) -> FileInputLoader.LoadedFile {
        FileInputLoader.LoadedFile(
            text: text,
            language: .swift,
            filename: url.lastPathComponent,
            sourceURL: url)
    }

    nonisolated private func stamp(_ revision: Int) -> LivingSnapshotSession.FileStamp {
        LivingSnapshotSession.FileStamp(
            byteCount: revision,
            modificationDate: Date(timeIntervalSince1970: TimeInterval(revision)),
            resourceIdentifier: "revision-\(revision)",
            fileNumber: UInt64(revision),
            volumeNumber: 1)
    }

    private func wait(_ task: Task<Bool, Never>?) async -> Bool {
        guard let task else { return false }
        return await task.value
    }

    @Test func explicitSessionRetainsAndReleasesAccessWithoutPersistingAPath() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Example.swift")
        var starts: [URL] = []
        var stops: [URL] = []
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: {
                    starts.append($0)
                    return true
                },
                stopAccess: { stops.append($0) },
                stamp: { _ in stamp(1) },
                load: { _ in loaded("let value = 1", url: source) }),
            pollingInterval: .seconds(3_600))

        settings.documentCode = "let value = 1"
        _ = await wait(session.start(with: loaded("let value = 1", url: source)))

        #expect(session.status == .watching)
        #expect(session.displayName == "Example.swift")
        #expect(starts == [source])

        session.stop()

        #expect(session.status == .inactive)
        #expect(session.displayName.isEmpty)
        #expect(stops == [source])
    }

    @Test func cleanEditorRefreshesAutomatically() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "let value = 1")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in await disk.fileStamp() },
                load: { _ in try await disk.loadedFile(for: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = await disk.currentText()
        _ = await wait(session.start(with: loaded(await disk.currentText(), url: source)))

        await disk.update(revision: 2, text: "let value = 2")
        _ = await wait(session.checkForChanges())

        #expect(settings.documentCode == "let value = 2")
        #expect(session.status == .watching)
    }

    @Test func dirtyEditorRequiresAnExplicitReload() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "let value = 1")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in await disk.fileStamp() },
                load: { _ in try await disk.loadedFile(for: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = await disk.currentText()
        _ = await wait(session.start(with: loaded(await disk.currentText(), url: source)))

        settings.documentCode = "let localDraft = true"
        await disk.update(revision: 2, text: "let value = 2")
        _ = await wait(session.checkForChanges())

        #expect(settings.documentCode == "let localDraft = true")
        #expect(session.status == .changeAvailable)

        _ = await wait(session.reloadFromDisk())

        #expect(settings.documentCode == "let value = 2")
        #expect(session.status == .watching)
    }

    @Test func keepingLocalEditsDismissesOnlyTheCurrentNotice() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "one")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in await disk.fileStamp() },
                load: { _ in try await disk.loadedFile(for: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = await disk.currentText()
        _ = await wait(session.start(with: loaded(await disk.currentText(), url: source)))
        settings.documentCode = "local"

        await disk.update(revision: 2, text: "two")
        _ = await wait(session.checkForChanges())
        session.keepEditing()

        #expect(settings.documentCode == "local")
        #expect(session.status == .watching)

        await disk.update(revision: 3, text: "three")
        _ = await wait(session.checkForChanges())

        #expect(settings.documentCode == "local")
        #expect(session.status == .changeAvailable)
    }

    @Test func transientReadFailureRetriesTheSameFingerprint() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "one")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in await disk.fileStamp() },
                load: { _ in try await disk.loadedFile(for: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = "one"
        _ = await wait(session.start(with: loaded("one", url: source)))

        await disk.update(revision: 2, text: "two")
        await disk.failNextRead()
        _ = await wait(session.checkForChanges())
        #expect(session.status == .unavailable)
        #expect(settings.documentCode == "one")

        _ = await wait(session.checkForChanges())
        #expect(await disk.failedAttemptCount() == 1)
        #expect(session.status == .watching)
        #expect(settings.documentCode == "two")
    }

    @Test func startReconcilesAChangeMadeDuringReplacementConfirmation() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        settings.documentCode = "one"
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(2) },
                load: { _ in loaded("two", url: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }

        _ = await wait(session.start(with: loaded("one", url: source)))

        #expect(settings.documentCode == "two")
        #expect(session.status == .watching)
    }

    @Test func unavailableStatusRequiresARealContentReadToRecover() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "one", isReadable: false)
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(1) },
                load: { _ in try await disk.loadedFile(for: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = "one"
        _ = await wait(session.start(with: loaded("one", url: source)))

        _ = await wait(session.reloadFromDisk())
        #expect(session.status == .unavailable)

        _ = await wait(session.checkForChanges())
        #expect(session.status == .unavailable)

        await disk.update(isReadable: true)
        _ = await wait(session.checkForChanges())
        #expect(session.status == .watching)
    }

    @Test func unchangedContentDoesNotClobberLocalPresentationState() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "same")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in await disk.fileStamp() },
                load: { _ in loaded("same", url: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = "same"
        _ = await wait(session.start(with: loaded("same", url: source)))
        settings.config.highlightedLineRanges = [1...1]

        await disk.update(revision: 2)
        _ = await wait(session.checkForChanges())

        #expect(settings.config.highlightedLineRanges == [1...1])
        #expect(session.status == .watching)
    }

    @Test func explicitReloadOfUnchangedContentPreservesContentMarks() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(1) },
                load: { _ in loaded("same", url: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = "same"
        _ = await wait(session.start(with: loaded("same", url: source)))
        settings.config.highlightedLineRanges = [1...1]

        #expect(await wait(session.reloadFromDisk()))

        #expect(settings.config.highlightedLineRanges == [1...1])
        #expect(session.status == .watching)
    }

    @Test func aLateReadFromThePreviousFileCannotOverwriteTheNewGeneration() async throws {
        let settings = settings()
        let firstURL = URL(fileURLWithPath: "/tmp/First.swift")
        let secondURL = URL(fileURLWithPath: "/tmp/Second.swift")
        let reads = ControlledReads()
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(1) },
                load: { await reads.load($0) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }

        settings.documentCode = "first initial"
        let firstTask = session.start(with: loaded("first initial", url: firstURL))
        await reads.waitUntilRequested(firstURL)

        settings.documentCode = "second initial"
        let secondTask = session.start(with: loaded("second initial", url: secondURL))
        await reads.waitUntilRequested(secondURL)
        await reads.resume(secondURL, text: "second newest")
        #expect(await wait(secondTask))

        await reads.resume(firstURL, text: "first stale")
        #expect(!(await wait(firstTask)))
        #expect(settings.documentCode == "second newest")
        #expect(session.displayName == "Second.swift")
        #expect(session.status == .watching)
    }

    @Test func stoppingTheSessionRejectsAReadThatFinishesAfterWindowClose() async throws {
        let settings = settings()
        let source = URL(fileURLWithPath: "/tmp/Closing.swift")
        let reads = ControlledReads()
        var stoppedURLs: [URL] = []
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in true },
                stopAccess: { stoppedURLs.append($0) },
                stamp: { _ in stamp(1) },
                load: { await reads.load($0) }),
            pollingInterval: .seconds(3_600))

        settings.documentCode = "window content"
        let task = session.start(with: loaded("window content", url: source))
        await reads.waitUntilRequested(source)
        session.stop()

        await reads.resume(source, text: "late disk content")
        #expect(!(await wait(task)))
        #expect(settings.documentCode == "window content")
        #expect(session.status == .inactive)
        #expect(session.displayName.isEmpty)
        #expect(stoppedURLs == [source])
    }

    @Test func aNewPickerRequestInvalidatesAnOlderOpeningRead() async throws {
        let settings = settings()
        let firstURL = URL(fileURLWithPath: "/tmp/OldSelection.swift")
        let secondURL = URL(fileURLWithPath: "/tmp/NewSelection.swift")
        let reads = ControlledReads()
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(1) },
                load: { await reads.load($0) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }

        let firstTask = Task {
            try await session.loadForOpening(from: firstURL)
        }
        await reads.waitUntilRequested(firstURL)
        let secondTask = Task {
            try await session.loadForOpening(from: secondURL)
        }
        await reads.waitUntilRequested(secondURL)

        await reads.resume(secondURL, text: "new selection")
        let secondLoaded = try await secondTask.value
        #expect(secondLoaded.text == "new selection")

        await reads.resume(firstURL, text: "stale selection")
        await #expect(throws: CancellationError.self) {
            try await firstTask.value
        }
    }

    @Test func sameSizeAtomicReplacementIsDetectedEndToEnd() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineLivingSnapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Live.swift")
        try Data("one".utf8).write(to: source)

        let settings = settings()
        let initial = try FileInputLoader.load(from: source)
        settings.documentCode = initial.text
        let session = LivingSnapshotSession(
            settings: settings,
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        _ = await wait(session.start(with: initial))

        // Atomic writes replace the original inode. The text deliberately keeps the
        // same byte count so resource identity, not file size, proves the change.
        try Data("two".utf8).write(to: source, options: .atomic)
        _ = await wait(session.checkForChanges())

        #expect(settings.documentCode == "two")
        #expect(session.status == .watching)
    }
}

import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Living snapshot sessions")
struct LivingSnapshotSessionTests {
    private final class TestDisk {
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
    }

    private func settings() throws -> AppSettings {
        try AppSettings(
            defaults: testDefaults())
    }

    private func loaded(_ text: String, url: URL) -> FileInputLoader.LoadedFile {
        FileInputLoader.LoadedFile(
            text: text,
            language: .swift,
            filename: url.lastPathComponent,
            sourceURL: url)
    }

    private func stamp(_ revision: Int) -> LivingSnapshotSession.FileStamp {
        LivingSnapshotSession.FileStamp(
            byteCount: revision,
            modificationDate: Date(timeIntervalSince1970: TimeInterval(revision)),
            resourceIdentifier: "revision-\(revision)",
            fileNumber: UInt64(revision),
            volumeNumber: 1)
    }

    @Test func explicitSessionRetainsAndReleasesAccessWithoutPersistingAPath() throws {
        let settings = try settings()
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
        session.start(with: loaded("let value = 1", url: source))

        #expect(session.status == .watching)
        #expect(session.displayName == "Example.swift")
        #expect(starts == [source])

        session.stop()

        #expect(session.status == .inactive)
        #expect(session.displayName.isEmpty)
        #expect(stops == [source])
    }

    @Test func cleanEditorRefreshesAutomatically() throws {
        let settings = try settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "let value = 1")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(disk.revision) },
                load: { _ in loaded(disk.text, url: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = disk.text
        session.start(with: loaded(disk.text, url: source))

        disk.revision = 2
        disk.text = "let value = 2"
        session.checkForChanges()

        #expect(settings.documentCode == "let value = 2")
        #expect(session.status == .watching)
    }

    @Test func dirtyEditorRequiresAnExplicitReload() throws {
        let settings = try settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "let value = 1")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(disk.revision) },
                load: { _ in loaded(disk.text, url: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = disk.text
        session.start(with: loaded(disk.text, url: source))

        settings.documentCode = "let localDraft = true"
        disk.revision = 2
        disk.text = "let value = 2"
        session.checkForChanges()

        #expect(settings.documentCode == "let localDraft = true")
        #expect(session.status == .changeAvailable)

        session.reloadFromDisk()

        #expect(settings.documentCode == "let value = 2")
        #expect(session.status == .watching)
    }

    @Test func keepingLocalEditsDismissesOnlyTheCurrentNotice() throws {
        let settings = try settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "one")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(disk.revision) },
                load: { _ in loaded(disk.text, url: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = disk.text
        session.start(with: loaded(disk.text, url: source))
        settings.documentCode = "local"

        disk.revision = 2
        disk.text = "two"
        session.checkForChanges()
        session.keepEditing()

        #expect(settings.documentCode == "local")
        #expect(session.status == .watching)

        disk.revision = 3
        disk.text = "three"
        session.checkForChanges()

        #expect(settings.documentCode == "local")
        #expect(session.status == .changeAvailable)
    }

    @Test func transientReadFailureRetriesTheSameFingerprint() throws {
        enum TestError: Error { case unavailable }

        let settings = try settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "one")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(disk.revision) },
                load: { _ in
                    if disk.shouldFailNextRead {
                        disk.failedAttempts += 1
                        disk.shouldFailNextRead = false
                        throw TestError.unavailable
                    }
                    return loaded(disk.text, url: source)
                }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = "one"
        session.start(with: loaded("one", url: source))

        disk.revision = 2
        disk.text = "two"
        disk.shouldFailNextRead = true
        session.checkForChanges()
        #expect(session.status == .unavailable)
        #expect(settings.documentCode == "one")

        session.checkForChanges()
        #expect(disk.failedAttempts == 1)
        #expect(session.status == .watching)
        #expect(settings.documentCode == "two")
    }

    @Test func startReconcilesAChangeMadeDuringReplacementConfirmation() throws {
        let settings = try settings()
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

        session.start(with: loaded("one", url: source))

        #expect(settings.documentCode == "two")
        #expect(session.status == .watching)
    }

    @Test func unavailableStatusRequiresARealContentReadToRecover() throws {
        enum TestError: Error { case unavailable }

        let settings = try settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "one", isReadable: false)
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(1) },
                load: { _ in
                    guard disk.isReadable else { throw TestError.unavailable }
                    return loaded(disk.text, url: source)
                }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = "one"
        session.start(with: loaded("one", url: source))

        session.reloadFromDisk()
        #expect(session.status == .unavailable)

        session.checkForChanges()
        #expect(session.status == .unavailable)

        disk.isReadable = true
        session.checkForChanges()
        #expect(session.status == .watching)
    }

    @Test func unchangedContentDoesNotClobberLocalPresentationState() throws {
        let settings = try settings()
        let source = URL(fileURLWithPath: "/tmp/Live.swift")
        let disk = TestDisk(text: "same")
        let session = LivingSnapshotSession(
            settings: settings,
            client: .init(
                startAccess: { _ in false },
                stopAccess: { _ in },
                stamp: { _ in stamp(disk.revision) },
                load: { _ in loaded("same", url: source) }),
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        settings.documentCode = "same"
        session.start(with: loaded("same", url: source))
        settings.config.highlightedLineRanges = [1...1]

        disk.revision = 2
        session.checkForChanges()

        #expect(settings.config.highlightedLineRanges == [1...1])
        #expect(session.status == .watching)
    }

    @Test func explicitReloadOfUnchangedContentPreservesContentMarks() throws {
        let settings = try settings()
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
        session.start(with: loaded("same", url: source))
        settings.config.highlightedLineRanges = [1...1]

        #expect(session.reloadFromDisk())

        #expect(settings.config.highlightedLineRanges == [1...1])
        #expect(session.status == .watching)
    }

    @Test func sameSizeAtomicReplacementIsDetectedEndToEnd() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineLivingSnapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Live.swift")
        try Data("one".utf8).write(to: source)

        let settings = try settings()
        let initial = try FileInputLoader.load(from: source)
        settings.documentCode = initial.text
        let session = LivingSnapshotSession(
            settings: settings,
            pollingInterval: .seconds(3_600))
        defer { session.stop() }
        session.start(with: initial)

        // Atomic writes replace the original inode. The text deliberately keeps the
        // same byte count so resource identity, not file size, proves the change.
        try Data("two".utf8).write(to: source, options: .atomic)
        session.checkForChanges()

        #expect(settings.documentCode == "two")
        #expect(session.status == .watching)
    }
}

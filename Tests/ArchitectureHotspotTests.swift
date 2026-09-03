import Foundation
import Testing

@testable import Vitrine

@Suite("Architecture hotspot boundaries")
struct ArchitectureHotspotTests {
    @Test func terminalScreenResponsibilitiesStayPhysicallySeparated() throws {
        let terminal = Self.repositoryRoot.appending(path: "VitrineDomain/Terminal")
        let state = try Self.source("TerminalGrid.swift", in: terminal)
        let scanner = try Self.source("TerminalScreen+Scanner.swift", in: terminal)
        let parser = try Self.source("TerminalScreen+Parser.swift", in: terminal)
        let operations = try Self.source("TerminalScreen+Operations.swift", in: terminal)
        let serialization = try Self.source("TerminalScreen+Serialization.swift", in: terminal)

        #expect(state.contains("struct TerminalScreen"))
        #expect(!state.contains("mutating func feed"))
        #expect(scanner.contains("usesScreenAddressing"))
        #expect(parser.contains("mutating func feed"))
        #expect(operations.contains("mutating func putChar"))
        #expect(serialization.contains("public func runs"))
    }

    @Test func webSnapshotWindowOwnsPresentationButNotCaptureOrchestration() throws {
        let web = Self.repositoryRoot.appending(path: "Vitrine/WebRendering")
        let window = try Self.source("WebSnapshotWindowController.swift", in: web)
        let model = try Self.source("WebSnapshotModel.swift", in: web)
        let orchestration = try Self.source("WebSnapshotCaptureOrchestration.swift", in: web)

        #expect(window.contains("final class WebSnapshotWindowController"))
        #expect(window.contains("func windowWillClose"))
        #expect(!window.contains("func render(settings:"))
        #expect(model.contains("final class WebSnapshotModel"))
        #expect(model.contains("func cancelRender"))
        #expect(!model.contains("withTaskGroup"))
        #expect(orchestration.contains("extension WebSnapshotModel"))
        #expect(orchestration.contains("withTaskGroup"))
        #expect(!orchestration.contains("NSWindow"))
    }

    @Test func webSessionStorageAndInteractiveWindowRemainSeparateOwners() throws {
        let web = Self.repositoryRoot.appending(path: "Vitrine/WebRendering")
        let store = try Self.source("WebSessionStore.swift", in: web)
        let window = try Self.source("WebSessionWindowController.swift", in: web)

        #expect(store.contains("enum WebSessionStore"))
        #expect(store.contains("clearSessions"))
        #expect(!store.contains("NSWindow"))
        #expect(window.contains("final class WebSessionWindowController"))
        #expect(window.contains("private var webView"))
        #expect(!window.contains("removeData(ofTypes:"))
    }

    private static var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }
}

import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

/// Copy Command reads the window's own session, which diverges from the app-wide default as
/// soon as the user edits it.
@MainActor
@Suite("Editor reproduction command")
struct EditorReproductionCommandTests {
    private func makeEnvironment() throws -> AppEnvironment {
        AppEnvironment(defaults: testDefaults())
    }

    @Test func theSessionsRedactionAndStyleReachTheLineWhileTheDefaultStaysClean() throws {
        let environment = try makeEnvironment()
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 61), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer { session.discard() }
        session.settings.documentCode = "let visible = 1\nlet secret = \"hunter2\""
        session.settings.style.redactedLineRanges = [2...2]
        session.settings.style.theme = Theme.theme(withID: "dracula")

        let defaultLine = environment.appSettings.reproductionCommand.outcome()
        #expect(defaultLine == .command("vitrine render input.swift --out image.png"))

        guard case .command(let line) = session.settings.reproductionCommand.outcome() else {
            Issue.record("The session should have a command")
            return
        }
        #expect(line.contains("--redact-lines 2 --redact-secrets"))
        #expect(line.contains("--theme dracula"))
        #expect(!line.contains("hunter2"))
    }

    @Test func limitsComeFromTheSessionNotTheDefault() throws {
        let environment = try makeEnvironment()
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 62), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer { session.discard() }
        session.settings.style.annotations = [
            Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))
        ]
        session.settings.style.foregroundImage = ImageReference(fileName: "pasted.png")

        #expect(
            session.settings.reproductionCommand.outcome()
                == .unavailable([.annotations, .pastedImage]))
        guard case .command = environment.appSettings.reproductionCommand.outcome() else {
            Issue.record("The default has neither annotations nor an image")
            return
        }
    }

    @Test func theSessionsDestinationAndExportSettingsReachTheLine() throws {
        let environment = try makeEnvironment()
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 63), environment: environment,
            feedback: .noOp, presentation: .noOp)
        defer { session.discard() }
        session.settings.selectPreset(try #require(ExportPreset.preset(withID: "twitter")))
        session.settings.export.scale = 3
        session.settings.export.format = .pdf
        session.settings.export.colorProfile = .displayP3

        guard case .command(let line) = session.settings.reproductionCommand.outcome() else {
            Issue.record("The session should have a command")
            return
        }
        #expect(line.contains("--out image.pdf"))
        #expect(line.contains("--preset twitter --scale 3 --profile p3"))
    }
}

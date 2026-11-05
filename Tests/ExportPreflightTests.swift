import AppKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

// Assembled at runtime so secret-shaped fixtures never trip push protection.
private let token = "gh" + "p_" + String(repeating: "x", count: 36)
private let awsKey = "AK" + "IA" + String(repeating: "A", count: 16)

private func codeConfig(_ code: String) -> SnapshotConfig {
    var config = SnapshotConfig()
    config.code = code
    config.language = .swift
    return config
}

@Suite("Export pre-flight report")
struct ExportPreflightReportTests {
    @Test func cleanDocumentsHaveNothingToFlag() {
        #expect(ExportPreflight(codeConfig("let answer = 42"), payload: .image).isClean)
        var image = codeConfig("let hidden = \"\(token)\"")
        image.foregroundImage = ImageReference(fileName: "a.png")
        #expect(
            ExportPreflight(image, payload: .image).isClean,
            "Hidden source is not part of an image export")
    }

    @Test func namesRowsAndKindsAndNeverTheMatchedText() {
        let report = ExportPreflight(
            codeConfig("let a = 1\nlet b = \"\(token)\"\nlet c = \"\(awsKey)\""),
            payload: .image)
        #expect(report.redactableLines == [2, 3])
        #expect(
            report.findings.contains { $0.location == .lines(2...2) && $0.kind == "github-token" })
        #expect(
            report.findings.contains { $0.location == .lines(3...3) && $0.kind == "aws-access-key" }
        )
        #expect(!String(describing: report).contains(token))
        #expect(!String(describing: report).contains(awsKey))
    }

    @Test func privateKeyBlockReadsAsOneFindingButRedactsEveryRow() {
        let pem = [
            "-----BEGIN RSA PRIVATE " + "KEY-----", "bWF0ZXJpYWw=", "bW9yZQ==",
            "-----END RSA PRIVATE " + "KEY-----",
        ]
        let report = ExportPreflight(
            codeConfig((["let a = 1"] + pem).joined(separator: "\n")), payload: .image)
        #expect(report.findings == [.init(location: .lines(2...5), kind: "private-key")])
        #expect(report.redactableLines == [2, 3, 4, 5])
        #expect(report.redactions(adding: []) == [2...5])
    }

    @Test func redactingOnlyTheBannerStillFlagsTheKeyBody() {
        var config = codeConfig(
            ["-----BEGIN RSA PRIVATE " + "KEY-----", "bWF0ZXJpYWw="].joined(separator: "\n"))
        config.redactedLineRanges = [1...1]
        #expect(ExportPreflight(config, payload: .image).redactableLines == [2])
        config.redactedLineRanges = [1...2]
        #expect(ExportPreflight(config, payload: .image).isClean)
    }

    @Test func redactionKeepsExistingRanges() {
        let report = ExportPreflight(codeConfig("a\n\(token)"), payload: .image)
        #expect(report.redactions(adding: [5...6]) == [2...2, 5...6])
    }

    @Test func redactedExportCarriesTheSecretInNoTextOutput() {
        var config = codeConfig("let a = 1\nlet b = \"\(token)\"")
        config.redactedLineRanges = ExportPreflight(config, payload: .image).redactions(adding: [])
        for text in [
            config.sidecarText, config.richClipboardText,
            MarkdownExport.document(for: config, imageSource: "image.png"),
            HTMLExport.document(for: config, imageSource: "image.png"),
        ] {
            #expect(!text.contains(token))
        }
    }

    @Test func terminalRowsAreScreenRowsNotTranscriptLines() {
        var config = SnapshotConfig()
        config.language = .terminal
        config.code = "first\n\u{1B}[31m\(token)\u{1B}[0m\n"
        #expect(ExportPreflight(config, payload: .image).redactableLines == [2])
    }

    @Test func overwrittenTerminalSecretOnlyMattersWhereTheTranscriptTravels() throws {
        var config = SnapshotConfig()
        config.language = .terminal
        config.code = "\(token)\r\u{1B}[2Kclean\n"
        try #require(!config.sidecarText.contains(token))

        #expect(
            ExportPreflight(config, payload: .image).isClean,
            "The image and sidecars show the resolved screen")
        let link = ExportPreflight(config, payload: .transcript)
        #expect(link.findings == [.init(location: .terminalTranscript, kind: "github-token")])
        #expect(link.redactableLines.isEmpty)

        config.redactedLineRanges = [1...1]
        #expect(
            ExportPreflight(config, payload: .transcript).isClean,
            "Any redaction already drops the transcript from a share link")
    }

    @Test func headerAnnotationAndDescriptionTextAreFlaggedButNotRedactable() throws {
        var config = codeConfig("let a = 1")
        config.metadata = SnapshotMetadata(title: "key \(token)")
        config.altText = try SnapshotAltText.normalized(awsKey)
        let report = ExportPreflight(config, payload: .text)
        #expect(report.redactableLines.isEmpty)
        #expect(Set(report.findings.map(\.location)) == [.label])
        #expect(Set(report.findings.map(\.kind)) == ["github-token", "aws-access-key"])
    }

    @Test func descriptionOnlyMattersWhereItIsDelivered() throws {
        var config = codeConfig("let a = 1")
        config.altText = try SnapshotAltText.normalized(token)
        #expect(ExportPreflight(config, payload: .image).isClean, "Pixels never carry alt text")
        #expect(!ExportPreflight(config, payload: .text).isClean)
        #expect(!ExportPreflight(config, payload: .transcript).isClean)
    }

    @Test func aShareLinkReportsAnOverwrittenSecretBesideAVisibleOne() throws {
        let hidden = "gh" + "p_" + String(repeating: "y", count: 36)
        var config = SnapshotConfig()
        config.language = .terminal
        config.code = "\(hidden)\r\u{1B}[2K\n\(awsKey)\n"
        try #require(!config.sidecarText.contains(hidden))

        let link = ExportPreflight(config, payload: .transcript)
        #expect(link.redactableLines == [2])
        #expect(link.findings.contains(.init(location: .terminalTranscript, kind: "github-token")))
        #expect(
            !ExportPreflight(config, payload: .image).findings.contains {
                $0.kind == "github-token"
            })
    }

    @Test func aShareLinkAcknowledgementCoversTheTranscriptItDelivers() {
        func config(hidden: String) -> SnapshotConfig {
            var config = SnapshotConfig()
            config.language = .terminal
            config.code = "\(hidden)\r\u{1B}[2K\n\(awsKey)\n"
            return config
        }
        let first = config(hidden: token)
        let second = config(hidden: "gh" + "p_" + String(repeating: "y", count: 36))
        #expect(first.sidecarText == second.sidecarText, "Both documents show the same screen")
        #expect(
            ExportPreflight(first, payload: .transcript).acknowledgement(for: .copy)
                != ExportPreflight(second, payload: .transcript).acknowledgement(for: .copy))
    }

    @Test func acknowledgementSeparatesWhatIsDelivered() {
        let config = codeConfig(token)
        let image = ExportPreflight(config, payload: .image).acknowledgement(for: .copy)
        #expect(image != ExportPreflight(config, payload: .text).acknowledgement(for: .copy))
        #expect(image != ExportPreflight(config, payload: .transcript).acknowledgement(for: .copy))
    }

    @Test func acknowledgementFollowsContentAndDestination() {
        let config = codeConfig(token)
        let report = ExportPreflight(config, payload: .image)
        #expect(
            report.acknowledgement(for: .copy)
                == ExportPreflight(config, payload: .image).acknowledgement(for: .copy))
        #expect(report.acknowledgement(for: .copy) != report.acknowledgement(for: .share))
        let other = codeConfig("gh" + "p_" + String(repeating: "y", count: 36))
        #expect(
            report.acknowledgement(for: .copy)
                != ExportPreflight(other, payload: .image).acknowledgement(for: .copy)
        )
    }
}

@Suite("Export pre-flight gate")
struct ExportPreflightGateTests {
    private final class ResolverSpy {
        var calls: [ExportPreflight.Action] = []
        var answer = ExportPreflightPrompt.Choice.cancel

        var presentation: EditorPresentation {
            EditorPresentation(
                presentPin: { _ in }, presentShare: { _, _ in }, batchExport: .noOp,
                resolvePreflight: { [self] _, action in
                    calls.append(action)
                    return answer
                })
        }
    }

    private func settings(_ code: String) -> AppSettings {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.code = code
        settings.config.language = .swift
        return settings
    }

    @Test func aCleanDocumentNeverAsks() {
        let spy = ResolverSpy()
        #expect(
            spy.presentation.clearsPreflight(
                of: settings("let a = 1"), for: .copy, delivering: .image))
        #expect(spy.calls.isEmpty)
    }

    @Test func cancelStopsTheExportAndLeavesTheDocumentAlone() {
        let spy = ResolverSpy()
        let document = settings("let a = \"\(token)\"")
        #expect(!spy.presentation.clearsPreflight(of: document, for: .save, delivering: .image))
        #expect(spy.calls == [.save])
        #expect(document.config.redactedLineRanges.isEmpty)
    }

    @Test func redactAppliesOnlyAfterTheChoiceAndMergesWithManualRanges() {
        let spy = ResolverSpy()
        spy.answer = .redact
        let document = settings("let a = 1\nlet b = \"\(token)\"\nlet c = 3\nlet d = 4")
        document.config.redactedLineRanges = [4...4]
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .image))
        #expect(document.exportConfig.redactedLineRanges == [2...2, 4...4])
        #expect(!document.exportConfig.sidecarText.contains(token))

        spy.calls = []
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .image))
        #expect(spy.calls.isEmpty, "A redacted document has nothing left to flag")
    }

    @Test func anywayKeepsTheExportAndAsksOncePerDestinationAndContent() {
        let spy = ResolverSpy()
        spy.answer = .proceed
        let document = settings("let a = \"\(token)\"")
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .image))
        #expect(document.exportConfig.redactedLineRanges.isEmpty)
        #expect(document.exportConfig.sidecarText.contains(token), "The export stays as requested")

        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .image))
        #expect(spy.calls == [.copy])
        #expect(spy.presentation.clearsPreflight(of: document, for: .share, delivering: .image))
        #expect(spy.calls == [.copy, .share])

        document.config.code += "\nlet more = 1"
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .image))
        #expect(spy.calls == [.copy, .share, .copy], "Edited content is a new decision")
    }

    @Test func aShareLinkAsksAboutTerminalHistoryTheImageDoesNotShow() {
        let spy = ResolverSpy()
        let document = settings("\(token)\r\u{1B}[2Kclean\n")
        document.config.language = .terminal
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .image))
        #expect(spy.calls.isEmpty)
        #expect(
            !spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .transcript))
    }

    @Test func anywayOnTheImageDoesNotCoverItsTextForms() {
        let spy = ResolverSpy()
        spy.answer = .proceed
        let document = settings("let a = \"\(token)\"")
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .image))
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .text))
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .transcript))
        #expect(spy.calls == [.copy, .copy, .copy], "Each exposure is its own decision")
        #expect(spy.presentation.clearsPreflight(of: document, for: .copy, delivering: .text))
        #expect(spy.calls.count == 3)
    }

    @Test func textRidersMakeAnImageCopyATextPayload() {
        let document = settings("let a = 1")
        document.export.richClipboard = false
        document.export.textSidecar = false
        #expect(EditorPresentation.copyPayload(of: document) == .image)
        document.export.textSidecar = true
        #expect(EditorPresentation.copyPayload(of: document) == .text)
        document.export.textSidecar = false
        document.export.richClipboard = true
        #expect(EditorPresentation.copyPayload(of: document) == .text)
        document.export.format = .png
        #expect(EditorPresentation.savePayload(of: document) == .image)
        document.export.format = .pdf
        #expect(EditorPresentation.savePayload(of: document) == .text)
    }

    @Test func aDocumentThatChangesDuringTheDialogIsCheckedAgain() {
        let document = settings("let a = \"\(token)\"")
        var calls = 0
        let presentation = EditorPresentation(
            presentPin: { _ in }, presentShare: { _, _ in }, batchExport: .noOp,
            resolvePreflight: { _, _ in
                calls += 1
                // An asynchronous format landing while the dialog is open moves the secret.
                if calls == 1 { document.config.code = "// header\nlet a = \"\(token)\"" }
                return .redact
            })
        #expect(presentation.clearsPreflight(of: document, for: .copy, delivering: .text))
        #expect(calls == 2)
        #expect(document.exportConfig.redactedLineRanges == [2...2])
        #expect(!document.exportConfig.sidecarText.contains(token))
    }

    @Test func anywayDoesNotCoverContentThatChangedDuringTheDialog() {
        let document = settings("let a = \"\(token)\"")
        var calls = 0
        let presentation = EditorPresentation(
            presentPin: { _ in }, presentShare: { _, _ in }, batchExport: .noOp,
            resolvePreflight: { _, _ in
                calls += 1
                if calls == 1 { document.config.code = "let b = \"\(awsKey)\"" }
                return calls == 1 ? .proceed : .cancel
            })
        #expect(!presentation.clearsPreflight(of: document, for: .copy, delivering: .text))
        #expect(calls == 2)
    }

    @Test func theMenuCopyAsksBeforeTouchingThePasteboard() throws {
        let spy = ResolverSpy()
        let document = settings("let a = \"\(token)\"")
        document.export.textSidecar = true
        document.outputBehavior.closeAfterCopy = false
        let session = EditorSession(
            identity: EditorWindowIdentity(index: 61),
            environment: AppEnvironment(defaults: testDefaults()),
            feedback: .noOp, presentation: spy.presentation, settings: document)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        session.copyImage(closing: nil, pasteboard: pasteboard)
        #expect(spy.calls == [.copy])
        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)

        spy.answer = .redact
        session.copyImage(closing: nil, pasteboard: pasteboard)
        let text = try #require(pasteboard.string(forType: .string))
        #expect(text.contains(SnapshotConfig.redactedLinePlaceholder))
        #expect(!text.contains(token))
    }
}

@Suite("Quick capture pre-flight", .serialized)
struct QuickCapturePreflightTests {
    private func settings(autoCopy: Bool) -> AppSettings {
        let settings = AppSettings(defaults: testDefaults())
        settings.outputBehavior.autoCopy = autoCopy
        settings.outputBehavior.alsoSaveToFile = false
        return settings
    }

    @Test func cancelRecordsAndCopiesNothing() {
        let recents = RecentsStore(defaults: testDefaults())
        var consentAsked = false
        let result = QuickCapture.capture(
            settings: settings(autoCopy: true), recents: recents,
            clipboard: { "let a = \"\(token)\"" },
            historyConsent: { _ in
                consentAsked = true
                return .doNotSave
            },
            preflight: { _, _ in .cancel })
        #expect(result == .nonProducing(.cancelled))
        #expect(recents.captures.isEmpty)
        #expect(!consentAsked)
    }

    @Test func redactSanitizesTheCaptureSoHistoryNeedsNoConsent() throws {
        let recents = RecentsStore(defaults: testDefaults())
        var consentAsked = false
        let result = QuickCapture.capture(
            settings: settings(autoCopy: true), recents: recents,
            clipboard: { "let a = 1\nlet b = \"\(token)\"" },
            historyConsent: { _ in
                consentAsked = true
                return .doNotSave
            },
            preflight: { _, action in
                #expect(action == .copy)
                return .redact
            })
        #expect(result.outcome == .copied)
        #expect(!consentAsked)
        let capture = try #require(recents.captures.first)
        #expect(!capture.code.contains(token))
    }

    @Test func cleanCaptureAndNoOutputNeverAsk() {
        let asked = {
            (_: ExportPreflight, _: ExportPreflight.Action) -> ExportPreflightPrompt.Choice in
            Issue.record("A capture with nothing to flag or nowhere to go must not ask")
            return .cancel
        }
        let clean = QuickCapture.capture(
            settings: settings(autoCopy: true), recents: RecentsStore(defaults: testDefaults()),
            clipboard: { "let a = 1" }, preflight: asked)
        #expect(clean.outcome == .copied)
        let noOutput = QuickCapture.capture(
            settings: settings(autoCopy: false), recents: RecentsStore(defaults: testDefaults()),
            clipboard: { "let a = \"\(token)\"" }, historyConsent: { _ in .doNotSave },
            preflight: asked)
        #expect(noOutput.outcome == .rendered)
    }

    @Test func theDialogNamesEveryOutputTheCaptureWillWrite() {
        var actions: [ExportPreflight.Action] = []
        for (autoCopy, save) in [(true, true), (true, false), (false, true)] {
            let settings = settings(autoCopy: autoCopy)
            settings.outputBehavior.alsoSaveToFile = save
            _ = QuickCapture.capture(
                settings: settings, recents: RecentsStore(defaults: testDefaults()),
                clipboard: { "let a = \"\(token)\"" },
                preflight: { _, action in
                    actions.append(action)
                    return .cancel
                })
        }
        #expect(actions == [.copyAndSave, .copy, .save])
    }

    @Test func cancelledFeedbackSaysNothingLeft() {
        let feedback = Notifier.feedback(for: .cancelled)
        #expect(feedback.message == String(localized: "Nothing was exported"))
        #expect(feedback.category == .info)
    }
}

@Suite("Export pre-flight prompt")
struct ExportPreflightPromptTests {
    private func report(_ code: String) -> ExportPreflight {
        ExportPreflight(codeConfig(code), payload: .image)
    }

    @Test(arguments: [
        ExportPreflight.Action.copy, .save, .copyAndSave, .share, .export,
    ])
    func redactIsTheDefaultAndEscapeCancels(action: ExportPreflight.Action) {
        let alert = ExportPreflightPrompt.makeAlert(report(token), action: action)
        #expect(
            alert.buttons.map { $0.accessibilityIdentifier() } == [
                "export-preflight-redact", "export-preflight-anyway", "export-preflight-cancel",
            ])
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent.isEmpty)
        #expect(alert.buttons[2].keyEquivalent == "\u{1b}")
        #expect(!alert.informativeText.contains(token))
    }

    @Test func bothOutputsAreNamedOnTheButtons() {
        let alert = ExportPreflightPrompt.makeAlert(report(token), action: .copyAndSave)
        #expect(alert.buttons[0].title == String(localized: "Redact \(1), copy and save"))
        #expect(alert.buttons[1].title == String(localized: "Copy and save anyway"))
    }

    @Test func withNothingToRedactNoPositiveChoiceIsDefault() throws {
        var config = codeConfig("let a = 1")
        config.metadata = SnapshotMetadata(title: token)
        let alert = ExportPreflightPrompt.makeAlert(
            ExportPreflight(config, payload: .image), action: .copy)
        #expect(
            alert.buttons.map { $0.accessibilityIdentifier() } == [
                "export-preflight-cancel", "export-preflight-anyway",
            ])
        #expect(alert.buttons[0].keyEquivalent == "\u{1b}")
        #expect(alert.buttons[1].keyEquivalent.isEmpty)
    }

    @Test func responsesMapToChoices() {
        typealias Prompt = ExportPreflightPrompt
        #expect(Prompt.choice(for: .alertFirstButtonReturn, canRedact: true) == .redact)
        #expect(Prompt.choice(for: .alertSecondButtonReturn, canRedact: true) == .proceed)
        #expect(Prompt.choice(for: .alertThirdButtonReturn, canRedact: true) == .cancel)
        #expect(Prompt.choice(for: .alertFirstButtonReturn, canRedact: false) == .cancel)
        #expect(Prompt.choice(for: .alertSecondButtonReturn, canRedact: false) == .proceed)
    }

    @Test func longListsAreCapped() {
        let code = Array(repeating: token, count: 20).joined(separator: "\nlet a = 1\n")
        let rows = ExportPreflightPrompt.rows(for: report(code))
        #expect(rows.count == 7)
        #expect(rows.last == String(localized: "And \(14) more"))
    }

    @Test func everyLocationHasARow() throws {
        var config = codeConfig("-----BEGIN RSA PRIVATE " + "KEY-----\nbWF0ZXJpYWw=\n\(token)")
        config.metadata = SnapshotMetadata(caption: awsKey)
        let rows = ExportPreflightPrompt.rows(for: ExportPreflight(config, payload: .image))
        #expect(rows.count == 3, "An unclosed key block runs to the end of the document")
        #expect(rows.allSatisfy { !$0.contains(token) && !$0.contains(awsKey) })

        var terminal = SnapshotConfig()
        terminal.language = .terminal
        terminal.code = "\(token)\r\u{1B}[2Kclean\n"
        #expect(
            ExportPreflightPrompt.rows(for: ExportPreflight(terminal, payload: .transcript))
                .count
                == 1)
    }
}

@Suite("Prompt focus")
struct PromptFocusTests {
    @Test func focusReturnsOnceAfterEveryPromptIsAnswered() {
        var events: [String] = []
        let focus = PromptFocus { events.append("return") }
        focus.asking { events.append("preflight") }
        focus.asking { events.append("history") }
        events.append("delivered")
        focus.finish()
        #expect(events == ["preflight", "history", "delivered", "return"])
    }

    @Test func noPromptMeansFocusIsLeftAlone() {
        var returned = false
        PromptFocus { returned = true }.finish()
        #expect(!returned)
    }

    @Test func aVisibleVitrineWindowDoesNotKeepFocusAfterAPrompt() {
        #expect(
            AppActivation.shouldReturnFocusAfterPrompt(
                previousProcessID: 42, appIsActive: true, appProcessID: 7))
    }

    @Test(arguments: [(pid_t?.none, true), (pid_t?.some(7), true), (pid_t?.some(42), false)])
    func focusStaysWithNoTargetOrIfTheUserAlreadyLeft(previous: pid_t?, active: Bool) {
        #expect(
            !AppActivation.shouldReturnFocusAfterPrompt(
                previousProcessID: previous, appIsActive: active, appProcessID: 7))
    }
}

@Suite("Alternative text drafter")
struct AlternativeTextDrafterTests {
    @Test func describesTheDocumentFromItsMetadata() throws {
        var config = codeConfig("let a = 1\nlet b = 2\n")
        config.metadata = SnapshotMetadata(filename: "Greeter.swift", title: "Trim names")
        let draft = try #require(AlternativeTextDrafter.draft(for: config))
        let lines = String(localized: "\(2) lines")
        #expect(draft.text.hasSuffix("\(lines), Greeter.swift: Trim names"))
        #expect(draft.text.contains("Swift"))
    }

    @Test(arguments: [Language.terminal, .diff, .plaintext, .python])
    func everyKindOfDocumentGetsADraft(language: Language) throws {
        var config = codeConfig("only line")
        config.language = language
        let draft = try #require(AlternativeTextDrafter.draft(for: config))
        #expect(draft.text.contains(String(localized: "\(1) lines")))
        #expect(!draft.text.contains("only line"), "A draft never quotes the source")
    }

    @Test func redactedAndFlaggedTextNeverEntersTheDraft() throws {
        var config = codeConfig("let b = \"\(token)\"\nlet c = 1")
        config.redactedLineRanges = [1...1]
        config.metadata = SnapshotMetadata(filename: "ok.swift", title: "Token \(token)")
        let draft = try #require(AlternativeTextDrafter.draft(for: config))
        #expect(!draft.text.contains(token))
        #expect(draft.text.contains("ok.swift"))
        #expect(!draft.text.contains(":"))
    }

    @Test func imagesAndEmptyDocumentsGetNoDraft() {
        #expect(AlternativeTextDrafter.draft(for: codeConfig("")) == nil)
        var image = codeConfig("hidden")
        image.foregroundImage = ImageReference(fileName: "a.png")
        #expect(AlternativeTextDrafter.draft(for: image) == nil)
    }

    @Test func overlongHeaderTextFallsBackToTheSummary() throws {
        var config = codeConfig("let a = 1")
        config.metadata = SnapshotMetadata(
            title: String(repeating: "x", count: SnapshotAltText.maximumLength + 1))
        let draft = try #require(AlternativeTextDrafter.draft(for: config))
        #expect(!draft.text.contains("xxx"))
    }
}

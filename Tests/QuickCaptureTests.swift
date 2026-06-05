import Foundation
import Testing

@testable import Vitrine

/// CS-027 — Markdown fence and file-input detection.
///
/// These suites exercise the pure detection layer (`MarkdownFence`,
/// `LanguageDetector.language(forFileExtension:)` / `forPath:`, and
/// `LanguageDetector.interpret(_:)`) plus the quick-capture wiring that turns a
/// multi-block paste into a deferred-to-editor outcome.

private func cs027Defaults() -> UserDefaults {
    UserDefaults(suiteName: "VitrineCS027-\(UUID().uuidString)")!
}

// MARK: - Markdown fence parsing (table-driven)

@Suite("MarkdownFence")
struct MarkdownFenceTests {
    /// A backtick fence with an explicit language strips its delimiters and names
    /// the language from the info string.
    @Test func backtickFenceStripsDelimitersAndReadsLanguage() {
        let text = """
            ```swift
            let answer = 42
            ```
            """
        let blocks = MarkdownFence.codeBlocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks.first?.code == "let answer = 42")
        #expect(blocks.first?.declaredLanguage == .swift)
    }

    /// Tilde fences are equivalent to backtick fences.
    @Test func tildeFenceIsRecognized() {
        let text = """
            ~~~python
            def greet():
                pass
            ~~~
            """
        let blocks = MarkdownFence.codeBlocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks.first?.code == "def greet():\n    pass")
        #expect(blocks.first?.declaredLanguage == .python)
    }

    /// A fence with no info string yields a block with no declared language, so
    /// the caller falls back to content scoring.
    @Test func fenceWithoutInfoStringHasNoDeclaredLanguage() {
        let text = """
            ```
            SELECT * FROM users
            ```
            """
        let blocks = MarkdownFence.codeBlocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks.first?.declaredLanguage == nil)
        #expect(blocks.first?.code == "SELECT * FROM users")
    }

    /// The info string's first token names the language; trailing tokens (e.g.
    /// `swift title="Demo"`) are ignored, and short aliases resolve too.
    @Test(arguments: [
        ("```ts\nconst x: number = 1\n```", Language.typescript),
        ("```py\nprint(1)\n```", Language.python),
        ("```sh\necho hi\n```", Language.bash),
        ("```yml\nkey: value\n```", Language.yaml),
        ("```swift title=\"Demo\"\nlet x = 1\n```", Language.swift),
    ])
    func infoStringFirstTokenNamesLanguage(_ text: String, _ expected: Language) {
        #expect(MarkdownFence.codeBlocks(in: text).first?.declaredLanguage == expected)
    }

    /// Blank lines and indentation inside a fence are preserved verbatim.
    @Test func preservesBlankLinesAndIndentationInsideFence() {
        let text = """
            ```swift
            func a() {

                let x = 1
            }
            ```
            """
        let block = MarkdownFence.codeBlocks(in: text).first
        #expect(block?.code == "func a() {\n\n    let x = 1\n}")
    }

    /// An unterminated fence is not a code block (treated as prose).
    @Test func unterminatedFenceIsNotABlock() {
        let text = """
            ```swift
            let x = 1
            """
        #expect(MarkdownFence.codeBlocks(in: text).isEmpty)
    }

    /// A closing fence must be at least as long as the opening one; a shorter run
    /// inside the body does not close the block.
    @Test func closingFenceMustMatchOpeningLength() {
        let text = """
            ````swift
            ```
            nested
            ```
            ````
            """
        let blocks = MarkdownFence.codeBlocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks.first?.code == "```\nnested\n```")
    }

    /// Carriage-return line endings (CRLF) are normalized so Windows clipboards
    /// parse cleanly.
    @Test func handlesCarriageReturnLineEndings() {
        let text = "```swift\r\nlet x = 1\r\n```\r\n"
        let block = MarkdownFence.codeBlocks(in: text).first
        #expect(block?.code == "let x = 1")
        #expect(block?.declaredLanguage == .swift)
    }

    /// CommonMark forbids an info string on a closing fence: a line like
    /// ` ```ruby ` is body content, not a close. The block stays open until a
    /// bare closing fence, so the would-be closer is captured verbatim.
    @Test func closingFenceWithInfoStringDoesNotClose() {
        let text = """
            ```swift
            let x = 1
            ```ruby
            still in body
            ```
            """
        let blocks = MarkdownFence.codeBlocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks.first?.code == "let x = 1\n```ruby\nstill in body")
        #expect(blocks.first?.declaredLanguage == .swift)
    }

    /// A fence may be indented up to three spaces (CommonMark). The opening and
    /// closing markers are still recognized, while the indentation of the *body*
    /// lines is preserved verbatim (only the fence lines tolerate the indent).
    @Test func fenceIndentedUpToThreeSpacesIsRecognized() {
        let text = "   ```swift\n   let x = 1\n   ```"
        let blocks = MarkdownFence.codeBlocks(in: text)
        #expect(blocks.count == 1)
        #expect(blocks.first?.declaredLanguage == .swift)
        #expect(blocks.first?.code == "   let x = 1")
    }

    /// Four or more leading spaces is an indented code block, not a fence, so no
    /// fenced block is recognized.
    @Test func fenceIndentedFourSpacesIsNotAFence() {
        let text = "    ```swift\n    let x = 1\n    ```"
        #expect(MarkdownFence.codeBlocks(in: text).isEmpty)
    }

    /// A fence whose info string is an extension-only alias (`rb` has no matching
    /// `Language` raw value) resolves through the file-extension table, proving
    /// the info-string language lookup falls back to the extension map.
    @Test func fenceInfoStringResolvesExtensionOnlyAlias() {
        let text = """
            ```rb
            puts "hi"
            ```
            """
        #expect(MarkdownFence.codeBlocks(in: text).first?.declaredLanguage == .ruby)
    }

    /// Text with no fence at all yields no blocks.
    @Test func plainTextHasNoBlocks() {
        #expect(MarkdownFence.codeBlocks(in: "just some words here").isEmpty)
        #expect(MarkdownFence.codeBlocks(in: "let x = 1").isEmpty)
    }
}

// MARK: - File-extension and path hints

@Suite("LanguageDetector file hints")
struct LanguageDetectorFileHintTests {
    @Test(arguments: [
        ("swift", Language.swift),
        (".swift", Language.swift),
        ("PY", Language.python),
        ("ts", Language.typescript),
        ("tsx", Language.typescript),
        ("jsx", Language.javascript),
        ("yml", Language.yaml),
        ("sh", Language.bash),
        ("rs", Language.rust),
        ("kt", Language.kotlin),
        ("h", Language.objectivec),
        ("hpp", Language.cpp),
    ])
    func extensionMapsToLanguage(_ ext: String, _ expected: Language) {
        #expect(LanguageDetector.language(forFileExtension: ext) == expected)
    }

    @Test func unknownOrEmptyExtensionIsNil() {
        #expect(LanguageDetector.language(forFileExtension: "") == nil)
        #expect(LanguageDetector.language(forFileExtension: "xyz") == nil)
        #expect(LanguageDetector.language(forFileExtension: "   ") == nil)
    }

    @Test(arguments: [
        ("~/src/main.go", Language.go),
        ("/Users/dev/app/Model.swift", Language.swift),
        ("file:///tmp/query.sql", Language.sql),
        ("relative/path/style.scss", Language.scss),
        ("Dockerfile", Language.dockerfile),
        ("/etc/docker/Dockerfile", Language.dockerfile),
        ("a.tsx", Language.typescript),
    ])
    func pathMapsToLanguageByExtension(_ path: String, _ expected: Language) {
        #expect(LanguageDetector.language(forPath: path) == expected)
    }

    /// Prose and code are never mistaken for a path (they contain whitespace, or
    /// have no usable extension).
    @Test func nonPathsYieldNoHint() {
        #expect(LanguageDetector.language(forPath: "just some words here") == nil)
        #expect(LanguageDetector.language(forPath: "let x = 1") == nil)
        #expect(LanguageDetector.language(forPath: "README") == nil)
        #expect(LanguageDetector.language(forPath: "SELECT * FROM t") == nil)
        #expect(LanguageDetector.language(forPath: "") == nil)
    }
}

// MARK: - Clipboard interpretation and hint precedence

@Suite("LanguageDetector.interpret")
struct LanguageDetectorInterpretTests {
    /// A single fenced block is unwrapped to its inner code and the declared
    /// language is used.
    @Test func singleFenceStripsAndSetsLanguage() {
        let result = LanguageDetector.interpret("```swift\nlet x = 1\n```")
        #expect(result.code == "let x = 1")
        #expect(result.language == .swift)
        #expect(result.blockCount == 1)
        #expect(!result.hasMultipleBlocks)
    }

    /// Prose around exactly one fenced block keeps only the code in that block.
    @Test func proseAroundOneBlockKeepsOnlyTheBlock() {
        let text = """
            Here is the fix you asked for:

            ```swift
            let fixed = true
            ```

            Let me know if that works.
            """
        let result = LanguageDetector.interpret(text)
        #expect(result.code == "let fixed = true")
        #expect(result.language == .swift)
        #expect(result.blockCount == 1)
    }

    /// A fence without an info string still strips delimiters and falls back to
    /// content scoring for the language.
    @Test func fenceWithoutLanguageFallsBackToContentScoring() {
        let result = LanguageDetector.interpret("```\nSELECT * FROM users WHERE id = 1\n```")
        #expect(result.code == "SELECT * FROM users WHERE id = 1")
        #expect(result.language == .sql)
        #expect(result.blockCount == 1)
    }

    /// Multiple blocks are concatenated for the editor and reported as a
    /// multi-block result; the language comes from the first declared fence.
    @Test func multipleBlocksAreConcatenatedAndCounted() {
        let text = """
            First:

            ```swift
            let a = 1
            ```

            Second:

            ```swift
            let b = 2
            ```
            """
        let result = LanguageDetector.interpret(text)
        #expect(result.blockCount == 2)
        #expect(result.hasMultipleBlocks)
        #expect(result.language == .swift)
        #expect(result.code.contains("let a = 1"))
        #expect(result.code.contains("let b = 2"))
    }

    /// Hint precedence: an explicit fence language wins over what content scoring
    /// would otherwise pick. Here the body reads like SQL, but the fence says
    /// `python`, so `python` must win.
    @Test func fenceLanguageOverridesContentScoring() {
        let result = LanguageDetector.interpret("```python\nSELECT * FROM t WHERE x = 1\n```")
        #expect(result.language == .python)
    }

    /// Multi-block language is taken from the *first* block that declares one,
    /// even when later blocks declare a different language. Two distinct
    /// declarations (`python` then `sql`) pin this ordering rule, which two
    /// same-language blocks could not distinguish.
    @Test func multipleBlocksUseFirstDeclaredLanguage() {
        let text = """
            ```python
            x = 1
            ```

            ```sql
            SELECT 1
            ```
            """
        let result = LanguageDetector.interpret(text)
        #expect(result.blockCount == 2)
        #expect(result.language == .python)
        #expect(result.code.contains("x = 1"))
        #expect(result.code.contains("SELECT 1"))
    }

    /// When several blocks are present but none declare a language, the language
    /// is scored from the *combined* block text (not an individual block, not
    /// plaintext). Both bodies read as Swift via the `let` signal, so the joined
    /// text scores Swift.
    @Test func multipleUndeclaredBlocksScoreTheJoinedText() {
        let text = """
            ```
            let a = 1
            ```

            ```
            let b = 2
            ```
            """
        let result = LanguageDetector.interpret(text)
        #expect(result.blockCount == 2)
        #expect(result.hasMultipleBlocks)
        #expect(result.language == .swift)
        #expect(result.code.contains("let a = 1"))
        #expect(result.code.contains("let b = 2"))
    }

    /// Hint precedence: with no fence, a lone file path names the language by
    /// extension rather than by (absent) content signal.
    @Test func filePathHintWinsWhenNoFence() {
        let result = LanguageDetector.interpret("~/project/build.gradle.kts")
        #expect(result.language == .kotlin)
        #expect(result.blockCount == 0)
        #expect(result.code == "~/project/build.gradle.kts")
    }

    /// Plain text with no fence and no path is returned unchanged, with the
    /// language coming from content scoring exactly as before (no regression).
    @Test func plainTextIsUnchanged() {
        let go = "package main\nfunc main() { fmt.Println() }"
        let result = LanguageDetector.interpret(go)
        #expect(result.code == go)
        #expect(result.language == .go)
        #expect(result.blockCount == 0)
    }

    /// Plain prose with no code signal stays plaintext and unchanged.
    @Test func plainProseStaysPlaintext() {
        let result = LanguageDetector.interpret("just some words here")
        #expect(result.code == "just some words here")
        #expect(result.language == .plaintext)
        #expect(result.blockCount == 0)
    }
}

// MARK: - QuickCapture wiring

@MainActor
@Suite("QuickCapture · CS-027", .serialized)
struct QuickCaptureFenceTests {
    @Test func singleFenceIsStrippedBeforeStoring() {
        let recents = RecentsStore(defaults: cs027Defaults())
        let outcome = QuickCapture.run(
            settings: AppSettings(defaults: cs027Defaults()),
            recents: recents,
            clipboard: { "```swift\nlet x = 1\n```" })
        #expect(outcome == .copied)
        // The stored capture holds the stripped code and the fence's language,
        // not the raw fenced text.
        #expect(recents.captures.first?.code == "let x = 1")
        #expect(recents.captures.first?.language == .swift)
    }

    @Test func multipleBlocksDeferToEditorAndStoreNothing() {
        let settings = AppSettings(defaults: cs027Defaults())
        let recents = RecentsStore(defaults: cs027Defaults())
        let clip = """
            ```swift
            let a = 1
            ```

            ```swift
            let b = 2
            ```
            """
        let outcome = QuickCapture.run(
            settings: settings, recents: recents, clipboard: { clip })

        #expect(outcome == .deferredToEditor(blocks: 2))
        // Nothing is recorded or copied for a deferred multi-block paste, but the
        // combined source is loaded into the live config for the editor to show.
        #expect(recents.captures.isEmpty)
        #expect(settings.config.code.contains("let a = 1"))
        #expect(settings.config.code.contains("let b = 2"))
        #expect(settings.config.language == .swift)
    }

    @Test func filePathClipboardHintsLanguage() {
        let recents = RecentsStore(defaults: cs027Defaults())
        let outcome = QuickCapture.run(
            settings: AppSettings(defaults: cs027Defaults()),
            recents: recents,
            clipboard: { "~/src/server/main.go" })
        #expect(outcome == .copied)
        #expect(recents.captures.first?.language == .go)
    }

    @Test func plainCodeBehaviorIsUnchanged() {
        let recents = RecentsStore(defaults: cs027Defaults())
        let outcome = QuickCapture.run(
            settings: AppSettings(defaults: cs027Defaults()),
            recents: recents,
            clipboard: { "def greet():\n    pass" })
        #expect(outcome == .copied)
        #expect(recents.captures.first?.code == "def greet():\n    pass")
        #expect(recents.captures.first?.language == .python)
    }

    @Test func deferredOutcomeHasAFeedbackMessage() {
        #expect(Notifier.message(for: .deferredToEditor(blocks: 3)) != nil)
    }

    /// A whitespace-only clipboard is treated as empty before interpretation runs,
    /// so nothing is recorded. This guards the blank-input branch that the
    /// Markdown/path interpretation path sits behind.
    @Test func whitespaceOnlyClipboardIsEmptyAndStoresNothing() {
        let recents = RecentsStore(defaults: cs027Defaults())
        let outcome = QuickCapture.run(
            settings: AppSettings(defaults: cs027Defaults()),
            recents: recents,
            clipboard: { "   \n\t  " })
        #expect(outcome == .empty)
        #expect(recents.captures.isEmpty)
    }
}

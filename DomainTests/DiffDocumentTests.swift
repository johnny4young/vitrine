import Testing

@testable import VitrineDomain

@Suite("Diff document")
struct DiffDocumentTests {
    private static let patch = """
        diff --git a/Sources/Weather/Client.swift b/Sources/Weather/Client.swift
        index 1111111..2222222 100644
        --- a/Sources/Weather/Client.swift
        +++ b/Sources/Weather/Client.swift
        @@ -1,8 +1,9 @@
         one
         two
         three
        -four
        +FOUR
        +FOUR AND A HALF
         five
         six
         seven
         eight
        """

    @Test func countsChangesButNotFileHeaders() {
        let document = DiffDocument(source: Self.patch)
        #expect(document.additions == 2)
        #expect(document.deletions == 1)
        #expect(document.files.count == 1)
    }

    @Test func lineThatLooksLikeAFileHeaderInsideAHunkIsAChange() {
        let document = DiffDocument(
            source: "@@ -1,2 +1,2 @@\n--- removed rule\n+++ added rule\n context\n")
        #expect(document.deletions == 1)
        #expect(document.additions == 1)
        #expect(document.files.isEmpty)
    }

    @Test func splitsFilesOnPlainDiffHeadersWithoutGitLines() {
        let document = DiffDocument(
            source: """
                --- a/one.txt\t2026-01-01
                +++ b/one.txt\t2026-01-02
                @@ -1 +1 @@
                -a
                +b
                --- a/two.txt
                +++ b/two.txt
                @@ -1 +1 @@
                -c
                +d
                """)
        #expect(document.files.map(\.path) == ["one.txt", "two.txt"])
        #expect(document.additions == 2)
        #expect(document.deletions == 2)
    }

    @Test func deletedFileKeepsItsOldPath() {
        let document = DiffDocument(
            source: """
                diff --git a/gone.txt b/gone.txt
                deleted file mode 100644
                --- a/gone.txt
                +++ /dev/null
                @@ -1 +0,0 @@
                -bye
                """)
        #expect(document.files == [DiffDocument.ChangedFile(path: "gone.txt", headerRows: 1...4)])
        #expect(document.deletions == 1)
    }

    @Test func binaryEntryReadsItsPathFromTheGitHeader() {
        let document = DiffDocument(
            source: "diff --git a/new name.png b/new name.png\nBinary files differ\n")
        #expect(document.files.map(\.path) == ["new name.png"])
        #expect(document.additions == 0)
    }

    @Test func quotedGitHeaderPathLosesItsQuotes() {
        let plain = DiffDocument(source: "diff --git \"a/x y\" \"b/x y\"\n")
        #expect(plain.files.map(\.path) == ["x y"])
        let escaped = DiffDocument(source: "diff --git \"a/tab\\tname\" \"b/tab\\tname\"\n")
        #expect(escaped.files.map(\.path) == [nil])
    }

    @Test func mailSignatureAndPreambleAreNotChanges() {
        let document = DiffDocument(
            source: """
                Subject: [PATCH] change
                ---
                 file | 2 +-
                diff --git a/file b/file
                --- a/file
                +++ b/file
                @@ -1 +1 @@
                -a
                +b
                --\u{20}
                2.45.0
                """)
        #expect(document.additions == 1)
        #expect(document.deletions == 1)
    }

    @Test func rowsAddedByHandPastTheHunkCountStillCount() {
        let document = DiffDocument(source: "@@ -1 +1 @@\n-a\n+b\n+added by hand\n extra\n")
        #expect(document.additions == 2)
        #expect(document.rowKinds[4] == .context)
    }

    @Test func malformedHunkHeaderStillReadsItsRows() {
        for header in ["@@", "@@ @@", "@@ -x +y @@", "@@ one two @@"] {
            let document = DiffDocument(source: "\(header)\n-a\n+b\n c")
            #expect(document.additions == 1)
            #expect(document.deletions == 1)
            #expect(document.rowKinds[3] == .context)
        }
    }

    @Test(arguments: [
        "@@ -1,9223372036854775807 +1,-5 @@",
        "@@ -1,-9223372036854775808 +1,1 @@",
        "@@ -1,1 +1,-9223372036854775808 @@",
        "@@ -1,99999999999999999999 +1,1 @@",
        "@@ -9223372036854775807,1 +-9223372036854775808,1 @@",
        "@@ -1,-1 +1,-1 @@",
    ])
    func hostileHunkCountsAreMalformedAndNeverTrap(header: String) {
        let source = "\(header)\n-a\n+b\n c\n--- a/next\n+++ b/next\n@@ -1 +1 @@\n-d\n+e"
        let document = DiffDocument(source: source)
        #expect(document.additions == 2)
        #expect(document.deletions == 2)
        #expect(document.files.map(\.path) == ["next"])
        #expect(!document.displayRows(contextLines: 0).isEmpty)
    }

    @Test func oversizedCountIsMalformedSoTheNextFileHeaderIsRead() {
        let document = DiffDocument(source: "@@ -1,999 +1,999 @@\n-a\n--- a/x\n+++ b/x\n")
        #expect(document.deletions == 1)
        #expect(document.additions == 0)
        #expect(document.files.map(\.path) == ["x"])
    }

    @Test func unifiedHeaderInUnknownCountHunkEndsIt() {
        let document = DiffDocument(
            source: "@@ @@\n-a\n--- a/next\n+++ b/next\n@@ -1 +1 @@\n-c\n+d\n")
        #expect(document.deletions == 2)
        #expect(document.additions == 1)
        #expect(document.files.map(\.path) == ["next"])
    }

    @Test func snippetWithoutHunksReadsAsOneHunk() {
        let document = DiffDocument(source: "keep\n+new\n-old\nkeep too")
        #expect(document.additions == 1)
        #expect(document.deletions == 1)
        #expect(document.rowKinds == [.context, .addition, .deletion, .context])
    }

    @Test func crlfRowsMatchTheRenderedRows() {
        let document = DiffDocument(source: "@@ -1 +1 @@\r\n-a\r\n+b\r\n")
        #expect(document.rowKinds == [.hunkHeader, .deletion, .addition, .context])
    }

    @Test func noNewlineNoteIsNeitherCountedNorFolded() {
        let document = DiffDocument(source: "@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b\n")
        #expect(document.rowKinds[2] == .note)
        #expect(document.displayRows(contextLines: 0).contains(.line(3)))
    }

    @Test func emptySourceHasOneRowAndNoChanges() {
        let document = DiffDocument(source: "")
        #expect(document.rowKinds.count == 1)
        #expect(document.displayRows(contextLines: 0) == [.line(1)])
    }

    // MARK: - Review reproductions

    private static let combined = """
        diff --cc file.txt
        index 1234567,89abcde..fedcba9
        --- a/file.txt
        +++ b/file.txt
        @@@ -1,3 -1,3 +1,4 @@@
          shared
        - ours
         -theirs
        ++merged
          tail
        """

    @Test func combinedDiffCountsAndKeepsItsChanges() {
        let document = DiffDocument(source: Self.combined)
        #expect(document.additions == 1)
        #expect(document.deletions == 2)
        #expect(document.files.map(\.path) == ["file.txt"])
        let shown = document.displayRows(contextLines: 0)
        #expect(shown == [1, 2, 3, 4, 5, 7, 8, 9].map { .line($0) })
    }

    @Test func combinedDiffAfterAPlainDiffStillCounts() {
        let document = DiffDocument(
            source: "diff --git a/p b/p\n--- a/p\n+++ b/p\n@@ -1 +1 @@\n-a\n+b\n" + Self.combined)
        #expect(document.additions == 2)
        #expect(document.deletions == 3)
        #expect(document.files.count == 2)
    }

    @Test func hunklessSnippetIsNeverFolded() {
        let document = DiffDocument(source: "one\ntwo\n+new\nthree\nfour\n-old\nfive\nsix")
        #expect(
            document.displayRows(contextLines: 0) == document.rowKinds.indices.map { .line($0 + 1) }
        )
    }

    @Test func quotedFileHeaderLosesItsQuoteAndPrefix() {
        let document = DiffDocument(source: "--- \"a/x y\"\n+++ \"b/x y\"\n@@ -1 +1 @@\n-a\n+b")
        #expect(document.files.map(\.path) == ["x y"])
    }

    @Test func quotedHeaderDoesNotOverrideTheGitPathWithItsPrefix() {
        let document = DiffDocument(
            source: "diff --git a/x y b/x y\n--- \"a/x y\"\n+++ \"b/x y\"\n@@ -1 +1 @@\n-a\n+b")
        #expect(document.files.map(\.path) == ["x y"])
    }

    @Test func pathContainingTheSeparatorIsReadWhole() {
        let document = DiffDocument(source: "diff --git a/x b/y b/x b/y\nBinary files differ")
        #expect(document.files.map(\.path) == ["x b/y"])
    }

    @Test func ambiguousRenameHeaderShowsNoGuessedPath() {
        let document = DiffDocument(source: "diff --git a/x b/y z b/q\nBinary files differ")
        #expect(document.files.map(\.path) == [nil])
    }

    @Test func renameRowNamesTheTarget() {
        let document = DiffDocument(
            source:
                "diff --git a/x b/y z b/q\nsimilarity index 100%\nrename from x\nrename to y z b/q")
        #expect(document.files.map(\.path) == ["y z b/q"])
    }

    @Test func escapedQuotedPathShowsNoPath() {
        let document = DiffDocument(
            source: "--- \"a/caf\\303\\251\"\n+++ \"b/caf\\303\\251\"\n@@ -1 +1 @@\n-a\n+b")
        #expect(document.files.map(\.path) == [nil])
    }

    // MARK: - Context fold

    @Test func keepsTheRequestedContextAroundAChange() {
        let rows = DiffDocument(source: Self.patch).displayRows(contextLines: 1)
        let headers: [DiffDisplayRow] = (1...5).map { .line($0) }
        // Row 8 is the last unchanged line before the change; row 12 the first after it.
        let body: [DiffDisplayRow] = (8...12).map { .line($0) }
        #expect(rows == headers + body)
    }

    @Test func zeroContextKeepsOnlyChangesAndHeaders() {
        let rows = DiffDocument(source: Self.patch).displayRows(contextLines: 0)
        #expect(rows == [1, 2, 3, 4, 5, 9, 10, 11].map { .line($0) })
    }

    @Test func enoughContextKeepsEveryRow() {
        let document = DiffDocument(source: Self.patch)
        #expect(
            document.displayRows(contextLines: 5)
                == document.rowKinds.indices.map { .line($0 + 1) })
    }

    @Test func gapBetweenChangesGetsAFoldMarker() {
        let source = "@@ -1,6 +1,6 @@\n-a\n+b\n one\n two\n three\n four\n-c\n+d\n"
        let rows = DiffDocument(source: source).displayRows(contextLines: 1)
        #expect(
            rows == [
                .line(1), .line(2), .line(3), .line(4), .fold, .line(7), .line(8), .line(9),
                .line(10),
            ])
    }

    @Test func overlappingContextProducesNoMarkerOrDuplicates() {
        let source = "@@ -1,3 +1,3 @@\n-a\n one\n-b\n"
        #expect(
            DiffDocument(source: source).displayRows(contextLines: 3)
                == [.line(1), .line(2), .line(3), .line(4), .line(5)])
    }

    @Test func keptRowsSurviveTheFoldWithAMarkerForEachGap() {
        let source = "@@ -1,7 +1,7 @@\n-a\n+b\n one\n two\n three\n four\n five\n-c\n+d"
        let rows = DiffDocument(source: source).displayRows(contextLines: 0, keeping: [6...6])
        #expect(
            rows == [
                .line(1), .line(2), .line(3), .fold, .line(6), .fold, .line(9), .line(10),
            ])
    }

    @Test func keptRowAtAHunkEdgeNeedsNoLeadingMarker() {
        let source = "@@ -1,3 +1,3 @@\n one\n two\n-a\n+b"
        let rows = DiffDocument(source: source).displayRows(contextLines: 0, keeping: [2...2])
        #expect(rows == [.line(1), .line(2), .fold, .line(4), .line(5)])
    }

    @Test(arguments: [
        ("+secret", "+[r]"), ("-secret", "-[r]"), (" secret", " [r]"), ("", " [r]"),
        ("--- a/secret", "--- [r]"), ("+++ b/secret", "+++ [r]"), ("@@ -1 +1 @@ secret", "@@ [r]"),
        ("@@@ -1 -1 +1 @@@ x", "@@@ [r]"), ("diff --git a/s b/s", "diff --git [r]"),
        ("index secret", " [r]"), ("\\ note", "\\ [r]"), (" +secret", " +[r]"),
        ("+----BEGIN KEY", "+---[r]"),
    ])
    func maskedRowKeepsOnlyDiffMarkers(row: String, masked: String) {
        #expect(DiffDocument.maskedRow(row, placeholder: "[r]") == masked)
    }

    @Test func noChangesLeavesEveryRowVisible() {
        let document = DiffDocument(source: "just\nplain\ntext")
        #expect(
            document.displayRows(contextLines: 0) == [.line(1), .line(2), .line(3)])
    }

    @Test func negativeContextActsAsZero() {
        let document = DiffDocument(source: Self.patch)
        #expect(
            document.displayRows(contextLines: -3) == document.displayRows(contextLines: 0))
    }

    // MARK: - Header inputs

    @Test(arguments: 1...4)
    func redactingAnyGitHeaderRowWithholdsThePath(row: Int) {
        let document = DiffDocument(source: Self.patch)
        #expect(document.singleFilePath(redacting: []) == "Sources/Weather/Client.swift")
        #expect(document.singleFilePath(redacting: [row...row]) == nil)
    }

    @Test(arguments: 1...4)
    func redactingAnyRenameRowWithholdsThePath(row: Int) {
        let document = DiffDocument(
            source: """
                diff --git a/old.swift b/new.swift
                similarity index 100%
                rename from old.swift
                rename to new.swift
                """)
        #expect(document.singleFilePath(redacting: []) == "new.swift")
        #expect(document.singleFilePath(redacting: [row...row]) == nil)
    }

    @Test(arguments: 1...2)
    func redactingAPlainFileHeaderRowWithholdsThePath(row: Int) {
        let document = DiffDocument(source: "--- a/one\n+++ b/one\n@@ -1 +1 @@\n-a\n+b")
        #expect(document.singleFilePath(redacting: []) == "one")
        #expect(document.singleFilePath(redacting: [row...row]) == nil)
    }

    @Test func redactingARangeAcrossTheHeaderWithholdsThePath() {
        let document = DiffDocument(source: Self.patch)
        #expect(document.singleFilePath(redacting: [3...20]) == nil)
    }

    @Test func redactingARowInTheHunkKeepsThePath() {
        let document = DiffDocument(source: Self.patch)
        #expect(document.singleFilePath(redacting: [5...15]) == "Sources/Weather/Client.swift")
    }

    @Test func hunklessFilesSplitAtEachHeaderPair() {
        let document = DiffDocument(
            source: "--- a/one\n+++ b/one\n+a\n--- a/two\n+++ b/two\n-b")
        #expect(document.files.map(\.path) == ["one", "two"])
        #expect(document.files.map(\.headerRows) == [1...2, 4...5])
    }

    @Test func severalFilesHaveNoSinglePath() {
        let document = DiffDocument(
            source: "diff --git a/one b/one\ndiff --git a/two b/two\n")
        #expect(document.singleFilePath(redacting: []) == nil)
    }

    @Test(arguments: [
        (8, 1, 4), (1, 200, 1), (200, 1, 4), (3, 0, 5), (0, 3, 0), (0, 0, 0), (1, 1, 3),
    ])
    func additionCellsKeepEverySideVisible(added: Int, removed: Int, expected: Int) {
        let rows =
            Array(repeating: "+a", count: added) + Array(repeating: "-b", count: removed)
        let document = DiffDocument(source: rows.joined(separator: "\n"))
        #expect(document.additionCells(of: 5) == expected)
    }
}

import Foundation
import Testing
import VitrineDomain

@Suite("VitrineDomain boundary")
struct VitrineDomainBoundaryTests {
    @Test func searchIsUnicodeAndDiacriticInsensitive() {
        #expect(
            LocalSearch.matchesAllTerms(
                "CAFE swift",
                in: ["Café", "Swift"],
                locale: Locale(identifier: "en_US_POSIX")
            ))
    }

    @Test func transportCollectorRejectsBeforeMutation() throws {
        var collector = BoundedDataCollector(limit: 4, initialCapacity: 1)
        try collector.append(Data([0, 1, 2]))

        #expect(throws: BoundedDataCollector.Failure.tooLarge) {
            try collector.append(Data([3, 4]))
        }
        #expect(collector.data == Data([0, 1, 2]))
    }

    @Test func boundedFileReaderRejectsOversizedRegularFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vitrine-domain-boundary-\(UUID().uuidString).txt"
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("12345".utf8).write(to: url)

        #expect(throws: BoundedFileReader.ReadError.tooLarge) {
            try BoundedFileReader.read(from: url, limit: 4)
        }
    }

    @Test func ansiParserStripsControlsAndPreservesStyle() {
        let runs = ANSIParser.parse("plain \u{1B}[31mred\u{1B}[0m")

        #expect(runs.map(\.text).joined() == "plain red")
        #expect(runs.last?.style.foreground == .indexed(1))
    }

    @Test func characterWidthHandlesWideAndCombiningScalars() {
        #expect(CharacterWidth.displayWidth("界".unicodeScalars.first!) == 2)
        #expect(CharacterWidth.displayWidth("\u{0301}".unicodeScalars.first!) == 0)
    }
}

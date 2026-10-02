import Foundation
import Testing
import VitrineDomain

@Suite("Bounded snapshot alternative text")
struct SnapshotAltTextTests {
    @Test func normalizesAndTreatsBlankAsAbsent() throws {
        #expect(try SnapshotAltText.normalized(" \n ") == nil)
        #expect(try SnapshotAltText.normalized(nil) == nil)
        #expect(try SnapshotAltText.normalized(" 説明 👩🏽‍💻\n")?.text == "説明 👩🏽‍💻")
    }

    @Test func limitCountsUnicodeCharactersWithoutTruncation() throws {
        let accepted = String(repeating: "👩🏽‍💻", count: 1_024)
        #expect(try SnapshotAltText.normalized(accepted)?.text == accepted)
        #expect(throws: SnapshotAltText.ValidationError.tooLong) {
            try SnapshotAltText.normalized(accepted + "x")
        }
    }

    @Test func encodesAsAnAdditiveStringAndRejectsInvalidPayloads() throws {
        let value = try #require(try SnapshotAltText.normalized("Descripción"))
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(SnapshotAltText.self, from: data) == value)
        for input in ["\"\"", "null", "12", "\"" + String(repeating: "x", count: 1_025) + "\""] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(SnapshotAltText.self, from: Data(input.utf8))
            }
        }
    }
}

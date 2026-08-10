import Foundation
import Testing

@testable import Vitrine

@Suite("Local search semantics")
struct LocalSearchTests {
    @Test func anEmptyQueryMatchesWithoutTargets() {
        #expect(LocalSearch.matchesAllTerms("", in: []))
        #expect(LocalSearch.matchesAllTerms(" \n\t ", in: []))
    }

    @Test func matchingIgnoresCaseDiacriticsAndWidth() {
        #expect(LocalSearch.matchesAllTerms("CAPTURA", in: ["Captúra rápida"]))
        #expect(LocalSearch.matchesAllTerms("ＪｅｔＢｒａｉｎｓ", in: ["JetBrains Mono"]))
    }

    @Test func termsMayMatchAcrossSeparateFieldsInAnyOrder() {
        let targets = ["fn main()", "Rust", "Dracula"]
        #expect(LocalSearch.matchesAllTerms("dracula rust", in: targets))
        #expect(LocalSearch.matchesAllTerms("rust main", in: targets))
        #expect(!LocalSearch.matchesAllTerms("rust github", in: targets))
    }

    @Test func everyTermUsesSubstringRatherThanSubsequenceMatching() {
        #expect(LocalSearch.matchesAllTerms("brain mono", in: ["JetBrains Mono"]))
        #expect(!LocalSearch.matchesAllTerms("jbm", in: ["JetBrains Mono"]))
    }

    @Test func localeCanBePinnedForDeterministicFixtures() {
        let locale = Locale(identifier: "en_US_POSIX")
        #expect(LocalSearch.fold("Résumé", locale: locale) == "resume")
        #expect(LocalSearch.terms(in: "  Résumé   Swift ", locale: locale) == ["resume", "swift"])
    }
}

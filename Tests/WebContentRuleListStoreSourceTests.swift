import Foundation
import Testing

@testable import Vitrine

@Suite("Content-rule store selection")
struct WebContentRuleListStoreSourceTests {
    @Test func theDefaultKeepsTheApplicationStoreAndSharedCache() {
        var defaultCalls = 0
        var directoryCalls = 0
        let source = WebContentRuleListStoreSource.applicationDefault
        let store: String? = source.makeStore(
            applicationDefault: {
                defaultCalls += 1
                return "application"
            },
            directory: { _ in
                directoryCalls += 1
                return "unexpected"
            })
        #expect(store == "application")
        #expect(defaultCalls == 1)
        #expect(directoryCalls == 0)
        #expect(source.usesSharedCache)
    }

    @Test func anOwnedDirectorySelectsOnlyItsFactoryAndDoesNotShareTheCache() {
        let url = URL(filePath: "/tmp/synthetic-content-rules", directoryHint: .isDirectory)
        let source = WebContentRuleListStoreSource.directory(url)
        var defaultCalls = 0
        var received: [URL] = []
        let store: String? = source.makeStore(
            applicationDefault: {
                defaultCalls += 1
                return "unexpected"
            },
            directory: {
                received.append($0)
                return "owned"
            })
        #expect(store == "owned")
        #expect(defaultCalls == 0)
        #expect(received == [url])
        #expect(!source.usesSharedCache)
    }

    @Test func aMissingApplicationStoreDoesNotFallBackToADirectory() {
        var directoryCalls = 0
        let store: String? = WebContentRuleListStoreSource.applicationDefault.makeStore(
            applicationDefault: { nil },
            directory: { _ in
                directoryCalls += 1
                return "unexpected"
            })
        #expect(store == nil)
        #expect(directoryCalls == 0)
    }

    @Test func aMissingDirectoryStoreDoesNotFallBackToTheApplicationStore() {
        let url = URL(filePath: "/tmp/synthetic-content-rules", directoryHint: .isDirectory)
        var defaultCalls = 0
        let store: String? = WebContentRuleListStoreSource.directory(url).makeStore(
            applicationDefault: {
                defaultCalls += 1
                return "unexpected"
            },
            directory: { _ in nil })
        #expect(store == nil)
        #expect(defaultCalls == 0)
    }

    @Test(arguments: [
        "https://example.invalid/rules", "file://remote.invalid/rules", "file:relative",
        "file:///tmp/rules?query", "file:///tmp/rules#fragment",
    ])
    func invalidDirectoryLocationsDoNotInvokeEitherFactory(_ value: String) throws {
        let source = WebContentRuleListStoreSource.directory(try #require(URL(string: value)))
        var calls = 0
        let store: String? = source.makeStore(
            applicationDefault: {
                calls += 1
                return "unexpected"
            },
            directory: { _ in
                calls += 1
                return "unexpected"
            })
        #expect(store == nil)
        #expect(calls == 0)
        #expect(!source.usesSharedCache)
    }
}

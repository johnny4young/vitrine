import Foundation
import Testing

@testable import Vitrine

@Suite("Test defaults suite purge")
struct AppDefaultsPurgeTests {
    @Test func onlyUUIDSuffixedSuitesAreTestScoped() {
        #expect(AppDefaults.isTestScoped("VitrineUITests--[A b]-\(UUID().uuidString)"))
        #expect(AppDefaults.isTestScoped("com.johnny4young.vitrine.memory-smoke.\(UUID())"))
        #expect(!AppDefaults.isTestScoped(UUID().uuidString))
        #expect(!AppDefaults.isTestScoped("com.johnny4young.vitrine"))
        #expect(!AppDefaults.isTestScoped("com.johnny4young.vitrine.menubar-helper"))
        #expect(!AppDefaults.isTestScoped("vitrine-cli"))
        #expect(!AppDefaults.isTestScoped(""))
        #expect(!AppDefaults.isTestScoped("../../Application Support/x-\(UUID().uuidString)"))
        #expect(!AppDefaults.isTestScoped("sub/dir-\(UUID().uuidString)"))
    }

    @Test func onlyThePurgeArgumentMakesAPurgeLaunch() {
        #expect(
            AppDefaults.isPurgeLaunch(arguments: ["Vitrine", "--purge-user-defaults-suite", "s"]))
        #expect(!AppDefaults.isPurgeLaunch(arguments: ["Vitrine", "--open-editor"]))
    }

    @Test func aPurgeRequestNamesOnlyTestScopedSuites() {
        let first = "VitrineUITests--[A b]-\(UUID().uuidString)"
        let second = "shortcut-opt-in--[A c]-\(UUID().uuidString)"
        let flag = AppDefaults.purgeSuiteArgument
        #expect(
            AppDefaults.requestedSuites(arguments: ["Vitrine", flag, "\(first)\n\(second)"])
                == [first, second])
        #expect(
            AppDefaults.requestedSuites(
                arguments: ["Vitrine", flag, "\(first)\ncom.johnny4young.vitrine"]) == nil)
        #expect(AppDefaults.requestedSuites(arguments: ["Vitrine", flag]) == nil)
        #expect(AppDefaults.requestedSuites(arguments: ["Vitrine", flag, ""]) == nil)
    }

    @Test func purgeRefusesARealDomainAndLeavesItsFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "purge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = directory.appending(path: "com.johnny4young.vitrine.plist")
        try Data().write(to: real)

        #expect(
            !AppDefaults.purge(suite: "com.johnny4young.vitrine", preferencesDirectory: directory))
        #expect(FileManager.default.fileExists(atPath: real.path))
    }

    @Test func purgeDeletesTheSuitePlist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "purge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "purge-test-\(UUID().uuidString)"
        let file = directory.appending(path: "\(suite).plist")
        try Data().write(to: file)

        #expect(AppDefaults.purge(suite: suite, preferencesDirectory: directory))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let realPreferences = URL.libraryDirectory.appending(path: "Preferences/\(suite).plist")
        #expect(!FileManager.default.fileExists(atPath: realPreferences.path))
    }
}

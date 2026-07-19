import Foundation
import Testing

@testable import Vitrine

/// The single-instance launch guard must never fire under tests: the unit-test host
/// launches the app to host XCTest, and exiting there aborts the run with "test runner
/// exited before establishing connection". The UI-test host is likewise exempt.
@MainActor
@Suite("Single-instance launch guard")
struct AppLaunchGuardTests {
    @Test func enforcesForAPlainUserLaunch() {
        #expect(AppDelegate.shouldEnforceSingleInstance([:]))
        #expect(AppDelegate.shouldEnforceSingleInstance(["HOME": "/Users/x"]))
    }

    @Test func skipsUnderTheUITestHost() {
        #expect(
            !AppDelegate.shouldEnforceSingleInstance(["VITRINE_USER_DEFAULTS_SUITE": "suite-123"]))
    }

    @Test func skipsUnderTheUnitTestHost() {
        #expect(
            !AppDelegate.shouldEnforceSingleInstance([
                "XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"
            ]))
        // This very test runs inside a unit-test host, so the live environment must also
        // resolve to "do not enforce".
        #expect(!AppDelegate.shouldEnforceSingleInstance(ProcessInfo.processInfo.environment))
    }

    @Test func handoffRoutingIsCaseInsensitiveAndRejectsForeignSchemes() {
        #expect(
            AppDelegate.handoffRoute(for: URL(string: "VITRINE://OPEN?d=x")!)
                == .sharedSnapshot)
        #expect(AppDelegate.handoffRoute(for: URL(string: "vitrine://EDIT?d=x")!) == .edit)
        #expect(AppDelegate.handoffRoute(for: URL(string: "https://open?d=x")!) == nil)
        #expect(AppDelegate.handoffRoute(for: URL(string: "vitrine://unknown?d=x")!) == nil)
    }
}

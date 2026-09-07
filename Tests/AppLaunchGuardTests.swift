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
    // MARK: - Update scheduler

    /// Sparkle asks once, in a modal window, whether to check automatically, and records
    /// the answer in the app's defaults. A UI-test run gets a fresh throwaway suite each
    /// time, so that window opens on every launch and steals focus from the automation.
    @Test func startsTheUpdateSchedulerOnlyOutsideATestHost() {
        #expect(AppDelegate.shouldStartUpdateScheduler([:]))
        #expect(AppDelegate.shouldStartUpdateScheduler(["HOME": "/Users/x"]))
        #expect(
            !AppDelegate.shouldStartUpdateScheduler(["VITRINE_USER_DEFAULTS_SUITE": "suite-123"]))
        #expect(
            !AppDelegate.shouldStartUpdateScheduler([
                "XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"
            ]))
        #expect(!AppDelegate.shouldStartUpdateScheduler(ProcessInfo.processInfo.environment))
    }

}

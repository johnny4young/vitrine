import XCTest

/// XCTest runs classes in alphabetical order, so this one runs last and deletes every
/// defaults suite the UI tests launched. A failure here is inside a test, the only place
/// xcodebuild turns into a red run.
final class ZZDefaultsSuitePurgeUITests: XCTestCase {
    @MainActor
    func testDeletesEveryDefaultsSuiteTheUITestsLaunched() {
        let count = UITestDefaultsSuite.launchedCount
        XCTAssertTrue(
            UITestDefaultsSuite.purgeLaunchedSuites(),
            "Vitrine did not delete \(count) defaults suites")
    }
}

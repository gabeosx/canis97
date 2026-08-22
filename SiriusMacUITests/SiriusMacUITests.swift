import XCTest

final class SiriusMacUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SIRIUS_MAC_UI_TEST_MODE"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testOfflineHarnessLaunchesCompactAndLibrary() {
        XCTAssertTrue(app.otherElements["compact.canvas"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tables["library.collection"].waitForExistence(timeout: 5))
    }
}

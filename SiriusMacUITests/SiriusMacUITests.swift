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
        XCTAssertTrue(
            app.groups["compact.canvas"].waitForExistence(timeout: 5),
            app.debugDescription
        )
        XCTAssertTrue(app.outlines["library.collection"].waitForExistence(timeout: 5))
    }

    func testCompactCanvasFillsFixedWindow() {
        let compactCanvas = app.groups["compact.canvas"]
        XCTAssertTrue(compactCanvas.waitForExistence(timeout: 5), app.debugDescription)

        XCTAssertEqual(compactCanvas.frame.width, 400, accuracy: 1)
        XCTAssertEqual(compactCanvas.frame.height, 320, accuracy: 1)
    }
}

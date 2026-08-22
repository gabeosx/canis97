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

    func testSingleClickSelectsImmediatelyWithoutTuning() {
        let firstRow = app.staticTexts["library.row.ui-test-1"].firstMatch
        let secondRow = app.staticTexts["library.row.ui-test-2"].firstMatch
        let tuneCount = app.staticTexts["library.tune-count"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(secondRow.exists)

        firstRow.click()
        XCTAssertEqual(firstRow.value as? String, "Selected")
        XCTAssertEqual(tuneCount.value as? String, "0")

        secondRow.click()
        XCTAssertEqual(secondRow.value as? String, "Selected")
        XCTAssertEqual(tuneCount.value as? String, "0")
    }

    func testDoubleClickAndReturnTuneExactlyOnce() {
        let firstRow = app.staticTexts["library.row.ui-test-1"].firstMatch
        let secondRow = app.staticTexts["library.row.ui-test-2"].firstMatch
        let tuneCount = app.staticTexts["library.tune-count"]
        let tuneOrigin = app.staticTexts["library.tune-origin"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), app.debugDescription)

        firstRow.doubleClick()
        XCTAssertEqual(tuneCount.value as? String, "1")
        XCTAssertEqual(tuneOrigin.value as? String, "ui-test-1,ui-test-2")

        secondRow.click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(tuneCount.value as? String, "2")
        XCTAssertEqual(tuneOrigin.value as? String, "ui-test-1,ui-test-2")
    }
}

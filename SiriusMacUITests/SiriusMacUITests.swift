import AppKit
import XCTest

final class SiriusMacUITests: XCTestCase, @unchecked Sendable {
    private let expectedBundleIdentifier = "com.siriusmac.player"
    private var app: XCUIApplication!
    private var launchedProcessIdentifier: pid_t?
    private var expectedExecutableURL: URL!

    override func setUpWithError() throws {
        try MainActor.assumeIsolated {
            continueAfterFailure = false
            let existingApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: expectedBundleIdentifier
            )
            guard existingApplications.isEmpty else {
                throw LaunchSafetyError("Refusing to launch while another SiriusMac application is running")
            }

            expectedExecutableURL = try makeExpectedExecutableURL()
            app = XCUIApplication()
            app.launchEnvironment["SIRIUS_MAC_UI_TEST_MODE"] = "1"
            app.launch()

            let launchedApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: expectedBundleIdentifier
            )
            guard launchedApplications.count == 1 else {
                throw LaunchSafetyError("Expected exactly one launched SiriusMac application")
            }
            let processIdentifier = launchedApplications[0].processIdentifier
            guard processIdentifier > 1 else {
                throw LaunchSafetyError("SiriusMac did not report a safe process identifier")
            }
            launchedProcessIdentifier = processIdentifier
            guard app.wait(for: .runningForeground, timeout: 5) else {
                throw LaunchSafetyError("SiriusMac did not reach the foreground")
            }
            guard launchedApplications[0].processIdentifier == processIdentifier,
                  isExpectedApplication(processIdentifier: processIdentifier)
            else {
                throw LaunchSafetyError("Launched application identity did not match the build-only SiriusMac product")
            }
        }
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            defer {
                app = nil
                launchedProcessIdentifier = nil
                expectedExecutableURL = nil
            }
            guard let app, let launchedProcessIdentifier else { return }

            if app.state != .notRunning {
                let matchingApplications = NSRunningApplication.runningApplications(
                    withBundleIdentifier: expectedBundleIdentifier
                )
                guard matchingApplications.count == 1,
                      matchingApplications[0].processIdentifier == launchedProcessIdentifier,
                      isExpectedApplication(processIdentifier: launchedProcessIdentifier)
                else {
                    XCTFail("Refusing to terminate an application whose identity changed")
                    return
                }
                app.terminate()
            }
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
            XCTAssertNil(NSRunningApplication(processIdentifier: launchedProcessIdentifier))
        }
    }

    @MainActor
    func testOfflineHarnessLaunchesCompactAndLibrary() {
        XCTAssertTrue(
            app.groups["compact.canvas"].waitForExistence(timeout: 5),
            app.debugDescription
        )
        XCTAssertTrue(app.outlines["library.collection"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompactCanvasFillsFixedWindow() {
        let compactCanvas = app.groups["compact.canvas"]
        let compactContentRegion = app.groups["compact.content-region"]
        let compactWindow = app.windows["Sirius Mac"].firstMatch
        XCTAssertTrue(compactCanvas.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(compactContentRegion.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(compactWindow.waitForExistence(timeout: 5), app.debugDescription)

        XCTAssertEqual(compactContentRegion.frame.width, 400, accuracy: 1)
        XCTAssertEqual(compactContentRegion.frame.height, 288, accuracy: 1)
        XCTAssertEqual(compactWindow.frame.width, compactContentRegion.frame.width, accuracy: 1)
        XCTAssertEqual(compactWindow.frame.minX, compactContentRegion.frame.minX, accuracy: 1)
        XCTAssertEqual(compactWindow.frame.maxX, compactContentRegion.frame.maxX, accuracy: 1)
        XCTAssertGreaterThan(compactWindow.frame.height - compactContentRegion.frame.height, 0)
        XCTAssertLessThanOrEqual(compactWindow.frame.height - compactContentRegion.frame.height, 40)
    }

    @MainActor
    func testSingleClickSelectsImmediatelyWithoutTuning() {
        let firstRow = app.staticTexts["library.row.ui-test-1"].firstMatch
        let secondRow = app.staticTexts["library.row.ui-test-2"].firstMatch
        let collection = app.outlines["library.collection"]
        let firstCell = collection.cells.element(boundBy: 0)
        let secondCell = collection.cells.element(boundBy: 1)
        let tuneCount = app.staticTexts["library.tune-count"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(secondRow.exists)

        firstRow.click()
        XCTAssertTrue(firstCell.isSelected)
        XCTAssertEqual(firstRow.value as? String, "Selected")
        XCTAssertEqual(tuneCount.value as? String, "0")

        secondRow.click()
        XCTAssertTrue(secondCell.isSelected)
        XCTAssertEqual(secondRow.value as? String, "Selected")
        XCTAssertEqual(tuneCount.value as? String, "0")
    }

    @MainActor
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

    @MainActor
    private func makeExpectedExecutableURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let productsPaths = environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] else {
            throw LaunchSafetyError("Xcode did not provide a built-products directory")
        }

        let fileManager = FileManager.default
        for productsPath in productsPaths.split(separator: ":") {
            let executableURL = URL(fileURLWithPath: String(productsPath), isDirectory: true)
                .appendingPathComponent("SiriusMac.app/Contents/MacOS/SiriusMac")
                .resolvingSymlinksInPath()
            if fileManager.isExecutableFile(atPath: executableURL.path) {
                return executableURL
            }
        }
        throw LaunchSafetyError("The build-only SiriusMac executable was not found")
    }

    @MainActor
    private func isExpectedApplication(processIdentifier: pid_t) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier),
              application.bundleIdentifier == expectedBundleIdentifier,
              let executableURL = application.executableURL?.resolvingSymlinksInPath()
        else { return false }
        return executableURL == expectedExecutableURL
    }
}

private struct LaunchSafetyError: LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}

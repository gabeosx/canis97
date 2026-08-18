import XCTest
@testable import SiriusMac

@MainActor
final class CompatibilityTracerTests: XCTestCase {
    func testPresentationStartsWaitingForAuthenticationComposition() async {
        let model = CompatibilityPresentationModel()

        let state = await model.present()

        XCTAssertEqual(state, .waitingForAuthenticationComposition)
    }

    func testExplicitPresentationDoesNotCreateBackgroundRetryWork() async {
        let model = CompatibilityPresentationModel()

        _ = await model.present()
        _ = await model.present()

        XCTAssertEqual(model.presentationCount, 2)
        XCTAssertEqual(model.backgroundRetryCount, 0)
    }
}

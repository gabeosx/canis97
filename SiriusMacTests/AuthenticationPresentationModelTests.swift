import XCTest
@testable import SiriusMac

@MainActor
final class AuthenticationPresentationModelTests: XCTestCase {
    func testSemanticStatesHaveDistinctFixedPresentationCopy() {
        let model = AuthenticationPresentationModel()
        let states: [AuthenticationPresentationState] = [
            .waitingForWebView,
            .verifyingAuthentication,
            .verifyingEntitlement,
            .authenticatedButNotEntitled,
            .entitled,
            .rejected,
            .challengeRequired,
            .unsupported,
            .signedOut,
            .cleanupFailed(.both)
        ]

        let copies = states.map { model.presentation(for: $0) }

        XCTAssertEqual(Set(copies.map(\.title)).count, states.count)
        XCTAssertTrue(model.presentation(for: .entitled).isReady)
        XCTAssertTrue(model.presentation(for: .entitled).canSignOut)
        XCTAssertEqual(model.presentation(for: .unsupported).message, "This sign-in flow is unsupported. No workaround was attempted.")
        XCTAssertEqual(model.presentation(for: .cleanupFailed(.both)).message, "You are signed out. Local cleanup was incomplete.")
    }

    func testOnlyEntitledStateExposesReadinessOrSignOut() {
        let model = AuthenticationPresentationModel()
        let nonEntitledStates: [AuthenticationPresentationState] = [
            .waitingForWebView,
            .verifyingAuthentication,
            .verifyingEntitlement,
            .authenticatedButNotEntitled,
            .rejected,
            .challengeRequired,
            .unsupported,
            .signedOut,
            .cleanupFailed(.keychain)
        ]

        for state in nonEntitledStates {
            XCTAssertFalse(model.presentation(for: state).isReady)
            XCTAssertFalse(model.presentation(for: state).canSignOut)
        }
    }

    func testSafeDiagnosticsAcceptOnlyFixedClassifications() {
        let model = AuthenticationPresentationModel()

        model.record(.challengeRequired)
        model.record(.cleanupFailed)

        XCTAssertEqual(model.diagnostics, [.challengeRequired, .cleanupFailed])
    }
}

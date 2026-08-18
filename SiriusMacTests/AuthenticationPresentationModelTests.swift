import XCTest
import SiriusXMClient
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

    func testSignInStartsOnlyOneBridgeActionWhileInFlight() async {
        let flow = AuthenticationFlowSpy(beginResults: [.rejected, .rejected], holdBegin: true)
        let model = AuthenticationPresentationModel(flow: flow)

        model.signIn()
        model.signIn()
        await Task.yield()

        XCTAssertTrue(model.isAttemptInFlight)
        let pendingCounts = await flow.callCounts()
        XCTAssertEqual(pendingCounts.begin, 1)

        await flow.finishBegin()
        await Task.yield()

        XCTAssertEqual(model.state, .rejected)
    }

    func testRetryRepeatsOnlyTheWebViewPathAfterTerminalResult() async {
        let flow = AuthenticationFlowSpy(beginResults: [.rejected, .waitingForWebView])
        let model = AuthenticationPresentationModel(flow: flow)

        model.signIn()
        await Task.yield()
        model.retry()
        await Task.yield()

        let retryCounts = await flow.callCounts()
        XCTAssertEqual(retryCounts.begin, 2)
        XCTAssertEqual(retryCounts.loggedInSession, 0)
        XCTAssertEqual(model.state, .waitingForWebView)
    }

    func testTerminalFailuresScheduleNoFollowUpWork() async {
        let flow = AuthenticationFlowSpy(beginResult: .challengeRequired)
        let model = AuthenticationPresentationModel(flow: flow)

        model.signIn()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(model.state, .challengeRequired)
        XCTAssertEqual(model.backgroundRetryCount, 0)
        let terminalCounts = await flow.callCounts()
        XCTAssertEqual(terminalCounts.begin, 1)
        XCTAssertEqual(terminalCounts.loggedInSession, 0)
    }

    func testSignOutRequiresEntitlementAndReportsCleanupFailureSafely() async {
        let flow = AuthenticationFlowSpy(
            loggedInSessionResult: .entitled,
            signOutResult: .cleanupFailed(.browserResidue)
        )
        let model = AuthenticationPresentationModel(flow: flow)

        model.signOut()
        await Task.yield()
        let signedOutCounts = await flow.callCounts()
        XCTAssertEqual(signedOutCounts.signOut, 0)

        model.useLoggedInSession()
        await Task.yield()
        model.signOut()
        await Task.yield()

        let cleanupCounts = await flow.callCounts()
        XCTAssertEqual(cleanupCounts.signOut, 1)
        XCTAssertEqual(model.state, .cleanupFailed(.browserResidue))
        XCTAssertEqual(model.presentation(for: model.state).message, "You are signed out. Local cleanup was incomplete.")
    }
}

private actor AuthenticationFlowSpy: AuthenticationPresentationFlow {
    private var beginResults: [AuthenticationPresentationState]
    private let holdBegin: Bool
    private var beginContinuation: CheckedContinuation<Void, Never>?
    private let loggedInSessionResult: AuthenticationPresentationState
    private let signOutResult: SignOutOutcome

    private(set) var beginCallCount = 0
    private(set) var loggedInSessionCallCount = 0
    private(set) var signOutCallCount = 0

    init(
        beginResult: AuthenticationPresentationState = .waitingForWebView,
        beginResults: [AuthenticationPresentationState]? = nil,
        holdBegin: Bool = false,
        loggedInSessionResult: AuthenticationPresentationState = .waitingForWebView,
        signOutResult: SignOutOutcome = .alreadySignedOut
    ) {
        self.beginResults = beginResults ?? [beginResult]
        self.holdBegin = holdBegin
        self.loggedInSessionResult = loggedInSessionResult
        self.signOutResult = signOutResult
    }

    func beginWebViewSignIn() async -> AuthenticationPresentationState {
        beginCallCount += 1
        if holdBegin, beginCallCount == 1 {
            await withCheckedContinuation { continuation in
                beginContinuation = continuation
            }
        }
        return beginResults.removeFirst()
    }

    func useLoggedInSession() async -> AuthenticationPresentationState {
        loggedInSessionCallCount += 1
        return loggedInSessionResult
    }

    func signOut() async -> SignOutOutcome {
        signOutCallCount += 1
        return signOutResult
    }

    func finishBegin() {
        beginContinuation?.resume()
        beginContinuation = nil
    }

    func callCounts() -> (begin: Int, loggedInSession: Int, signOut: Int) {
        (beginCallCount, loggedInSessionCallCount, signOutCallCount)
    }
}

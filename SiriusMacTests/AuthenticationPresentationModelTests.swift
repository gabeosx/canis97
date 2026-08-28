import XCTest
import SiriusXMClient
@testable import Canis97

@MainActor
final class AuthenticationPresentationModelTests: XCTestCase {
    func testLaunchModeIdentifiesOnlyTheXCTestHostEnvironment() {
        XCTAssertTrue(
            OfflineReviewLaunchMode.isUnitTestHost(
                environment: ["XCTestConfigurationFilePath": "/private/tmp/config.xctest"]
            )
        )
        XCTAssertFalse(OfflineReviewLaunchMode.isUnitTestHost(environment: [:]))
    }

    func testUITestRequestFailsClosedOutsideTheDebugHarness() {
        let environment = ["CANIS97_OFFLINE_REVIEW_MODE": "1"]

        XCTAssertTrue(OfflineReviewLaunchMode.isOfflineReviewRequested(environment: environment))
        XCTAssertNil(Canis97App.makeSessionController(environment: environment))
    }

    func testSemanticStatesHaveDistinctFixedPresentationCopy() {
        let model = AuthenticationPresentationModel()
        let states: [AuthenticationPresentationState] = [
            .localCredentialMissing,
            .localCredentialInvalid,
            .localCredentialUnavailable,
            .webSessionResetFailed,
            .waitingForWebView,
            .webCredentialMissing,
            .webCredentialMalformed,
            .webCredentialAmbiguous,
            .verifyingAuthentication,
            .verifyingEntitlement,
            .authenticatedButNotEntitled,
            .entitled,
            .restoreCompleted,
            .profileAuthorizationRejected,
            .entitlementAuthorizationRejected,
            .credentialNotDurable,
            .rejected,
            .challengeRequired,
            .unsupported,
            .signedOut,
            .cleanupFailed(.both),
            .finishingCleanup
        ]

        let copies = states.map { model.presentation(for: $0) }

        XCTAssertEqual(Set(copies.map(\.statusLabel)).count, states.count)
        XCTAssertTrue(model.presentation(for: .entitled).isReady)
        XCTAssertTrue(model.presentation(for: .entitled).canSignOut)
        XCTAssertEqual(model.presentation(for: .unsupported).message, "This sign-in flow is unsupported. No workaround was attempted.")
        XCTAssertEqual(model.presentation(for: .cleanupFailed(.both)).message, "You are signed out. Local cleanup was incomplete.")
    }

    func testOnlyEntitledStateExposesReadinessOrSignOut() {
        let model = AuthenticationPresentationModel()
        let nonEntitledStates: [AuthenticationPresentationState] = [
            .localCredentialMissing,
            .localCredentialInvalid,
            .localCredentialUnavailable,
            .webSessionResetFailed,
            .waitingForWebView,
            .webCredentialMissing,
            .webCredentialMalformed,
            .webCredentialAmbiguous,
            .verifyingAuthentication,
            .verifyingEntitlement,
            .authenticatedButNotEntitled,
            .rejected,
            .challengeRequired,
            .unsupported,
            .signedOut,
            .cleanupFailed(.keychain),
            .finishingCleanup
        ]

        for state in nonEntitledStates {
            XCTAssertFalse(model.presentation(for: state).isReady)
            XCTAssertFalse(model.presentation(for: state).canSignOut)
        }
    }

    func testClosedOracleUsesFixedStageSpecificClassifications() {
        let model = AuthenticationPresentationModel()

        XCTAssertEqual(
            model.presentation(for: .profileAuthorizationRejected).statusLabel,
            "profile-authorization-rejected"
        )
        XCTAssertEqual(
            model.presentation(for: .entitlementAuthorizationRejected).statusLabel,
            "entitlement-authorization-rejected"
        )
        XCTAssertFalse(model.presentation(for: .credentialNotDurable).isReady)
        XCTAssertTrue(model.presentation(for: .restoreCompleted).isReady)
    }

    func testLaunchRestorationRunsExactlyOnceWithoutUsingTheWebViewSession() async {
        let flow = AuthenticationFlowSpy(automaticRestoreResult: .entitled)
        let model = AuthenticationPresentationModel(flow: flow)

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(model.useLoggedInSession())

        let firstAttempt = model.restoreStoredCredentialOnLaunch()
        let repeatedAttempt = model.restoreStoredCredentialOnLaunch()
        await firstAttempt?.value

        XCTAssertNil(repeatedAttempt)
        XCTAssertEqual(model.state, .restoreCompleted)
        let counts = await flow.callCounts()
        XCTAssertEqual(counts.automaticRestore, 1)
        XCTAssertEqual(counts.begin, 0)
        XCTAssertEqual(counts.loggedInSession, 0)
    }

    func testRestoredReadyStateCanEnterThePlayerAndSignOut() async throws {
        let flow = AuthenticationFlowSpy(
            automaticRestoreResult: .entitled,
            signOutResult: .signedOut
        )
        let model = AuthenticationPresentationModel(flow: flow)

        await model.restoreStoredCredentialOnLaunch()?.value

        XCTAssertEqual(model.state, .restoreCompleted)
        XCTAssertTrue(model.isReady)
        try await XCTUnwrap(model.signOut()).value
        XCTAssertEqual(model.state, .signedOut)
        let counts = await flow.callCounts()
        XCTAssertEqual(counts.signOut, 1)
    }

    func testTerminalLaunchRestorationDoesNotRetryOrStartTheWebViewPath() async {
        let flow = AuthenticationFlowSpy(automaticRestoreResult: .unsupported)
        let model = AuthenticationPresentationModel(flow: flow)

        let firstAttempt = model.restoreStoredCredentialOnLaunch()
        let repeatedAttempt = model.restoreStoredCredentialOnLaunch()
        await firstAttempt?.value

        XCTAssertNil(repeatedAttempt)
        XCTAssertEqual(model.state, .unsupported)
        let counts = await flow.callCounts()
        XCTAssertEqual(counts.automaticRestore, 1)
        XCTAssertEqual(counts.begin, 0)
        XCTAssertEqual(counts.loggedInSession, 0)
    }

    func testSignInStartsOnlyOneBridgeActionWhileInFlight() async {
        let flow = AuthenticationFlowSpy(beginResults: [.rejected, .rejected], holdBegin: true)
        let model = AuthenticationPresentationModel(flow: flow)

        let firstAttempt = model.signIn()
        let secondAttempt = model.signIn()
        await Task.yield()

        XCTAssertTrue(model.isAttemptInFlight)
        XCTAssertEqual(model.state, .signedOut, "the WebView state must not be published before its request is queued")
        XCTAssertNil(secondAttempt)
        let pendingCounts = await flow.callCounts()
        XCTAssertEqual(pendingCounts.begin, 1)

        await flow.finishBegin()
        await firstAttempt?.value

        XCTAssertEqual(model.state, .rejected)
    }

    func testRetryRepeatsOnlyTheWebViewPathAfterTerminalResult() async {
        let flow = AuthenticationFlowSpy(beginResults: [.rejected, .waitingForWebView])
        let model = AuthenticationPresentationModel(flow: flow)

        await model.signIn()?.value
        await model.retry()?.value

        let retryCounts = await flow.callCounts()
        XCTAssertEqual(retryCounts.begin, 2)
        XCTAssertEqual(retryCounts.loggedInSession, 0)
        XCTAssertEqual(model.state, .waitingForWebView)
    }

    func testAutomaticallyDetectedSessionWaitsForWebViewSetupThenRunsExactlyOneTransaction() async {
        let flow = AuthenticationFlowSpy(
            beginResult: .waitingForWebView,
            holdBegin: true,
            loggedInSessionResult: .entitled
        )
        let model = AuthenticationPresentationModel(flow: flow)

        let signIn = model.signIn()
        await Task.yield()
        model.useAutomaticallyDetectedSession()

        var counts = await flow.callCounts()
        XCTAssertEqual(counts.loggedInSession, 0)
        await flow.finishBegin()
        await signIn?.value
        for _ in 0..<12 { await Task.yield() }

        counts = await flow.callCounts()
        XCTAssertEqual(counts.loggedInSession, 1)
        XCTAssertEqual(model.state, .entitled)

        model.useAutomaticallyDetectedSession()
        for _ in 0..<4 { await Task.yield() }
        counts = await flow.callCounts()
        XCTAssertEqual(counts.loggedInSession, 1)
    }

    func testTerminalFailuresScheduleNoFollowUpWork() async {
        let flow = AuthenticationFlowSpy(beginResult: .challengeRequired)
        let model = AuthenticationPresentationModel(flow: flow)

        await model.signIn()?.value

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

        XCTAssertNil(model.signOut())
        let signedOutCounts = await flow.callCounts()
        XCTAssertEqual(signedOutCounts.signOut, 0)

        await model.signIn()?.value
        await model.useLoggedInSession()?.value
        await model.signOut()?.value

        let cleanupCounts = await flow.callCounts()
        XCTAssertEqual(cleanupCounts.signOut, 1)
        XCTAssertEqual(model.state, .cleanupFailed(.browserResidue))
        XCTAssertEqual(model.presentation(for: model.state).message, "You are signed out. Local cleanup was incomplete.")
    }

    func testCleanupShowsOneFixedStateAndBlocksEveryAuthenticationActionUntilItFinishes() async throws {
        let flow = AuthenticationFlowSpy(beginResult: .entitled, holdSignOut: true, signOutResult: .signedOut)
        let model = AuthenticationPresentationModel(flow: flow)

        await model.signIn()?.value
        XCTAssertEqual(model.state, .entitled)

        let cleanup = try XCTUnwrap(model.signOut())
        await flow.waitUntilSignOutStarted()

        XCTAssertTrue(model.isAttemptInFlight)
        XCTAssertEqual(model.presentation(for: model.state).statusLabel, "cleanup-in-progress")
        XCTAssertNil(model.signIn())
        XCTAssertNil(model.useLoggedInSession())
        XCTAssertNil(model.retry())
        XCTAssertNil(model.restoreStoredCredentialOnLaunch())
        XCTAssertNil(model.signOut())
        XCTAssertNil(model.clearLocalSession())

        await flow.finishSignOut()
        await cleanup.value

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertFalse(model.isAttemptInFlight)
        let counts = await flow.callCounts()
        XCTAssertEqual(counts.signOut, 1)
    }
}

private actor AuthenticationFlowSpy: AuthenticationPresentationFlow {
    private var beginResults: [AuthenticationPresentationState]
    private let holdBegin: Bool
    private var beginContinuation: CheckedContinuation<Void, Never>?
    private let holdSignOut: Bool
    private var signOutContinuation: CheckedContinuation<Void, Never>?
    private var signOutStarted = false
    private var signOutStartContinuation: CheckedContinuation<Void, Never>?
    private let automaticRestoreResult: AuthenticationPresentationState
    private let loggedInSessionResult: AuthenticationPresentationState
    private let signOutResult: SignOutOutcome

    private(set) var beginCallCount = 0
    private(set) var automaticRestoreCallCount = 0
    private(set) var loggedInSessionCallCount = 0
    private(set) var signOutCallCount = 0

    init(
        beginResult: AuthenticationPresentationState = .waitingForWebView,
        beginResults: [AuthenticationPresentationState]? = nil,
        holdBegin: Bool = false,
        holdSignOut: Bool = false,
        automaticRestoreResult: AuthenticationPresentationState = .signedOut,
        loggedInSessionResult: AuthenticationPresentationState = .waitingForWebView,
        signOutResult: SignOutOutcome = .alreadySignedOut
    ) {
        self.beginResults = beginResults ?? [beginResult]
        self.holdBegin = holdBegin
        self.holdSignOut = holdSignOut
        self.automaticRestoreResult = automaticRestoreResult
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

    func restoreStoredCredential(
        onAuthenticationVerification: @MainActor @escaping @Sendable () -> Void,
        onEntitlementVerification: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        automaticRestoreCallCount += 1
        await onAuthenticationVerification()
        if automaticRestoreResult == .entitled {
            await onEntitlementVerification()
        }
        return automaticRestoreResult
    }

    func useLoggedInSession(
        onEntitlementVerification _: @MainActor @escaping @Sendable () -> Void
    ) async -> AuthenticationPresentationState {
        loggedInSessionCallCount += 1
        return loggedInSessionResult
    }

    func signOut() async -> SignOutOutcome {
        signOutCallCount += 1
        signOutStarted = true
        signOutStartContinuation?.resume()
        signOutStartContinuation = nil
        if holdSignOut {
            await withCheckedContinuation { continuation in
                signOutContinuation = continuation
            }
        }
        return signOutResult
    }

    func finishBegin() {
        beginContinuation?.resume()
        beginContinuation = nil
    }

    func waitUntilSignOutStarted() async {
        if signOutStarted { return }
        await withCheckedContinuation { continuation in
            signOutStartContinuation = continuation
        }
    }

    func finishSignOut() {
        signOutContinuation?.resume()
        signOutContinuation = nil
    }

    func callCounts() -> (automaticRestore: Int, begin: Int, loggedInSession: Int, signOut: Int) {
        (automaticRestoreCallCount, beginCallCount, loggedInSessionCallCount, signOutCallCount)
    }
}

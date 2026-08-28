import Foundation
import AppKit
import WebKit
import XCTest
@_spi(AppIntegration) import SiriusXMClient
@testable import Canis97

@MainActor
final class WebAuthenticationBridgeTests: XCTestCase {
    func testCreatesOnlyANonPersistentWebViewStoreAndDoesNotReadCookiesBeforeConsent() {
        let store = TestCookieStore(cookies: [])
        let bridge = WebAuthenticationBridge(cookieStore: store, credentialConsumer: { _ in })

        XCTAssertFalse(bridge.webViewConfiguration.websiteDataStore.isPersistent)
        XCTAssertEqual(store.readCount, 0)
    }

    func testAuthenticationWebViewDoesNotEnableInspection() {
        let bridge = WebAuthenticationBridge(cookieStore: TestCookieStore(cookies: []), credentialConsumer: { _ in })

        XCTAssertFalse(bridge.makeWebView().isInspectable)
        XCTAssertNotNil(bridge.makeWebView().navigationDelegate)
    }

    func testAuthenticationWebViewInstallsMaterialFreePageStateSignals() {
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: []),
            credentialConsumer: { _ in }
        )
        let sources = bridge.webViewConfiguration.userContentController.userScripts.map(\.source)
        let combined = sources.joined(separator: "\n")

        XCTAssertTrue(combined.contains("cookieStore"))
        XCTAssertTrue(combined.contains("PerformanceObserver"))
        XCTAssertTrue(combined.contains("xmlhttprequest"))
        XCTAssertTrue(combined.contains("siriusMacSessionStateMayHaveChanged"))
        XCTAssertFalse(combined.contains("AUTH_TOKEN"))
        XCTAssertFalse(combined.contains("DEVICE_GRANT"))
        XCTAssertFalse(combined.contains("document.cookie"))
    }

    func testExplicitConsentAcceptsOneCurrentBoundarySafeSiriusXMSubdomainToken() async throws {
        let recorder = CredentialRecorder()
        let now = Date()
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: [try authCookie(domain: ".player.siriusxm.com", expires: now.addingTimeInterval(60))]),
            now: { now },
            credentialConsumer: { credential in await recorder.record(credential) }
        )

        let result = await bridge.useLoggedInSession()
        let repeatedResult = await bridge.useLoggedInSession()
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(result, .credentialTransferred)
        XCTAssertEqual(repeatedResult, .alreadyConsumed)
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.descriptions, ["AuthenticationCredential(redacted)"])
        XCTAssertEqual(snapshot.browserSessionCount, 1)
    }

    func testExplicitConsentAcceptsCurrentTokenWhenWebKitReportsSecureFalse() async throws {
        let recorder = CredentialRecorder()
        let now = Date()
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: [
                try authCookie(
                    domain: ".player.siriusxm.com",
                    expires: now.addingTimeInterval(60),
                    secure: false
                ),
            ]),
            now: { now },
            credentialConsumer: { credential in await recorder.record(credential) }
        )

        let result = await bridge.useLoggedInSession()
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(result, .credentialTransferred)
        XCTAssertEqual(snapshot.count, 1)
    }

    func testExplicitSignInLoadsTheEstablishedPlayerEntryOnlyAfterVisibleWebViewInstallation() async {
        var loadedRequests: [URLRequest] = []
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: []),
            credentialConsumer: { _ in },
            signInRequestLoader: { loadedRequests.append($0) }
        )

        _ = await bridge.beginUserOperatedSignIn()
        XCTAssertTrue(loadedRequests.isEmpty)

        let host = WebAuthenticationWebViewHost(frame: .zero)
        let visibleWebView = bridge.makeWebView()
        host.install(visibleWebView)
        bridge.loadPendingSignInRequestIfNeeded()
        bridge.loadPendingSignInRequestIfNeeded()

        XCTAssertEqual(loadedRequests.map(\.url), [URL(string: "https://www.siriusxm.com/player")])
        XCTAssertTrue(host.subviews.first === visibleWebView)
    }

    func testExplicitSignInRetiresAndRotatesBeforeOnePlayerLoad() async {
        var loadedRequests: [URLRequest] = []
        var retireCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: []),
            credentialConsumer: { _ in },
            websiteSessionRetirer: {
                retireCount += 1
                return true
            },
            signInRequestLoader: { loadedRequests.append($0) }
        )
        let initialGeneration = bridge.websiteSessionGeneration

        let didBegin = await bridge.beginUserOperatedSignIn()
        bridge.loadPendingSignInRequestIfNeeded()

        XCTAssertTrue(didBegin)
        XCTAssertEqual(retireCount, 1)
        XCTAssertEqual(bridge.websiteSessionGeneration, initialGeneration + 1)
        XCTAssertEqual(loadedRequests.map(\.url), [URL(string: "https://www.siriusxm.com/player")])
    }

    func testFailedExplicitSignInRotationDoesNotLoadPlayerOrRearmSelection() async {
        var loadedRequests: [URLRequest] = []
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: []),
            credentialConsumer: { _ in },
            websiteSessionRetirer: { false },
            signInRequestLoader: { loadedRequests.append($0) }
        )

        let didBegin = await bridge.beginUserOperatedSignIn()

        XCTAssertFalse(didBegin)
        XCTAssertTrue(loadedRequests.isEmpty)
        let selection = await bridge.useLoggedInSession()
        XCTAssertEqual(selection, .alreadyConsumed)
    }

    func testExplicitNewAttemptDiscardsAnUnconsumedHandoffAndRearmsOneTransfer() async throws {
        let recorder = CredentialRecorder()
        let now = Date()
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: [try authCookie(expires: now.addingTimeInterval(60))]),
            now: { now },
            credentialConsumer: { credential in await recorder.record(credential) }
        )

        let firstTransfer = await bridge.useLoggedInSession()
        XCTAssertEqual(firstTransfer, .credentialTransferred)
        _ = await bridge.beginUserOperatedSignIn()
        let discardedCredential = await bridge.credential()
        let secondTransfer = await bridge.useLoggedInSession()
        let repeatedSecondTransfer = await bridge.useLoggedInSession()
        let snapshot = await recorder.snapshot()

        XCTAssertNil(discardedCredential)
        XCTAssertEqual(secondTransfer, .credentialTransferred)
        XCTAssertEqual(repeatedSecondTransfer, .alreadyConsumed)
        XCTAssertEqual(snapshot.count, 2)
    }

    func testMissingMultipleExpiredLookalikeAndUnsupportedCookiesFailClosed() throws {
        let now = Date()
        let valid = try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(60))
        let secureLeadingDotApex = try authCookie(domain: ".siriusxm.com", expires: now.addingTimeInterval(60))
        let exactWWW = try authCookie(domain: "www.siriusxm.com", expires: now.addingTimeInterval(60))
        let insecure = try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(60), secure: false)
        let expired = try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(-60))
        let playerSubdomain = try authCookie(domain: "player.siriusxm.com", expires: now.addingTimeInterval(60))
        let arbitrarySubdomain = try authCookie(domain: "account.siriusxm.com", expires: now.addingTimeInterval(60))
        let lookalike = try authCookie(domain: "evil-siriusxm.com", expires: now.addingTimeInterval(60))
        let unsupportedPath = try authCookie(domain: "siriusxm.com", path: "/account", expires: now.addingTimeInterval(60))

        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [], now: now), .missing)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [valid, valid], now: now), .ambiguous)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [secureLeadingDotApex], now: now), .one)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [exactWWW], now: now), .one)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [playerSubdomain], now: now), .one)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [arbitrarySubdomain], now: now), .one)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [insecure], now: now), .one)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [expired], now: now), .missing)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [lookalike], now: now), .missing)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: [unsupportedPath], now: now), .missing)
    }

    func testMalformedOrIncompletePayloadProducesATerminalResult() async throws {
        let now = Date()
        let malformed = try authCookie(value: "not-json", expires: now.addingTimeInterval(60))
        let incomplete = try authCookie(value: #"{"session":{}}"#, expires: now.addingTimeInterval(60))

        let malformedBridge = WebAuthenticationBridge(cookieStore: TestCookieStore(cookies: [malformed]), now: { now }, credentialConsumer: { _ in })
        let incompleteBridge = WebAuthenticationBridge(cookieStore: TestCookieStore(cookies: [incomplete]), now: { now }, credentialConsumer: { _ in })

        let malformedResult = await malformedBridge.useLoggedInSession()
        let incompleteResult = await incompleteBridge.useLoggedInSession()

        XCTAssertEqual(malformedResult, .malformedCredential)
        XCTAssertEqual(incompleteResult, .malformedCredential)
    }

    func testCookieChangesReportExactRedactedStagesAndAutomaticallyAnnounceACompleteSession() async throws {
        let now = Date()
        let store = TestCookieStore(cookies: [])
        var events: [AuthenticationBridgeDiagnostic] = []
        var readyCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: store,
            now: { now },
            credentialConsumer: { _ in },
            telemetry: AuthenticationBridgeTelemetry(record: { events.append($0) })
        )
        bridge.setAutomaticCredentialReadyHandler { readyCount += 1 }

        let didBegin = await bridge.beginUserOperatedSignIn()
        XCTAssertTrue(didBegin)
        store.replaceCookies(with: [try authCookie(value: #"{"session":{}}"#, expires: now.addingTimeInterval(60))])
        store.signalChange()
        await settleMainActorTasks()

        XCTAssertEqual(readyCount, 0)
        XCTAssertTrue(events.contains(.accessTokenMissing))
        XCTAssertTrue(events.contains(.malformedCredential))

        store.replaceCookies(with: [try authCookie(expires: now.addingTimeInterval(60))])
        store.signalChange()
        await settleMainActorTasks()

        XCTAssertEqual(readyCount, 1)
        XCTAssertTrue(events.contains(.automaticCredentialReady))
        let transfer = await bridge.useLoggedInSession()
        XCTAssertEqual(transfer, .credentialTransferred)

        store.signalChange()
        await settleMainActorTasks()
        XCTAssertEqual(readyCount, 1)
        XCTAssertFalse(events.map(\.rawValue).joined().contains("synthetic-access-token"))
    }

    func testAuthenticatedCookieWithoutDeviceGrantRemainsRenewable() throws {
        let now = Date()
        let authentication = try authCookie(expires: now.addingTimeInterval(60))

        guard case let .credential(credential) = WebCredentialSelectionPolicy.select(from: [authentication], now: now),
              let snapshot = credential.browserSessionSnapshot() else {
            XCTFail("Expected the authenticated browser session")
            return
        }
        XCTAssertNil(snapshot.deviceGrantCookieValue)
    }

    func testBrowserRenewalRunsOnlyForAnExpiringCompleteEnvelope() async throws {
        let now = Date()
        let current = try renewableTestCredential(
            accessToken: "synthetic-current-access",
            accessExpiresAt: now.addingTimeInterval(3_600)
        )
        let expired = try renewableTestCredential(
            accessToken: "synthetic-expired-access",
            accessExpiresAt: now.addingTimeInterval(-60)
        )
        let replacement = try renewableTestCredential(
            accessToken: "synthetic-refreshed-access",
            accessExpiresAt: now.addingTimeInterval(10_800)
        )
        var refreshCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: []),
            now: { now },
            credentialConsumer: { _ in },
            browserSessionRefresher: { _ in
                refreshCount += 1
                return replacement
            }
        )

        let unchanged = await bridge.refreshedCredential(ifNeeded: current)
        let refreshed = await bridge.refreshedCredential(ifNeeded: expired)

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(unchanged?.browserSessionSnapshot()?.accessTokenExpiresAt, current.browserSessionSnapshot()?.accessTokenExpiresAt)
        XCTAssertEqual(refreshed?.browserSessionSnapshot()?.accessTokenExpiresAt, replacement.browserSessionSnapshot()?.accessTokenExpiresAt)
    }

    func testTelemetryIdentifiesSafeCredentialSelectionOutcomesWithoutPayloads() async throws {
        let now = Date()
        var events: [AuthenticationBridgeDiagnostic] = []
        let telemetry = AuthenticationBridgeTelemetry(record: { events.append($0) })

        let missingBridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: []),
            now: { now },
            credentialConsumer: { _ in },
            telemetry: telemetry
        )
        let malformedBridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: [try authCookie(value: "not-json", expires: now.addingTimeInterval(60))]),
            now: { now },
            credentialConsumer: { _ in },
            telemetry: telemetry
        )
        let transferredBridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: [try authCookie(expires: now.addingTimeInterval(60))]),
            now: { now },
            credentialConsumer: { _ in },
            telemetry: telemetry
        )

        let missingResult = await missingBridge.useLoggedInSession()
        let malformedResult = await malformedBridge.useLoggedInSession()
        let transferredResult = await transferredBridge.useLoggedInSession()

        XCTAssertEqual(missingResult, .authCookieMissing)
        XCTAssertEqual(malformedResult, .malformedCredential)
        XCTAssertEqual(transferredResult, .credentialTransferred)
        XCTAssertEqual(events, [
            .credentialSelectionStarted,
            .authCookieNameAbsent,
            .authCookieMissing,
            .credentialSelectionStarted,
            .authenticationCookieUnreadable,
            .malformedCredential,
            .credentialSelectionStarted,
            .renewalViaRefreshToken,
            .deviceGrantAbsent,
            .credentialTransferred,
        ])
        XCTAssertFalse(events.map(\.rawValue).joined().contains("synthetic-access-token"))
    }

    func testTelemetryUsesOnlyClosedSelectionLabels() async throws {
        let now = Date()
        var events: [AuthenticationBridgeDiagnostic] = []
        let firstPartyToken = try authCookie(expires: now.addingTimeInterval(60))
        let firstPartyDevice = try authCookie(
            name: "DEVICE_GRANT",
            value: deviceGrantCookieValue(secretCanary: "device-secret-canary"),
            domain: "player.siriusxm.com",
            expires: now.addingTimeInterval(60)
        )
        let thirdParty = try authCookie(
            name: "TRACKING_COOKIE",
            value: "third-party-secret-canary",
            domain: "example.com",
            expires: now.addingTimeInterval(60)
        )
        let bridge = WebAuthenticationBridge(
            cookieStore: TestCookieStore(cookies: [thirdParty, firstPartyDevice, firstPartyToken]),
            now: { now },
            credentialConsumer: { _ in },
            telemetry: AuthenticationBridgeTelemetry(record: { events.append($0) })
        )

        let result = await bridge.useLoggedInSession()

        XCTAssertEqual(result, .credentialTransferred)
        XCTAssertEqual(events, [
            .credentialSelectionStarted,
            .renewalViaRefreshToken,
            .deviceGrantAccepted,
            .credentialTransferred,
        ])
        XCTAssertFalse(events.map(\.rawValue).joined().contains("secret-canary"))
    }

    func testAutomaticCaptureAcceptsCurrentSplitRenewalCookiesWithoutARefreshToken() async throws {
        let now = Date()
        let store = TestCookieStore(cookies: [])
        var events: [AuthenticationBridgeDiagnostic] = []
        var readyCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: store,
            now: { now },
            credentialConsumer: { _ in },
            telemetry: AuthenticationBridgeTelemetry(record: { events.append($0) })
        )
        bridge.setAutomaticCredentialReadyHandler { readyCount += 1 }

        let didBegin = await bridge.beginUserOperatedSignIn()
        XCTAssertTrue(didBegin)
        let authentication = try authCookie(
            value: currentAuthenticationCookieValue(expires: now.addingTimeInterval(3_600)),
            expires: now.addingTimeInterval(3_600)
        )
        let deviceGrant = try authCookie(
            name: "DEVICE_GRANT",
            value: deviceGrantCookieValue(),
            expires: now.addingTimeInterval(2_592_000)
        )
        store.replaceCookies(with: [authentication, deviceGrant])
        store.signalChange()
        await settleMainActorTasks()

        XCTAssertEqual(readyCount, 1)
        XCTAssertTrue(events.contains(.renewalViaDeviceGrant))
        XCTAssertTrue(events.contains(.deviceGrantAccepted))
        XCTAssertTrue(events.contains(.automaticCredentialReady))
        let transfer = await bridge.useLoggedInSession()
        XCTAssertEqual(transfer, .credentialTransferred)
    }

    func testPageStateSignalAutomaticallyCapturesWhenNativeCookieObserverDoesNotRepeat() async throws {
        let now = Date()
        let store = TestCookieStore(cookies: [])
        var events: [AuthenticationBridgeDiagnostic] = []
        var readyCount = 0
        let bridge = WebAuthenticationBridge(
            cookieStore: store,
            now: { now },
            credentialConsumer: { _ in },
            telemetry: AuthenticationBridgeTelemetry(record: { events.append($0) })
        )
        bridge.setAutomaticCredentialReadyHandler { readyCount += 1 }

        let didBegin = await bridge.beginUserOperatedSignIn()
        XCTAssertTrue(didBegin)
        store.replaceCookies(with: [
            try authCookie(
                value: currentAuthenticationCookieValue(expires: now.addingTimeInterval(3_600)),
                expires: now.addingTimeInterval(3_600)
            ),
            try authCookie(
                name: "DEVICE_GRANT",
                value: deviceGrantCookieValue(),
                expires: now.addingTimeInterval(2_592_000)
            ),
        ])

        bridge.webPageStateDidChange()
        await settleMainActorTasks()

        XCTAssertEqual(readyCount, 1)
        XCTAssertTrue(events.contains(.webPageStateChangeObserved))
        XCTAssertTrue(events.contains(.automaticCredentialInspectionStarted))
        XCTAssertTrue(events.contains(.renewalViaDeviceGrant))
        XCTAssertTrue(events.contains(.automaticCredentialReady))
    }

    func testMissingTokenTelemetryReportsOnlyClosedPolicyRejectionClasses() async throws {
        let now = Date()
        let scenarios: [(HTTPCookie, [AuthenticationBridgeDiagnostic])] = [
            (try authCookie(domain: "evil-siriusxm.com", expires: now.addingTimeInterval(60)), [.authCookieIssuerRejected]),
            (try authCookie(path: "/account", expires: now.addingTimeInterval(60)), [.authCookiePathRejected]),
            (try authCookie(expires: now.addingTimeInterval(-60)), [.authCookieExpired]),
        ]

        for (cookie, expectedDiagnostics) in scenarios {
            var events: [AuthenticationBridgeDiagnostic] = []
            let bridge = WebAuthenticationBridge(
                cookieStore: TestCookieStore(cookies: [cookie]),
                now: { now },
                credentialConsumer: { _ in },
                telemetry: AuthenticationBridgeTelemetry(record: { events.append($0) })
            )

            let result = await bridge.useLoggedInSession()

            XCTAssertEqual(result, .authCookieMissing)
            XCTAssertEqual(events, [.credentialSelectionStarted] + expectedDiagnostics + [.authCookieMissing])
        }

        let labels = AuthenticationBridgeDiagnostic.allCases.map(\.rawValue).joined(separator: ":")
        XCTAssertFalse(labels.contains("synthetic-access-token"))
        XCTAssertFalse(labels.contains("evil-siriusxm.com"))
    }

    func testConcurrentSelectionsReserveOneCookieReadAndOneCredentialTransfer() async throws {
        let now = Date()
        let cookie = try authCookie(expires: now.addingTimeInterval(60))
        let store = SuspendingCookieStore(responses: [[cookie]], suspendFirstRead: true)
        let recorder = CredentialRecorder()
        let bridge = WebAuthenticationBridge(
            cookieStore: store,
            now: { now },
            credentialConsumer: { credential in await recorder.record(credential) }
        )

        let firstSelection = Task { @MainActor in
            await bridge.useLoggedInSession()
        }
        await store.waitUntilFirstReadSuspended()

        let secondSelection = Task { @MainActor in
            await bridge.useLoggedInSession()
        }
        let secondResult = await secondSelection.value
        let readsBeforeResume = store.readCount

        store.resumeFirstRead()
        let firstResult = await firstSelection.value
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(secondResult, .alreadyConsumed)
        XCTAssertEqual(readsBeforeResume, 1)
        XCTAssertEqual(firstResult, .credentialTransferred)
        XCTAssertEqual(snapshot.count, 1)
    }

    func testPreCommitFailuresReleaseSelectionForAConfirmedRetry() async throws {
        let now = Date()
        let valid = try authCookie(expires: now.addingTimeInterval(60))
        let ambiguous = [valid, valid]
        let malformed = [try authCookie(value: "not-json", expires: now.addingTimeInterval(60))]
        let scenarios: [([HTTPCookie], WebAuthenticationBridge.Result)] = [
            ([], .authCookieMissing),
            (ambiguous, .ambiguousCredentials),
            (malformed, .malformedCredential),
        ]

        for (invalidCookies, expectedResult) in scenarios {
            let store = SuspendingCookieStore(responses: [invalidCookies, [valid]])
            let recorder = CredentialRecorder()
            let bridge = WebAuthenticationBridge(
                cookieStore: store,
                now: { now },
                credentialConsumer: { credential in await recorder.record(credential) }
            )

            let initialResult = await bridge.useLoggedInSession()
            let retryResult = await bridge.useLoggedInSession()
            let snapshot = await recorder.snapshot()

            XCTAssertEqual(initialResult, expectedResult)
            XCTAssertEqual(retryResult, .credentialTransferred)
            XCTAssertEqual(snapshot.count, 1)
        }
    }

    func testCancelledSelectionReleasesReservationWithoutDeliveringCredential() async throws {
        let now = Date()
        let valid = try authCookie(expires: now.addingTimeInterval(60))
        let store = SuspendingCookieStore(responses: [[valid], [valid]], suspendFirstRead: true)
        let recorder = CredentialRecorder()
        let bridge = WebAuthenticationBridge(
            cookieStore: store,
            now: { now },
            credentialConsumer: { credential in await recorder.record(credential) }
        )

        let cancelledSelection = Task { @MainActor in
            await bridge.useLoggedInSession()
        }
        await store.waitUntilFirstReadSuspended()
        cancelledSelection.cancel()
        store.resumeFirstRead()

        let cancelledResult = await cancelledSelection.value
        let retryResult = await bridge.useLoggedInSession()
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(cancelledResult, .cancelled)
        XCTAssertEqual(retryResult, .credentialTransferred)
        XCTAssertEqual(snapshot.count, 1)
    }

    func testCommittedSelectionStaysConsumedWhileTheCredentialConsumerSuspendsOrCallerCancels() async throws {
        let now = Date()
        let valid = try authCookie(expires: now.addingTimeInterval(60))
        let recorder = SuspendingCredentialRecorder()
        let bridge = WebAuthenticationBridge(
            cookieStore: SuspendingCookieStore(responses: [[valid]]),
            now: { now },
            credentialConsumer: { credential in await recorder.recordAndSuspend(credential) }
        )

        let firstSelection = Task { @MainActor in
            await bridge.useLoggedInSession()
        }
        await recorder.waitUntilFirstRecordSuspended()

        let overlappingResult = await Task { @MainActor in
            await bridge.useLoggedInSession()
        }.value
        firstSelection.cancel()
        await recorder.resumeFirstRecord()
        let firstResult = await firstSelection.value
        let subsequentResult = await bridge.useLoggedInSession()
        let snapshot = await recorder.snapshot()

        XCTAssertEqual(overlappingResult, .alreadyConsumed)
        XCTAssertEqual(firstResult, .credentialTransferred)
        XCTAssertEqual(subsequentResult, .alreadyConsumed)
        XCTAssertEqual(snapshot.count, 1)
    }

    func testExplicitNewAttemptBlocksSelectionUntilHandoffDisposalCompletes() async throws {
        let now = Date()
        let valid = try authCookie(expires: now.addingTimeInterval(60))
        let disposer = SuspendingHandoffDisposer()
        let bridge = WebAuthenticationBridge(
            cookieStore: SuspendingCookieStore(responses: [[valid]]),
            now: { now },
            credentialConsumer: { _ in },
            handoffDisposer: { await disposer.discardAndSuspend() }
        )

        let newAttempt = Task { @MainActor in
            await bridge.beginUserOperatedSignIn()
        }
        await disposer.waitUntilDiscardSuspended()

        let blockedSelection = await bridge.useLoggedInSession()
        await disposer.resumeDiscard()
        await disposer.waitUntilDiscardFinishes()
        _ = await newAttempt.value
        let rearmedSelection = await bridge.useLoggedInSession()

        XCTAssertEqual(blockedSelection, .alreadyConsumed)
        XCTAssertEqual(rearmedSelection, .credentialTransferred)
    }

    func testSignOutDeletesEveryBoundarySafeFirstPartyMatchThenRescans() async throws {
        let now = Date()
        let store = TestCookieStore(cookies: [
            try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(60)),
            try authCookie(domain: "www.siriusxm.com", expires: now.addingTimeInterval(60)),
            try authCookie(domain: "player.siriusxm.com", expires: now.addingTimeInterval(60), secure: false),
            try authCookie(domain: "evil-siriusxm.com", expires: now.addingTimeInterval(60)),
        ])
        let bridge = WebAuthenticationBridge(cookieStore: store, now: { now }, credentialConsumer: { _ in })

        let result = await bridge.removeAuthenticationResidue()
        let remainingCookies = await store.allCookies()

        XCTAssertEqual(result, .removed)
        XCTAssertEqual(store.deletedCount, 3)
        XCTAssertEqual(FirstPartyTokenCookiePolicy.select(from: remainingCookies, now: now), .missing)
    }

    func testSignOutFailsClosedWhenDeletionFailsOrAMatchingCookieRemains() async throws {
        let now = Date()
        let token = try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(60))
        let deleteFailureStore = TestCookieStore(cookies: [token], deleteFailure: true)
        let staleStore = TestCookieStore(cookies: [token], retainDeletedCookies: true)

        let deleteFailure = await WebAuthenticationBridge(cookieStore: deleteFailureStore, now: { now }, credentialConsumer: { _ in }).removeAuthenticationResidue()
        let staleResult = await WebAuthenticationBridge(cookieStore: staleStore, now: { now }, credentialConsumer: { _ in }).removeAuthenticationResidue()

        XCTAssertEqual(deleteFailure, .cleanupFailed)
        XCTAssertEqual(staleResult, .cleanupFailed)
    }

    func testSignOutRescansExactTokensThenRetiresTheOwnedWebsiteSession() async throws {
        let now = Date()
        let store = TestCookieStore(
            cookies: [
                try authCookie(domain: "siriusxm.com", expires: now.addingTimeInterval(60)),
                try authCookie(domain: "www.siriusxm.com", expires: now.addingTimeInterval(60)),
            ],
            hasSyntheticSessionResidue: true
        )
        let bridge = WebAuthenticationBridge(
            cookieStore: store,
            now: { now },
            credentialConsumer: { _ in },
            websiteSessionRetirer: { await store.retireAuthenticationWebsiteSession() }
        )
        let retiredWebView = bridge.makeWebView()

        let result = await bridge.removeAuthenticationResidue()
        let freshWebView = bridge.makeWebView()

        XCTAssertEqual(result, .removed)
        XCTAssertEqual(store.eventLog, ["read", "delete", "delete", "read", "retire"])
        XCTAssertEqual(store.retirementCount, 1)
        XCTAssertFalse(store.hasSyntheticSessionResidue)
        XCTAssertEqual(bridge.websiteSessionGeneration, 1)
        XCTAssertFalse(retiredWebView === freshWebView)
        XCTAssertFalse(bridge.webViewConfiguration.websiteDataStore.isPersistent)
    }

    func testSignOutReportsEveryPartialFailureButStillAttemptsWebsiteSessionRetirement() async throws {
        let now = Date()
        let deleteFailureStore = TestCookieStore(
            cookies: [try authCookie(expires: now.addingTimeInterval(60))],
            deleteFailure: true,
            hasSyntheticSessionResidue: true
        )
        let staleStore = TestCookieStore(
            cookies: [try authCookie(expires: now.addingTimeInterval(60))],
            retainDeletedCookies: true,
            hasSyntheticSessionResidue: true
        )
        let retirementFailureStore = TestCookieStore(
            cookies: [try authCookie(expires: now.addingTimeInterval(60))],
            retirementFailure: true,
            hasSyntheticSessionResidue: true
        )

        let deleteFailure = await WebAuthenticationBridge(
            cookieStore: deleteFailureStore,
            now: { now },
            credentialConsumer: { _ in },
            websiteSessionRetirer: { await deleteFailureStore.retireAuthenticationWebsiteSession() }
        ).removeAuthenticationResidue()
        let staleResult = await WebAuthenticationBridge(
            cookieStore: staleStore,
            now: { now },
            credentialConsumer: { _ in },
            websiteSessionRetirer: { await staleStore.retireAuthenticationWebsiteSession() }
        ).removeAuthenticationResidue()
        let retirementFailure = await WebAuthenticationBridge(
            cookieStore: retirementFailureStore,
            now: { now },
            credentialConsumer: { _ in },
            websiteSessionRetirer: { await retirementFailureStore.retireAuthenticationWebsiteSession() }
        ).removeAuthenticationResidue()

        XCTAssertEqual(deleteFailure, .cleanupFailed)
        XCTAssertEqual(staleResult, .cleanupFailed)
        XCTAssertEqual(retirementFailure, .cleanupFailed)
        XCTAssertEqual(deleteFailureStore.eventLog, ["read", "delete", "read", "retire"])
        XCTAssertEqual(staleStore.eventLog, ["read", "delete", "read", "retire"])
        XCTAssertEqual(retirementFailureStore.eventLog, ["read", "delete", "read", "retire"])
        XCTAssertEqual(deleteFailureStore.retirementCount, 1)
        XCTAssertEqual(staleStore.retirementCount, 1)
        XCTAssertEqual(retirementFailureStore.retirementCount, 1)
    }

    func testStableWebViewHostReplacesTheRetiredChild() async throws {
        let now = Date()
        let store = TestCookieStore(cookies: [try authCookie(expires: now.addingTimeInterval(60))])
        let bridge = WebAuthenticationBridge(
            cookieStore: store,
            now: { now },
            credentialConsumer: { _ in },
            websiteSessionRetirer: { await store.retireAuthenticationWebsiteSession() }
        )
        let host = WebAuthenticationWebViewHost(frame: .zero)
        let retiredWebView = bridge.makeWebView()
        host.install(retiredWebView)

        let cleanup = await bridge.removeAuthenticationResidue()
        let freshWebView = bridge.makeWebView()
        host.install(freshWebView)

        XCTAssertEqual(cleanup, .removed)
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertTrue(host.subviews[0] === freshWebView)
        XCTAssertFalse(host.subviews[0] === retiredWebView)
    }

    func testLookalikeDomainIsNeitherTransferredNorAnExactCleanupMatch() async throws {
        let now = Date()
        let store = TestCookieStore(cookies: [
            try authCookie(domain: "evil-siriusxm.com", expires: now.addingTimeInterval(60)),
        ])
        let bridge = WebAuthenticationBridge(cookieStore: store, now: { now }, credentialConsumer: { _ in })

        let extraction = await bridge.useLoggedInSession()
        let cleanup = await bridge.removeAuthenticationResidue()

        XCTAssertEqual(extraction, .authCookieMissing)
        XCTAssertEqual(cleanup, .removed)
        XCTAssertEqual(store.deletedCount, 0)
    }

    func testBridgeAndTestsAreUnconditionallyIncludedWithoutPlanningArtifactChecks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("SiriusMac.xcodeproj/project.pbxproj"), encoding: .utf8)
        let testSource = try String(contentsOf: root.appendingPathComponent("SiriusMacTests/WebAuthenticationBridgeTests.swift"), encoding: .utf8)

        XCTAssertTrue(project.contains("WebAuthenticationBridge.swift in Sources"))
        XCTAssertTrue(project.contains("WebAuthenticationBridgeTests.swift in Sources"))
        XCTAssertTrue(project.contains("SelectedAuthenticationCompositionTests.swift in Sources"))
        let planningDirectory = "." + "planning"
        XCTAssertFalse(project.contains(planningDirectory))
        let excludedImport = "can" + "Import(AuthFeasibilityHarness)"
        XCTAssertFalse(testSource.contains(excludedImport))
    }

    private func authCookie(
        name: String = "AUTH_TOKEN",
        value: String? = nil,
        domain: String = "siriusxm.com",
        path: String = "/",
        expires: Date,
        secure: Bool = true
    ) throws -> HTTPCookie {
        let resolvedValue = value ?? authenticationCookieValue(expires: expires)
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: resolvedValue.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? resolvedValue,
            .domain: domain,
            .path: path,
            .expires: expires,
        ]
        if secure {
            properties[.secure] = "TRUE"
        }
        return try XCTUnwrap(HTTPCookie(properties: properties))
    }

    private func settleMainActorTasks() async {
        for _ in 0..<12 { await Task.yield() }
    }
}

private func authenticationCookieValue(expires: Date) -> String {
    let formatter = ISO8601DateFormatter()
    let object: [String: Any] = [
        "handle": "synthetic-handle",
        "identityGrant": ["grant": "synthetic-identity-grant", "identityId": "synthetic-identity"],
        "session": [
            "accessToken": "synthetic-access-token",
            "accessTokenExpiresAt": formatter.string(from: expires),
            "refreshToken": "synthetic-refresh-token",
            "refreshTokenExpiresAt": formatter.string(from: Date(timeIntervalSinceNow: 7_776_000)),
            "sessionType": "authenticated",
        ],
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

private func currentAuthenticationCookieValue(expires: Date) -> String {
    let formatter = ISO8601DateFormatter()
    let object: [String: Any] = [
        "session": [
            "accessToken": "synthetic-current-access-token",
            "accessTokenExpiresAt": formatter.string(from: expires),
            "refreshTokenExpiresAt": formatter.string(from: Date(timeIntervalSinceNow: 7_776_000)),
            "sessionType": "authenticated",
        ],
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

private func deviceGrantCookieValue(secretCanary: String = "synthetic-device-refresh-grant") -> String {
    let formatter = ISO8601DateFormatter()
    let object: [String: Any] = [
        "deviceId": "synthetic-device",
        "grant": "synthetic-device-grant",
        "grantExpiresAt": formatter.string(from: Date(timeIntervalSinceNow: 2_592_000)),
        "grantVersion": "v2",
        "refreshGrant": secretCanary,
        "refreshGrantExpiresAt": formatter.string(from: Date(timeIntervalSinceNow: 15_552_000)),
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

@MainActor
private final class TestCookieStore: WebAuthenticationCookieStore, WebAuthenticationCookieChangeObserving {
    private var cookies: [HTTPCookie]
    private let deleteFailure: Bool
    private let retainDeletedCookies: Bool
    private let retirementFailure: Bool
    private(set) var hasSyntheticSessionResidue: Bool
    private(set) var readCount = 0
    private(set) var deletedCount = 0
    private(set) var retirementCount = 0
    private(set) var eventLog: [String] = []
    private var changeHandler: (@MainActor @Sendable () -> Void)?

    init(
        cookies: [HTTPCookie],
        deleteFailure: Bool = false,
        retainDeletedCookies: Bool = false,
        retirementFailure: Bool = false,
        hasSyntheticSessionResidue: Bool = false
    ) {
        self.cookies = cookies
        self.deleteFailure = deleteFailure
        self.retainDeletedCookies = retainDeletedCookies
        self.retirementFailure = retirementFailure
        self.hasSyntheticSessionResidue = hasSyntheticSessionResidue
    }

    func allCookies() async -> [HTTPCookie] {
        readCount += 1
        eventLog.append("read")
        return cookies
    }

    func delete(_ cookie: HTTPCookie) async throws {
        eventLog.append("delete")
        if deleteFailure { throw TestCookieStoreError.deleteFailed }
        deletedCount += 1
        if !retainDeletedCookies {
            cookies.removeAll { $0 === cookie }
        }
    }

    func setChangeHandler(_ handler: (@MainActor @Sendable () -> Void)?) {
        changeHandler = handler
    }

    func replaceCookies(with cookies: [HTTPCookie]) {
        self.cookies = cookies
    }

    func signalChange() {
        changeHandler?()
    }

    func retireAuthenticationWebsiteSession() async -> Bool {
        eventLog.append("retire")
        retirementCount += 1
        guard !retirementFailure else { return false }
        hasSyntheticSessionResidue = false
        return true
    }
}

private enum TestCookieStoreError: Error {
    case deleteFailed
}

private actor CredentialRecorder {
    private(set) var count = 0
    private(set) var descriptions: [String] = []
    private(set) var browserSessionCount = 0

    func record(_ credential: AuthenticationCredential) {
        count += 1
        descriptions.append(credential.description)
        if credential.browserSessionSnapshot() != nil {
            browserSessionCount += 1
        }
    }

    func snapshot() -> (count: Int, descriptions: [String], browserSessionCount: Int) {
        (count, descriptions, browserSessionCount)
    }
}

@MainActor
private final class SuspendingCookieStore: WebAuthenticationCookieStore {
    private var responses: [[HTTPCookie]]
    private let suspendFirstRead: Bool
    private var didSuspendFirstRead = false
    private var firstReadContinuation: CheckedContinuation<[HTTPCookie], Never>?
    private var firstReadStartedContinuation: CheckedContinuation<Void, Never>?
    private(set) var readCount = 0

    init(responses: [[HTTPCookie]], suspendFirstRead: Bool = false) {
        self.responses = responses
        self.suspendFirstRead = suspendFirstRead
    }

    func allCookies() async -> [HTTPCookie] {
        readCount += 1
        guard suspendFirstRead, !didSuspendFirstRead else {
            return nextResponse()
        }

        didSuspendFirstRead = true
        firstReadStartedContinuation?.resume()
        firstReadStartedContinuation = nil
        return await withCheckedContinuation { continuation in
            firstReadContinuation = continuation
        }
    }

    func delete(_ cookie: HTTPCookie) async throws {}

    func waitUntilFirstReadSuspended() async {
        guard didSuspendFirstRead, firstReadContinuation != nil else {
            await withCheckedContinuation { continuation in
                firstReadStartedContinuation = continuation
            }
            return
        }
    }

    func resumeFirstRead() {
        guard let firstReadContinuation else {
            XCTFail("Expected the first cookie read to be suspended")
            return
        }

        self.firstReadContinuation = nil
        firstReadContinuation.resume(returning: nextResponse())
    }

    private func nextResponse() -> [HTTPCookie] {
        guard !responses.isEmpty else { return [] }
        return responses.removeFirst()
    }
}

private actor SuspendingCredentialRecorder {
    private var count = 0
    private var descriptions: [String] = []
    private var firstRecordContinuation: CheckedContinuation<Void, Never>?
    private var firstRecordStartedContinuation: CheckedContinuation<Void, Never>?

    func recordAndSuspend(_ credential: AuthenticationCredential) async {
        count += 1
        descriptions.append(credential.description)
        firstRecordStartedContinuation?.resume()
        firstRecordStartedContinuation = nil
        await withCheckedContinuation { continuation in
            firstRecordContinuation = continuation
        }
    }

    func waitUntilFirstRecordSuspended() async {
        guard firstRecordContinuation != nil else {
            await withCheckedContinuation { continuation in
                firstRecordStartedContinuation = continuation
            }
            return
        }
    }

    func resumeFirstRecord() {
        guard let firstRecordContinuation else {
            XCTFail("Expected the credential consumer to be suspended")
            return
        }

        self.firstRecordContinuation = nil
        firstRecordContinuation.resume()
    }

    func snapshot() -> (count: Int, descriptions: [String]) {
        (count, descriptions)
    }
}

private actor SuspendingHandoffDisposer {
    private var discardContinuation: CheckedContinuation<Void, Never>?
    private var discardStartedContinuation: CheckedContinuation<Void, Never>?
    private var discardFinishedContinuation: CheckedContinuation<Void, Never>?

    func discardAndSuspend() async {
        discardStartedContinuation?.resume()
        discardStartedContinuation = nil
        await withCheckedContinuation { continuation in
            discardContinuation = continuation
        }
        discardFinishedContinuation?.resume()
        discardFinishedContinuation = nil
    }

    func waitUntilDiscardSuspended() async {
        guard discardContinuation != nil else {
            await withCheckedContinuation { continuation in
                discardStartedContinuation = continuation
            }
            return
        }
    }

    func resumeDiscard() {
        guard let discardContinuation else {
            XCTFail("Expected volatile handoff disposal to be suspended")
            return
        }

        self.discardContinuation = nil
        discardContinuation.resume()
    }

    func waitUntilDiscardFinishes() async {
        await withCheckedContinuation { continuation in
            discardFinishedContinuation = continuation
        }
    }
}

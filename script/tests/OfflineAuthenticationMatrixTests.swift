import Foundation

@main
struct OfflineAuthenticationMatrixTests {
    static func main() {
        let requestedScope = CommandLine.arguments.dropFirst().first ?? "--complete"
        let cases: [(String, () -> Void)] = [
            ("oracle profile rejection is fixed", testProfileRejection),
            ("oracle entitlement rejection is fixed", testEntitlementRejection),
            ("oracle persistence failure is not ready", testPersistenceFailure),
            ("oracle durable restore is ready", testRestoreCompletion),
            ("oracle labels do not retain canary material", testCanaryRedaction),
        ]
        let localCases: [(String, () -> Void)] = [
            ("local missing stays out of WebView", testMissingLocalCredential),
            ("local invalid stays out of WebView", testInvalidLocalCredential),
            ("local unavailable stays out of WebView", testUnavailableLocalCredential),
            ("local restore completes without WebView", testValidLocalCredential),
        ]
        let webCases: [(String, () -> Void)] = [
            ("web missing is fixed", testWebMissing),
            ("web malformed is fixed", testWebMalformed),
            ("web ambiguous is fixed", testWebAmbiguous),
            ("web transfer is single-consumption", testWebTransferred),
            ("web reset failure is terminal", testWebResetFailure),
        ]

        let selected: [(String, () -> Void)]
        switch requestedScope {
        case "--oracle-only": selected = cases
        case "--local-only": selected = localCases
        default: selected = cases + localCases + webCases
        }
        for (name, test) in selected {
            test()
            print("PASS: \(name)")
        }
    }

    private static func testProfileRejection() {
        expect(
            ClosedAuthenticationOracle.presentation(for: .profileUnauthorized).statusLabel,
            equals: "profile-authorization-rejected"
        )
    }

    private static func testEntitlementRejection() {
        expect(
            ClosedAuthenticationOracle.presentation(for: .entitlementForbidden).statusLabel,
            equals: "entitlement-authorization-rejected"
        )
    }

    private static func testPersistenceFailure() {
        let presentation = ClosedAuthenticationOracle.presentation(for: .persistenceFailed)
        expect(presentation.isReady, equals: false)
        expect(presentation.canSignOut, equals: false)
        expect(presentation.statusLabel, equals: "credential-not-durable")
    }

    private static func testRestoreCompletion() {
        let presentation = ClosedAuthenticationOracle.presentation(for: .restoreCompleted)
        expect(presentation.isReady, equals: true)
        expect(presentation.canSignOut, equals: true)
        expect(presentation.statusLabel, equals: "restore-completed")
    }

    private static func testCanaryRedaction() {
        let canary = "offline-secret-canary"
        for terminal in ClosedAuthenticationTerminal.allCases {
            let presentation = ClosedAuthenticationOracle.presentation(for: terminal)
            let surface = [presentation.title, presentation.message, presentation.statusLabel].joined(separator: "|")
            expect(surface.contains(canary), equals: false)
        }
    }

    private static func testMissingLocalCredential() {
        let outcome = ClosedAuthenticationOracle.restoreOutcome(for: .missing)
        expect(outcome.terminal, equals: .localCredentialMissing)
        expect(outcome.webViewLoads, equals: 0)
        expect(outcome.nativeTransactions, equals: 0)
    }

    private static func testInvalidLocalCredential() {
        let outcome = ClosedAuthenticationOracle.restoreOutcome(for: .invalid)
        expect(outcome.terminal, equals: .localCredentialInvalid)
        expect(outcome.webViewLoads, equals: 0)
        expect(outcome.nativeTransactions, equals: 0)
    }

    private static func testUnavailableLocalCredential() {
        let outcome = ClosedAuthenticationOracle.restoreOutcome(for: .unavailable)
        expect(outcome.terminal, equals: .localCredentialUnavailable)
        expect(outcome.webViewLoads, equals: 0)
        expect(outcome.nativeTransactions, equals: 0)
    }

    private static func testValidLocalCredential() {
        let outcome = ClosedAuthenticationOracle.restoreOutcome(for: .credential)
        expect(outcome.terminal, equals: .restoreCompleted)
        expect(outcome.webViewLoads, equals: 0)
        expect(outcome.nativeTransactions, equals: 1)
    }

    private static func testWebMissing() {
        expect(ClosedAuthenticationOracle.webOutcome(for: .missing).statusLabel, equals: "web-credential-missing")
    }

    private static func testWebMalformed() {
        expect(ClosedAuthenticationOracle.webOutcome(for: .malformed).statusLabel, equals: "web-credential-malformed")
    }

    private static func testWebAmbiguous() {
        expect(ClosedAuthenticationOracle.webOutcome(for: .ambiguous).statusLabel, equals: "web-credential-ambiguous")
    }

    private static func testWebTransferred() {
        let outcome = ClosedAuthenticationOracle.webOutcome(for: .transferred)
        expect(outcome.statusLabel, equals: "web-credential-transferred")
        expect(outcome.isSingleConsumption, equals: true)
    }

    private static func testWebResetFailure() {
        let outcome = ClosedAuthenticationOracle.webOutcome(for: .resetFailed)
        expect(outcome.statusLabel, equals: "web-session-reset-failed")
        expect(outcome.allowsPlayerLoad, equals: false)
    }

    private static func expect<T: Equatable>(_ actual: T, equals expected: T) {
        guard actual == expected else {
            fputs("FAIL: expected \(expected), got \(actual)\n", stderr)
            exit(1)
        }
    }
}

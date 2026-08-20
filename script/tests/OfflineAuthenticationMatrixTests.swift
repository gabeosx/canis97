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

        let selected = requestedScope == "--oracle-only" ? cases : cases
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

    private static func expect<T: Equatable>(_ actual: T, equals expected: T) {
        guard actual == expected else {
            fputs("FAIL: expected \(expected), got \(actual)\n", stderr)
            exit(1)
        }
    }
}

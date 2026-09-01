import XCTest
import SiriusXMClient
@testable import Canis97

final class CompatibilitySupportTests: XCTestCase {
    func testSnapshotIdentifiesEveryCompatibilityStage() {
        let snapshot = CompatibilitySnapshot.make(
            authentication: .entitled,
            catalog: .available(LiveCatalogSnapshot(channels: [], freshness: .fresh)),
            playback: .unavailable(.decoderUnavailable),
            metadata: .failed
        )

        XCTAssertEqual(snapshot.findings, [
            .init(area: .authentication, classification: .available),
            .init(area: .entitlement, classification: .available),
            .init(area: .catalog, classification: .available),
            .init(area: .stream, classification: .available),
            .init(area: .metadata, classification: .degraded),
            .init(area: .playback, classification: .unavailable),
        ])
    }

    func testResolutionFailureStopsAtStreamStage() {
        let snapshot = CompatibilitySnapshot.make(
            authentication: .entitled,
            catalog: .available(LiveCatalogSnapshot(channels: [], freshness: .fresh)),
            playback: .unavailable(.resolutionUnavailable),
            metadata: .unavailable
        )

        XCTAssertEqual(
            snapshot.findings.first(where: { $0.area == .stream })?.classification,
            .unavailable
        )
        XCTAssertEqual(
            snapshot.findings.first(where: { $0.area == .playback })?.classification,
            .notChecked
        )
    }

    func testSupportBundleIsAnAllowlistedSecretFreeDocument() throws {
        let bundle = SupportBundle(
            schemaVersion: SupportBundle.schemaVersion,
            product: "Canis97",
            version: "0.1.0",
            build: "1",
            operatingSystem: "macOS 26.0",
            architecture: "arm64",
            authentication: .unknown,
            compatibility: CompatibilitySnapshot.signedOut.findings,
            diagnostics: [
                SupportDiagnosticEntry(
                    recordedAt: Date(timeIntervalSince1970: 1_000),
                    code: .catalogUnsupportedResponse
                ),
            ]
        )

        let data = try SupportBundleFactory.encoded(bundle)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(
            Set(object.keys),
            Set(["schemaVersion", "product", "version", "build", "operatingSystem", "architecture", "authentication", "compatibility", "diagnostics"])
        )
        let compatibility = try XCTUnwrap(object["compatibility"] as? [[String: Any]])
        XCTAssertEqual(compatibility.count, CompatibilityArea.allCases.count)
        for finding in compatibility {
            XCTAssertEqual(Set(finding.keys), Set(["area", "classification"]))
        }
        let diagnostics = try XCTUnwrap(object["diagnostics"] as? [[String: Any]])
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(
            Set(diagnostics[0].keys),
            Set(["recordedAt", "area", "severity", "code", "summary", "suggestedAction"])
        )
        XCTAssertEqual(diagnostics[0]["code"] as? String, "catalog.unsupported-response")
        XCTAssertEqual(diagnostics[0]["area"] as? String, "catalog")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Authorization"))
    }

    func testSnapshotKeepsTheSixAreasOrderedForUncheckedAndUnavailableStates() {
        let snapshot = CompatibilitySnapshot.make(
            authentication: .signedOut,
            catalog: .idle,
            playback: .stopped,
            metadata: .unavailable
        )

        XCTAssertEqual(snapshot.findings.map(\.area), [
            .authentication, .entitlement, .catalog, .stream, .metadata, .playback,
        ])
        XCTAssertEqual(snapshot.findings.map(\.classification), [
            .notChecked, .notChecked, .notChecked, .notChecked, .unavailable, .notChecked,
        ])
    }

    func testSupportPreviewAndExportShareTheSameReviewedEncoding() throws {
        let bundle = SupportBundle(
            schemaVersion: SupportBundle.schemaVersion,
            product: "Canis97",
            version: "0.1.0",
            build: "1",
            operatingSystem: "macOS 26.0",
            architecture: "arm64",
            authentication: .unknown,
            compatibility: CompatibilitySnapshot.signedOut.findings,
            diagnostics: []
        )

        let preview = try SupportBundleFactory.encoded(bundle)
        let exported = try SupportBundleFactory.encoded(bundle)
        XCTAssertEqual(preview, exported)
    }

    @MainActor
    func testDiagnosticJournalIsBoundedAndCoalescesImmediateDuplicates() {
        let journal = SupportDiagnosticJournal()
        let start = Date(timeIntervalSince1970: 1_000)

        journal.record(.catalogUnsupportedResponse, at: start)
        journal.record(.catalogUnsupportedResponse, at: start.addingTimeInterval(1))
        XCTAssertEqual(journal.entries.count, 1)

        for offset in 0 ... SupportDiagnosticJournal.maximumEntries {
            journal.record(
                offset.isMultiple(of: 2) ? .catalogCollectionMissing : .catalogMalformedChannel,
                at: start.addingTimeInterval(Double(120 + offset * 61))
            )
        }

        XCTAssertEqual(journal.entries.count, SupportDiagnosticJournal.maximumEntries)
        XCTAssertNotEqual(journal.entries.first?.recordedAt, start)
    }

    @MainActor
    func testAuthenticationSupportRecordsCredentialLoadAndRenewalWithoutTokenMaterial() throws {
        let journal = SupportDiagnosticJournal()
        let start = Date(timeIntervalSince1970: 1_000)
        let sourceReference = "credential:11111111-1111-1111-1111-111111111111"
        let replacementReference = "credential:22222222-2222-2222-2222-222222222222"

        journal.recordAuthenticationState("stored-session-restored", successful: true, at: start.addingTimeInterval(-10))
        journal.recordAuthenticationState("verifying-authentication", successful: false, at: start)
        journal.recordStoredCredentialLoad(StoredCredentialLoadDiagnostic(
            recordedAt: start,
            purpose: .automaticRestore,
            outcome: .ready,
            credentialReference: sourceReference
        ))
        journal.recordNativeAuthenticationAttempt(NativeAuthenticationAttemptDiagnostic(
            recordedAt: start,
            outcome: .transportConnectionFailed
        ))
        journal.recordRenewalAttempt(AuthenticationRenewalAttemptDiagnostic(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            attemptedAt: start,
            completedAt: start.addingTimeInterval(2),
            sourceCredentialReference: sourceReference,
            renewalCredential: .deviceRefreshGrant,
            accessTokenExpiresAt: start.addingTimeInterval(-30),
            sessionRenewalExpiresAt: start.addingTimeInterval(7_776_000),
            renewalCredentialExpiresAt: start.addingTimeInterval(15_552_000),
            deviceGrantExpiresAt: start.addingTimeInterval(2_592_000),
            outcome: .replacementReceived,
            replacementCredentialReference: replacementReference
        ))

        let data = try SupportBundleFactory.encoded(SupportBundleFactory.make(
            snapshot: .signedOut,
            authentication: journal.authenticationSupport,
            diagnostics: journal.entries
        ))
        let encoded = String(decoding: data, as: UTF8.self)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let authentication = try XCTUnwrap(object["authentication"] as? [String: Any])
        let renewal = try XCTUnwrap(authentication["lastRenewalAttempt"] as? [String: Any])

        XCTAssertTrue(encoded.contains("device-refresh-grant"))
        XCTAssertTrue(encoded.contains("replacement-received"))
        XCTAssertTrue(encoded.contains("transport-connection-failed"))
        XCTAssertTrue(encoded.contains(sourceReference))
        XCTAssertTrue(encoded.contains(replacementReference))
        XCTAssertFalse(encoded.contains("AUTH_TOKEN"))
        XCTAssertFalse(encoded.contains("DEVICE_GRANT"))
        XCTAssertFalse(encoded.contains("Bearer"))
        XCTAssertEqual(Set(authentication.keys), Set([
            "currentState", "lastSuccessfulAuthenticationAt", "lastStoredCredentialLoad", "lastRenewalAttempt",
            "lastNativeAuthenticationAttempt",
        ]))
        XCTAssertEqual(Set(renewal.keys), Set([
            "id", "attemptedAt", "completedAt", "sourceCredentialReference", "renewalCredential",
            "accessTokenExpiresAt", "sessionRenewalExpiresAt", "renewalCredentialExpiresAt",
            "deviceGrantExpiresAt", "outcome", "replacementCredentialReference",
        ]))
    }

    func testPartialLineupDiagnosticExplainsTheCatalogFailureWithoutProviderMaterial() throws {
        let entry = SupportDiagnosticEntry(
            recordedAt: Date(timeIntervalSince1970: 1_000),
            code: .catalogPartialLineup
        )
        let data = try JSONEncoder().encode(entry)
        let encoded = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(entry.area, .catalog)
        XCTAssertEqual(entry.severity, .error)
        XCTAssertTrue(entry.summary.contains("curated subset"))
        XCTAssertTrue(encoded.contains("catalog.partial-lineup"))
        XCTAssertFalse(encoded.contains("http"))
        XCTAssertFalse(encoded.contains("Authorization"))
    }

    func testCompatibilityViewIsAReadOnlyCurrentStateProjection() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SiriusMac/Support/CompatibilitySupport.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("Task {"))
        XCTAssertFalse(source.contains("SiriusXMClient("))
        XCTAssertFalse(source.contains("ListeningSessionController("))
        XCTAssertFalse(source.contains("PlaybackCoordinator("))
    }

    func testFavoriteCurrentSongHasGlobalKeyboardShortcut() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SiriusMac/SiriusMacApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains(".keyboardShortcut(\"f\", modifiers: [.command, .option])"))
    }
}

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
            compatibility: CompatibilitySnapshot.signedOut.findings
        )

        let data = try SupportBundleFactory.encoded(bundle)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(
            Set(object.keys),
            Set(["schemaVersion", "product", "version", "build", "operatingSystem", "architecture", "compatibility"])
        )
        let compatibility = try XCTUnwrap(object["compatibility"] as? [[String: Any]])
        XCTAssertEqual(compatibility.count, CompatibilityArea.allCases.count)
        for finding in compatibility {
            XCTAssertEqual(Set(finding.keys), Set(["area", "classification"]))
        }
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

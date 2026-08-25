import XCTest
@testable import SiriusMac
import SiriusXMClient

@MainActor
final class CompactPlayerPresentationTests: XCTestCase {
    func testConfirmedPlaybackMapsOnlySemanticSlots() {
        let presentation = CompactPlayerPresentation.confirmed(
            channel: CompactPlayerPresentation.ChannelIdentity(number: 42, name: "The Spectrum"),
            artwork: .placeholder,
            primaryMetadata: "A very real song title",
            secondaryMetadata: "A very real artist",
            playback: .playing,
            isFavorite: true,
            queueAvailability: .both
        )

        XCTAssertEqual(presentation.channelIdentity?.displayText, "42 · The Spectrum")
        XCTAssertEqual(presentation.artwork, .placeholder)
        XCTAssertEqual(presentation.primaryMetadata, "A very real song title")
        XCTAssertEqual(presentation.secondaryMetadata, "A very real artist")
        XCTAssertEqual(presentation.status, .playing)
        XCTAssertTrue(presentation.isFavorite)
        XCTAssertEqual(presentation.transport, .init(previousEnabled: true, playPause: .pause, nextEnabled: true))
    }

    func testNativeStyleUsesApprovedRolesWithoutBehavior() {
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.contentSize, .init(width: 400, height: 288))
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.dominantHex, "#111111")
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.secondaryHex, "#262626")
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.accentHex, "#C6FF00")
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.destructiveHex, "#FF453A")
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.foregroundColorScheme, .dark)
        XCTAssertEqual(PlayerSemanticStyleRole.allCases, [.playerBackground, .metadataPanel, .accent, .destructive, .label, .body, .heading, .display])
    }

    func testFallbackStyleProvidesDarkSystemForegroundsForEveryCompactState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("SiriusMac/Player/CompactPlayerView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".environment(\\.colorScheme, contentColorScheme)"))
        XCTAssertTrue(source.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(source.contains(".background(Color(hex: style.dominantHex))"))
    }

    func testViewActionsStayOutsideThePresentationValue() {
        XCTAssertEqual(
            CompactPlayerAction.allCases,
            [.previous, .playPause, .next, .toggleFavorite, .showLibrary, .toggleAlwaysOnTop, .retryPlayback, .signInAgain, .refreshLibrary]
        )
        let storedValues = Array(Mirror(reflecting: CompactPlayerPresentation.empty()).children)

        XCTAssertEqual(
            storedValues.compactMap(\.label),
            [
                "backgroundRole", "channelIdentity", "artwork", "primaryMetadata",
                "secondaryMetadata", "status", "isFavorite", "transport", "emptyTitle",
                "emptyLibraryButtonTitle"
            ]
        )
        XCTAssertFalse(storedValues.contains { $0.value is CompactPlayerAction })
        XCTAssertFalse(storedValues.contains { String(reflecting: type(of: $0.value)).contains("->") })
    }

    func testEmptyPresentationHasNoFabricatedChannelOrMetadata() {
        let presentation = CompactPlayerPresentation.empty()

        XCTAssertEqual(presentation.emptyTitle, "Nothing Playing")
        XCTAssertEqual(presentation.emptyLibraryButtonTitle, "Open Library")
        XCTAssertNil(presentation.channelIdentity)
        XCTAssertNil(presentation.primaryMetadata)
        XCTAssertNil(presentation.secondaryMetadata)
    }

    func testPendingWithoutAConfirmedChannelShowsNativeProgressWithoutMetadata() {
        let presentation = CompactPlayerPresentation.project(
            channel: nil,
            metadata: unavailableMetadata(),
            primaryMetadata: nil,
            secondaryMetadata: nil,
            playback: .awaitingLiveContract,
            isFavorite: false,
            queueAvailability: .none
        )

        XCTAssertEqual(presentation.status, .pending)
        XCTAssertTrue(presentation.showsNativeProgress)
        XCTAssertNil(presentation.channelIdentity)
        XCTAssertNil(presentation.primaryMetadata)
    }

    func testFailuresExposeOnlyTheirApprovedRecoveryAction() {
        XCTAssertEqual(CompactRecoveryAction(failure: .authorizationUnavailable), .signInAgain)
        XCTAssertEqual(CompactRecoveryAction(failure: .entitlementUnavailable), .signInAgain)
        XCTAssertEqual(CompactRecoveryAction(failure: .catalogUnavailable), .refreshLibrary)
        XCTAssertEqual(CompactRecoveryAction(failure: .networkUnavailable), .tryAgain)
    }

    func testFailedReplacementTuneRetainsStationContentWithoutObsoleteTransportControls() {
        let confirmed = CompactPlayerPresentation.confirmed(
            channel: .init(number: 42, name: "The Spectrum"),
            artwork: .placeholder,
            primaryMetadata: "Current title",
            secondaryMetadata: "Current artist",
            playback: .playing,
            isFavorite: true,
            queueAvailability: .both
        )
        let failedReplacement = CompactPlayerPresentation.empty(
            status: .unavailable(.tryAgain)
        ).retainingConfirmedContent(from: confirmed)

        XCTAssertEqual(failedReplacement.channelIdentity, confirmed.channelIdentity)
        XCTAssertEqual(failedReplacement.status, .unavailable(.tryAgain))
        XCTAssertNil(failedReplacement.transport)
    }

    func testStoppedPlaybackRetainsStationContentWithoutInertTransportControls() {
        let confirmed = CompactPlayerPresentation.confirmed(
            channel: .init(number: 42, name: "The Spectrum"),
            artwork: .placeholder,
            primaryMetadata: "Current title",
            secondaryMetadata: "Current artist",
            playback: .playing,
            isFavorite: true,
            queueAvailability: .both
        )
        let stopped = CompactPlayerPresentation.empty(status: .stopped)
            .retainingConfirmedContent(from: confirmed)

        XCTAssertEqual(stopped.channelIdentity, confirmed.channelIdentity)
        XCTAssertEqual(stopped.status, .stopped)
        XCTAssertNil(stopped.transport)
    }

    func testMissingMetadataAndArtworkUseIndependentTruthfulFallbacks() {
        let presentation = CompactPlayerPresentation.project(
            channel: LiveChannel(id: LiveChannelID("fixture-channel"), name: "Fallback Channel", displayNumber: 7),
            metadata: unavailableMetadata(),
            primaryMetadata: "Current program unavailable",
            secondaryMetadata: "7 · Fallback Channel",
            playback: .paused,
            isFavorite: false,
            queueAvailability: .none
        )

        XCTAssertEqual(presentation.artwork, .placeholder)
        XCTAssertEqual(presentation.primaryMetadata, "Current program unavailable")
        XCTAssertEqual(presentation.secondaryMetadata, "7 · Fallback Channel")
        XCTAssertEqual(presentation.status, .paused)
    }

    func testLongMetadataKeepsCompleteSemanticValuesAndFixedLayoutMetrics() {
        let longTitle = "音楽と星空のためのライブ・ラジオ・セッション — a deliberately very long title"
        let presentation = CompactPlayerPresentation.confirmed(
            channel: .init(number: 42, name: "The Spectrum"),
            artwork: .placeholder,
            primaryMetadata: longTitle,
            secondaryMetadata: longTitle,
            playback: .playing,
            isFavorite: false,
            queueAvailability: .both
        )

        XCTAssertEqual(presentation.primaryMetadata, longTitle)
        XCTAssertEqual(presentation.secondaryMetadata, longTitle)
        XCTAssertEqual(CompactPlayerPresentation.metadataLineLimit, 2)
        XCTAssertEqual(CompactPlayerPresentation.transportControlSize, 32)
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.contentSize, .init(width: 400, height: 288))
    }

    func testSelectedAppearanceReferenceRoundTripsEveryClassification() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for classification in SkinClassification.allCases {
            let reference = SkinSelectionReference(
                identifier: try XCTUnwrap(SkinIdentifier(rawValue: "round-trip-\(classification.rawValue)")),
                classification: classification
            )
            XCTAssertEqual(
                try decoder.decode(SkinSelectionReference.self, from: encoder.encode(reference)),
                reference
            )
        }
    }

    func testNativeBundledAndImportedAppearancesUseOneSelectionPath() async throws {
        let bundled = try SkinManifestValidator.validate(
            manifestData(identifier: "bundled-fixture", displayName: "Bundled Fixture"),
            classification: .bundled
        )
        let imported = try SkinManifestValidator.validate(
            manifestData(identifier: "imported-fixture", displayName: "Imported Fixture"),
            classification: .imported
        )
        let controller = SkinAppearanceController(
            catalog: SkinAppearanceCatalog(appearances: [bundled, imported])
        )

        XCTAssertEqual(controller.availableAppearances.first?.reference, .native)
        for reference in [bundled.reference, imported.reference, .native] {
            await controller.select(reference)
            XCTAssertEqual(controller.selectedReference, reference)
            XCTAssertEqual(controller.selectedAppearance.reference.classification, reference.classification)
        }
    }

    func testSkinManifestCannotClaimWindowOrControlGeometry() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: manifestData(identifier: "geometry-fixture", displayName: "Geometry Fixture")
            ) as? [String: Any]
        )

        for (key, value) in [
            ("contentWidth", 400),
            ("contentHeight", 287),
            ("transportControlSize", 32),
            ("transportHitRegion", 31)
        ] {
            object[key] = value
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try SkinManifestValidator.validate(data)) { error in
                XCTAssertEqual(error as? SkinManifestValidationError, .unknownOrMissingKeys)
            }
            object.removeValue(forKey: key)
        }
    }

    private func manifestData(identifier: String, displayName: String) -> Data {
        Data(
            #"""
            {
              "schemaVersion": 1,
              "identifier": "\#(identifier)",
              "displayName": "\#(displayName)",
              "playerBackground": "#101010",
              "metadataPanel": "#202020",
              "accent": "#C6FF00",
              "destructive": "#FF453A",
              "foregroundScheme": "dark",
              "contentPadding": 16,
              "sectionSpacing": 8,
              "cornerRadius": 4,
              "backgroundAsset": null,
              "metadataPanelAsset": null
            }
            """#.utf8
        )
    }

    private func unavailableMetadata() -> LiveMetadataState {
        LiveMetadataState(
            channelID: LiveChannelID("fixture-metadata"),
            text: .unavailable,
            artwork: .unavailable,
            refreshedAt: nil
        )
    }
}

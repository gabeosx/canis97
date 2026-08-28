import XCTest
@testable import Canis97
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

    func testClosedSurfaceVocabularyMapsEveryValidatedAppearanceRole() throws {
        let appearance = try SkinManifestValidator.validate(
            manifestData(identifier: "surface-fixture", displayName: "Surface Fixture"),
            classification: .imported
        )

        XCTAssertEqual(
            CompactSkinSurface.allCases,
            [.canvas, .chromeHighlight, .displayGlow, .metadata, .status, .transport, .footer, .interactiveAccent, .criticalState]
        )

        for surface in CompactSkinSurface.allCases {
            let treatment = appearance.surfaceTreatment(for: surface)
            XCTAssertTrue(treatment.fillHex.hasPrefix("#"))
            XCTAssertTrue(treatment.strokeHex.hasPrefix("#"))
            XCTAssertTrue(treatment.tintHex.hasPrefix("#"))
            XCTAssertTrue((0 ... 1).contains(treatment.fillOpacity))
            XCTAssertTrue((0 ... 1).contains(treatment.strokeOpacity))
        }

        XCTAssertEqual(appearance.surfaceTreatment(for: .canvas).fillHex, "#101010")
        XCTAssertEqual(appearance.surfaceTreatment(for: .metadata).fillHex, "#202020")
        XCTAssertEqual(appearance.surfaceTreatment(for: .interactiveAccent).tintHex, "#C6FF00")
        XCTAssertEqual(appearance.surfaceTreatment(for: .criticalState).tintHex, "#FF453A")
        XCTAssertEqual(appearance.surfaceTreatment(for: .chromeHighlight).tintHex, "#C6FF00")
        XCTAssertEqual(appearance.surfaceTreatment(for: .displayGlow).fillHex, "#202020")
    }

    func testVersionOneAppearanceRemainsExactWhileVersionTwoProjectsOnlyDecorativeTreatments() throws {
        let versionOneData = manifestData(identifier: "version-one", displayName: "Version One")
        let versionOne = try SkinManifestValidator.validate(versionOneData)
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: versionOneData) as? [String: Any]
        )
        document["schemaVersion"] = 2
        document["chromeHighlight"] = "#D8FF59"
        document["displayGlow"] = "#315C48"
        let versionTwoData = try JSONSerialization.data(withJSONObject: document)
        let versionTwo = try SkinManifestValidator.validateVersion2(versionTwoData)

        XCTAssertEqual(versionOne.reference, versionTwo.reference)
        XCTAssertEqual(versionOne.displayName, versionTwo.displayName)
        XCTAssertEqual(versionOne.style, versionTwo.style)
        XCTAssertEqual(versionOne.cornerRadius, versionTwo.cornerRadius)
        XCTAssertEqual(versionTwo.surfaceTreatment(for: .chromeHighlight).tintHex, "#D8FF59")
        XCTAssertEqual(versionTwo.surfaceTreatment(for: .displayGlow).fillHex, "#315C48")
    }

    func testVersionTwoRejectsUnknownFieldsAndMissingOrInvalidDecorativeRoles() throws {
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: manifestData(identifier: "version-two-rejection", displayName: "Version Two Rejection")
            ) as? [String: Any]
        )
        document["schemaVersion"] = 2
        document["chromeHighlight"] = "#D8FF59"
        document["displayGlow"] = "#315C48"

        for mutation in ["menuAction", "accessibilityLabel", "contentWidth"] {
            document[mutation] = "forbidden"
            XCTAssertThrowsError(try SkinManifestValidator.validate(try JSONSerialization.data(withJSONObject: document)))
            document.removeValue(forKey: mutation)
        }
        document.removeValue(forKey: "displayGlow")
        XCTAssertThrowsError(try SkinManifestValidator.validate(try JSONSerialization.data(withJSONObject: document)))
        document["displayGlow"] = "not-a-color"
        XCTAssertThrowsError(try SkinManifestValidator.validate(try JSONSerialization.data(withJSONObject: document)))
    }

    func testUnusableDecorationFallsBackBeforeSurfaceTreatmentIsDerived() throws {
        let imported = ValidatedSkinAppearance(
            reference: SkinSelectionReference(
                identifier: try XCTUnwrap(SkinIdentifier(rawValue: "surface-render-failure")),
                classification: .imported
            ),
            displayName: "Surface Render Failure",
            style: CompactSkinStyle(
                contentSize: .init(width: 400, height: 288),
                dominantHex: "#001122",
                secondaryHex: "#113355",
                accentHex: "#66FFAA",
                destructiveHex: "#FF3355",
                foregroundColorScheme: .dark,
                padding: 16,
                sectionSpacing: 8
            ),
            cornerRadius: 8,
            backgroundAssetURL: URL(fileURLWithPath: "/managed/missing-surface.png"),
            metadataPanelAssetURL: nil
        )

        let rendered = imported.renderableAppearance { _ in false }

        XCTAssertEqual(rendered.surfaceTreatment(for: .canvas), ValidatedSkinAppearance.native.surfaceTreatment(for: .canvas))
        XCTAssertEqual(rendered.surfaceTreatment(for: .criticalState), ValidatedSkinAppearance.native.surfaceTreatment(for: .criticalState))
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
        XCTAssertTrue(source.contains("surfaceBackground(.canvas)"))
        XCTAssertTrue(source.contains("appOwnedDecorativeSurfaces"))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
    }

    func testViewActionsStayOutsideThePresentationValue() {
        XCTAssertEqual(
            CompactPlayerAction.allCases,
            [.previous, .playPause, .next, .toggleFavorite, .toggleSongFavorite, .showLibrary, .toggleAlwaysOnTop, .retryPlayback, .signInAgain, .refreshLibrary, .signOut]
        )
        let storedValues = Array(Mirror(reflecting: CompactPlayerPresentation.empty()).children)

        XCTAssertEqual(
            storedValues.compactMap(\.label),
            [
                "backgroundRole", "channelIdentity", "artwork", "primaryMetadata",
                "secondaryMetadata", "status", "isFavorite", "transport", "emptyTitle",
                "emptyBody", "emptyLibraryButtonTitle"
            ]
        )
        XCTAssertFalse(storedValues.contains { $0.value is CompactPlayerAction })
        XCTAssertFalse(storedValues.contains { String(reflecting: type(of: $0.value)).contains("->") })
    }

    func testEmptyPresentationHasNoFabricatedChannelOrMetadata() {
        let presentation = CompactPlayerPresentation.empty()

        XCTAssertEqual(presentation.emptyTitle, "Nothing Playing")
        XCTAssertEqual(presentation.emptyBody, "Choose a channel in the Library to start listening.")
        XCTAssertEqual(presentation.emptyLibraryButtonTitle, "Show Library")
        XCTAssertNil(presentation.channelIdentity)
        XCTAssertNil(presentation.primaryMetadata)
        XCTAssertNil(presentation.secondaryMetadata)
    }

    func testExpressiveStateContractKeepsExactCopyAndBoundedMotionAppOwned() throws {
        let source = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        let presentationSource = try repositorySource("SiriusMac/Player/CompactPlayerPresentation.swift")

        XCTAssertTrue(presentationSource.contains("Choose a channel in the Library to start listening."))
        XCTAssertTrue(source.contains("This appearance is unavailable. Native appearance has been restored."))
        XCTAssertTrue(source.contains("Use Native Appearance"))
        XCTAssertTrue(source.contains(".lineLimit(1)"))
        XCTAssertTrue(source.contains("BoundedMarqueeText("))
        XCTAssertTrue(source.contains(".fixedSize(horizontal: true, vertical: true)"))
        XCTAssertTrue(source.contains(".help(primary)"))
        XCTAssertTrue(source.contains(".help(secondary)"))
        XCTAssertTrue(source.contains(".accessibilityValue(primary)"))
        XCTAssertTrue(source.contains(".accessibilityValue(secondary)"))
        XCTAssertTrue(source.contains(".opacity"))
        XCTAssertTrue(source.contains("duration: 0.15"))
        XCTAssertTrue(source.contains("reduceMotion ? nil"))
        XCTAssertTrue(source.contains("CompactPlayerPresentation.focusClearance"))
    }

    func testOfflineReviewMatrixListsAllAppearancesAndCompactStates() throws {
        let source = try repositorySource("SiriusMac/Testing/UITestHarness.swift")

        for appearance in ["native", "legacySchema1", "signalGlow", "tapeDeck", "pixelDesk", "pocketDisc", "aquaVista"] {
            XCTAssertTrue(source.contains("case \(appearance)"))
        }
        for state in ["compactEmpty", "compactPopulated", "compactPending", "compactError", "compactLongText", "compactAppearanceFailure"] {
            XCTAssertTrue(source.contains("case \(state)"))
        }
        XCTAssertTrue(source.contains("OfflineReviewAppearanceFixture"))
        XCTAssertTrue(source.contains("SkinManifestValidator.validate"))
        XCTAssertTrue(source.contains("isStoredInMemoryOnly: true"))
        XCTAssertTrue(source.contains("private init?(environment:"))
        XCTAssertFalse(source.contains("try! ModelContainer"))

        let appSource = try repositorySource("SiriusMac/SiriusMacApp.swift")
        XCTAssertTrue(appSource.contains("if OfflineReviewLaunchMode.isOfflineReviewMode(environment: environment)"))
        XCTAssertTrue(appSource.contains("OfflineReviewUnavailableView()"))
        XCTAssertTrue(appSource.contains("sessionController = nil"))
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

    func testIdleWithoutAConfirmedChannelShowsEmptyStateWithoutProgress() {
        let presentation = CompactPlayerPresentation.project(
            channel: nil,
            metadata: unavailableMetadata(),
            primaryMetadata: nil,
            secondaryMetadata: nil,
            playback: .idle,
            isFavorite: false,
            queueAvailability: .none
        )

        XCTAssertNil(presentation.status)
        XCTAssertFalse(presentation.showsNativeProgress)
        XCTAssertEqual(presentation.emptyTitle, "Nothing Playing")
        XCTAssertEqual(presentation.emptyLibraryButtonTitle, "Show Library")
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

    func testChannelArtworkBacksUpUnavailableProgramArtwork() {
        let channelArtwork = ArtworkData(bytes: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: .png)
        let presentation = CompactPlayerPresentation.project(
            channel: LiveChannel(id: LiveChannelID("fixture-channel"), name: "Fallback Channel", displayNumber: 7),
            metadata: unavailableMetadata(),
            channelArtwork: channelArtwork,
            primaryMetadata: "Current program unavailable",
            secondaryMetadata: "7 · Fallback Channel",
            playback: .paused,
            isFavorite: false,
            queueAvailability: .none
        )

        XCTAssertEqual(presentation.artwork, .data(channelArtwork))
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
        XCTAssertEqual(CompactPlayerPresentation.metadataActionSize, 24)
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

    func testPixelDeskUsesTheSharedBundledSelectionIdentityAndFinitePolicy() throws {
        let pixelDesk = try bundledAppearance(named: "PixelDesk")
        let catalog = SkinAppearanceCatalog(appearances: [pixelDesk])

        XCTAssertEqual(pixelDesk.reference.identifier.rawValue, "pixel-desk")
        XCTAssertEqual(pixelDesk.reference.classification, .bundled)
        XCTAssertEqual(catalog.resolve(pixelDesk.reference), pixelDesk)
        XCTAssertEqual(pixelDesk.layoutPlan.layoutVariant, .desktopUtility)
        XCTAssertEqual(pixelDesk.layoutPlan.silhouette, .pixelNotched)
        XCTAssertEqual(pixelDesk.layoutPlan.contentSize, .init(width: 432, height: 304))
        XCTAssertEqual(ValidatedSkinAppearance.native.layoutPlan.contentSize, .init(width: 400, height: 288))
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
            ("metadataActionSize", 24),
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

    func testAppearanceManagementReceivesOnlyStableSemanticAuthority() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("SiriusMac/Skins/SkinManagementView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let reference: SkinSelectionReference"))
        XCTAssertTrue(source.contains("let classification: SkinClassification"))
        XCTAssertTrue(source.contains("appearanceController.select(reference)"))
        XCTAssertTrue(source.contains("skinImportCoordinator.importAndSelect(sourceURL)"))
        XCTAssertTrue(source.contains("SkinPackageCompatibilityFailure.unsupportedSchema"))
        XCTAssertFalse(source.contains("ListeningSessionController"))
        XCTAssertFalse(source.contains("AccessibilityAnnouncer"))
        XCTAssertFalse(source.contains("WindowLifecyclePolicy"))
        XCTAssertFalse(source.contains("SkinManifest"))
    }

    func testAppSettingsAndPlayerMenuShareTheAppearanceManagementSurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("SiriusMac/SiriusMacApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Settings {"))
        XCTAssertTrue(source.contains("SkinManagementView("))
        XCTAssertTrue(source.contains("Text(\"Manage Appearances…\")"))
        XCTAssertTrue(source.contains("SettingsLink"))
    }

    func testUnrenderableDecorationFallsBackToStaticNativeAppearance() throws {
        let imported = ValidatedSkinAppearance(
            reference: SkinSelectionReference(
                identifier: try XCTUnwrap(SkinIdentifier(rawValue: "imported-render-failure")),
                classification: .imported
            ),
            displayName: "Imported Render Failure",
            style: .fallback,
            cornerRadius: 8,
            backgroundAssetURL: URL(fileURLWithPath: "/managed/missing-background.png"),
            metadataPanelAssetURL: nil
        )

        let rendered = imported.renderableAppearance { _ in false }

        XCTAssertEqual(rendered, SkinAppearanceCatalog.nativeAppearance)
    }

    func testNativeBundledAndDecorationFreeImportedAppearancesKeepTheirValidatedValues() throws {
        let bundled = try SkinManifestValidator.validate(
            manifestData(identifier: "bundled-renderable", displayName: "Bundled Renderable"),
            classification: .bundled
        )
        let imported = try SkinManifestValidator.validate(
            manifestData(identifier: "imported-renderable", displayName: "Imported Renderable"),
            classification: .imported
        )

        for appearance in [ValidatedSkinAppearance.native, bundled, imported] {
            XCTAssertEqual(
                appearance.renderableAppearance { _ in false },
                appearance
            )
        }
    }

    func testPlayerRecoveryCommandIsDirectAndUnconditionallyEnabled() throws {
        let source = try repositorySource("SiriusMac/SiriusMacApp.swift")
        let commandStart = try XCTUnwrap(source.range(of: "Button(\"Use Native Appearance\")"))
        let commandTail = source[commandStart.lowerBound...]
        let commandBlock = String(commandTail.prefix(320))

        XCTAssertTrue(commandBlock.contains("appearanceController.restoreNativeAppearance()"))
        XCTAssertFalse(commandBlock.contains("catalog.resolve"))
        XCTAssertFalse(commandBlock.contains("selectedAppearance"))
        XCTAssertFalse(commandBlock.contains(".disabled"))
    }

    func testCompactAppearanceInputCannotChangeSemanticControlsOrGeometry() throws {
        let source = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        let manifestSource = try repositorySource("SiriusMac/Skins/SkinAppearance.swift")

        XCTAssertFalse(source.contains("switch appearance.reference.classification"))
        for surface in CompactSkinSurface.allCases {
            XCTAssertTrue(source.contains(".\(surface.rawValue)"))
        }
        XCTAssertTrue(source.contains("CompactPlayerPresentation.transportControlSize"))
        XCTAssertTrue(source.contains("CompactPlayerPresentation.metadataActionSize"))
        XCTAssertTrue(source.contains(".frame(width: style.contentSize.width, height: style.contentSize.height"))
        XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
        for forbiddenKey in [
            "accessibilityLabel", "accessibilityValue", "accessibilityHint",
            "accessibilitySortPriority", "actionName", "focusPriority",
            "reduceMotion", "contentWidth", "contentHeight", "transportControlSize", "metadataActionSize"
        ] {
            XCTAssertFalse(manifestSource.contains("\"\(forbiddenKey)\""))
        }
    }

    func testBundledAppearancesUseDistinctSharedNormalSurfaceTreatments() throws {
        let native = ValidatedSkinAppearance.native
        let signalGlow = try bundledAppearance(named: "SignalGlow")
        let tapeDeck = try bundledAppearance(named: "TapeDeck")
        let normalSurfaces = CompactSkinSurface.allCases.filter { $0 != .criticalState }

        for surface in normalSurfaces {
            XCTAssertNotEqual(signalGlow.surfaceTreatment(for: surface), native.surfaceTreatment(for: surface), "Signal Glow should differ from Native at \(surface)")
            XCTAssertNotEqual(tapeDeck.surfaceTreatment(for: surface), native.surfaceTreatment(for: surface), "Tape Deck should differ from Native at \(surface)")
            XCTAssertNotEqual(signalGlow.surfaceTreatment(for: surface), tapeDeck.surfaceTreatment(for: surface), "Bundled appearances should differ at \(surface)")
        }
        XCTAssertEqual(NativeCompactPlayerStyle.fallback.contentSize, .init(width: 400, height: 288))
        XCTAssertEqual(CompactPlayerPresentation.transportControlSize, 32)
        XCTAssertEqual(CompactPlayerPresentation.metadataActionSize, 24)
    }

    func testAppearanceFamilyKeepsOneActionAndAccessibilityContractForLongEmptyAndErrorContent() throws {
        let appearances = [
            ValidatedSkinAppearance.native,
            try bundledAppearance(named: "SignalGlow"),
            try bundledAppearance(named: "TapeDeck")
        ]
        let longMetadata = String(repeating: "Orbital signal / ", count: 18)
        let presentations = [
            CompactPlayerPresentation.confirmed(
                channel: .init(number: 97, name: "Canis"),
                artwork: .placeholder,
                primaryMetadata: longMetadata,
                secondaryMetadata: longMetadata,
                playback: .playing,
                isFavorite: false,
                queueAvailability: .both
            ),
            CompactPlayerPresentation.empty(),
            CompactPlayerPresentation.empty(status: .unavailable(.tryAgain))
        ]
        let source = try repositorySource("SiriusMac/Player/CompactPlayerView.swift")
        let expectedActions: [CompactPlayerAction] = [
            .previous, .playPause, .next, .toggleFavorite, .toggleSongFavorite, .showLibrary,
            .toggleAlwaysOnTop, .retryPlayback, .signInAgain, .refreshLibrary, .signOut
        ]

        XCTAssertEqual(CompactPlayerAction.allCases, expectedActions)
        XCTAssertFalse(source.contains("switch appearance.reference.classification"))
        for identifier in [
            "compact.favorite",
            "compact.song-favorite",
            "compact.status",
            "compact.show-library",
            "compact.sign-out"
        ] {
            XCTAssertTrue(
                source.contains(".accessibilityIdentifier(\"\(identifier)\")"),
                "\(identifier) must remain app-owned"
            )
        }
        for appearance in appearances {
            XCTAssertEqual(appearance.renderableAppearance { _ in false }, appearance)
            for presentation in presentations {
                XCTAssertFalse(Array(Mirror(reflecting: presentation).children).contains { $0.value is CompactPlayerAction })
            }
        }
    }

    private func repositorySource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func bundledAppearance(named name: String) throws -> ValidatedSkinAppearance {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("SiriusMac/Skins/Bundled")
            .appendingPathComponent(name)
            .appendingPathExtension("json")
        return try SkinManifestValidator.validate(
            Data(contentsOf: url),
            classification: .bundled
        )
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

import XCTest
@testable import Canis97

@MainActor
final class AccessibilityContractTests: XCTestCase {
    func testClosedConfirmedEventsPostOnceAndSuppressDuplicates() {
        let poster = AccessibilityAnnouncementPosterSpy()
        let announcer = AccessibilityAnnouncer(poster: poster)

        announcer.announce(.tuned(generation: 1))
        announcer.announce(.tuned(generation: 1))
        announcer.announce(.playing(generation: 2))
        announcer.announce(.playing(generation: 2))
        announcer.announce(.paused(generation: 3))

        XCTAssertEqual(poster.messages, ["Tuned to selected channel", "Playing", "Paused"])
    }

    func testFavoriteFailureAndFreshnessAnnouncementsStayClosedAndDeduplicated() {
        let poster = AccessibilityAnnouncementPosterSpy()
        let announcer = AccessibilityAnnouncer(poster: poster)

        announcer.announce(.favoriteAdded(generation: 1))
        announcer.announce(.favoriteRemoved(generation: 2))
        announcer.announce(.playbackFailed(generation: 3))
        announcer.announce(.metadataStale(generation: 4))
        announcer.announce(.metadataStale(generation: 4))
        announcer.announce(.metadataUnavailable(generation: 5))

        XCTAssertEqual(
            poster.messages,
            [
                "Added to Favorites",
                "Removed from Favorites",
                "Playback unavailable",
                "Current program is stale",
                "Current program unavailable",
            ]
        )
        XCTAssertTrue(poster.messages.allSatisfy { !$0.localizedCaseInsensitiveContains("token") })
        XCTAssertTrue(poster.messages.allSatisfy { !$0.localizedCaseInsensitiveContains("http") })
    }

    func testShutdownSuppressesRetainedAnnouncementObservation() {
        let poster = AccessibilityAnnouncementPosterSpy()
        let announcer = AccessibilityAnnouncer(poster: poster)

        announcer.shutdown()
        announcer.announce(.tuned(generation: 1))

        XCTAssertTrue(poster.messages.isEmpty)
    }

    func testAppearanceRecoveryAndManagementCopyStayOutsideAnnouncements() throws {
        let announcementSource = try repositorySource(
            "SiriusMac/Accessibility/AccessibilityAnnouncer.swift"
        )
        let managementSource = try repositorySource(
            "SiriusMac/Skins/SkinManagementView.swift"
        )
        let playerSource = try repositorySource(
            "SiriusMac/Player/CompactPlayerView.swift"
        )

        XCTAssertFalse(announcementSource.contains("Appearance"))
        XCTAssertFalse(announcementSource.contains("Skin"))
        XCTAssertFalse(managementSource.contains("AccessibilityAnnouncementEvent"))
        XCTAssertFalse(managementSource.contains(".announce("))
        XCTAssertFalse(playerSource.contains(".announce("))
    }

    func testAppearanceManagementUsesNativeFocusAndClosedErrorPresentation() throws {
        let source = try repositorySource("SiriusMac/Skins/SkinManagementView.swift")

        XCTAssertTrue(source.contains("@FocusState private var focusedReference"))
        XCTAssertTrue(source.contains("focusedReference = appearanceController.selectedReference"))
        XCTAssertTrue(source.contains("enum SkinManagementErrorPresentation"))
        XCTAssertTrue(source.contains("Button(\"Remove\", role: .destructive"))
        XCTAssertTrue(source.contains(".frame(minHeight: 32)"))
        XCTAssertFalse(source.contains("NSAlert"))
        XCTAssertFalse(source.contains("NSOpenPanel"))
    }

    func testProductOwnedPresentationKeepsAccessibilityAndRecoveryAppOwned() throws {
        let librarySource = try repositorySource("SiriusMac/Catalog/ListeningView.swift")
        let managementSource = try repositorySource("SiriusMac/Skins/SkinManagementView.swift")
        let appSource = try repositorySource("SiriusMac/SiriusMacApp.swift")

        XCTAssertTrue(librarySource.contains("ProductIdentity.displayName) library"))
        XCTAssertTrue(librarySource.contains("accessibilitySortPriority(30)"))
        XCTAssertTrue(librarySource.contains("accessibilitySortPriority(29)"))
        XCTAssertTrue(librarySource.contains("accessibilitySortPriority(27)"))
        XCTAssertTrue(managementSource.contains("ProductIdentity.skinPackageTypeIdentifier"))
        XCTAssertTrue(managementSource.contains("ProductIdentity.Legacy.skinPackageTypeIdentifier"))
        XCTAssertTrue(managementSource.contains("@FocusState private var focusedReference"))
        XCTAssertTrue(appSource.contains("Button(\"Use Native Appearance\")"))
        XCTAssertTrue(appSource.contains("CommandMenu(\"Player\")"))
        XCTAssertFalse(managementSource.contains("accessibilityLabel(appearance.displayName)"))
    }

    func testSkinImportKeepsBothExtensionsBehindTheClosedImporter() throws {
        let importerSource = try repositorySource("SiriusMac/Skins/SkinPackageImporter.swift")

        XCTAssertTrue(importerSource.contains("ProductIdentity.skinPackageExtension"))
        XCTAssertTrue(importerSource.contains("ProductIdentity.Legacy.skinPackageExtension"))
        XCTAssertTrue(importerSource.contains("validateManagedPackage"))
        XCTAssertFalse(importerSource.contains("JavaScript"))
        XCTAssertFalse(importerSource.contains("WebKit"))
    }

    private func repositorySource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}

@MainActor
private final class AccessibilityAnnouncementPosterSpy: AccessibilityAnnouncementPosting {
    private(set) var messages: [String] = []

    func postAnnouncement(_ message: String) {
        messages.append(message)
    }
}

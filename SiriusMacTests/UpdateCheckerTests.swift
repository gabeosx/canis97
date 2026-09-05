import XCTest
@testable import Canis97

final class StableSemanticVersionTests: XCTestCase {
    func testAcceptsStableCanonicalVersionsAndOptionalTagPrefix() throws {
        XCTAssertEqual(try XCTUnwrap(StableSemanticVersion("0.1.0")).description, "0.1.0")
        XCTAssertEqual(try XCTUnwrap(StableSemanticVersion("v12.34.56")).description, "12.34.56")
    }

    func testRejectsPrereleaseMetadataAndNoncanonicalNumbers() {
        XCTAssertNil(StableSemanticVersion("1.0.0-beta.1"))
        XCTAssertNil(StableSemanticVersion("1.0.0+42"))
        XCTAssertNil(StableSemanticVersion("01.0.0"))
        XCTAssertNil(StableSemanticVersion("1.0"))
    }

    func testComparesNumerically() throws {
        XCTAssertLessThan(
            try XCTUnwrap(StableSemanticVersion("1.9.9")),
            try XCTUnwrap(StableSemanticVersion("1.10.0"))
        )
    }

    func testRepositoryAcceptsOnlyOneSafeOwnerAndNamePair() throws {
        XCTAssertEqual(try XCTUnwrap(GitHubRepository("open-source/canis97")).value, "open-source/canis97")
        XCTAssertNil(GitHubRepository("open-source/canis97/releases"))
        XCTAssertNil(GitHubRepository("https://github.com/open-source/canis97"))
        XCTAssertNil(GitHubRepository("owner/repo?redirect=example.com"))
        XCTAssertNil(GitHubRepository("../repo"))
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UpdateCheckerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testManualCheckOffersNewerStableRelease() async throws {
        let releaseURL = try XCTUnwrap(URL(string: "https://github.com/example/canis97/releases/tag/v0.2.0"))
        let checker = UpdateChecker(
            configuration: try configuration(version: "0.1.0"),
            client: FixedReleaseClient(.success(GitHubReleaseInfo(
                version: try XCTUnwrap(StableSemanticVersion("0.2.0")),
                pageURL: releaseURL
            ))),
            defaults: defaults
        )

        await checker.check(manual: true)

        XCTAssertEqual(checker.alert?.releaseURL, releaseURL)
        XCTAssertEqual(checker.alert?.title, "Canis97 0.2.0 Is Available")
        XCTAssertFalse(checker.isChecking)
    }

    func testManualCheckReportsCurrentVersion() async throws {
        let checker = UpdateChecker(
            configuration: try configuration(version: "1.0.0"),
            client: FixedReleaseClient(.success(GitHubReleaseInfo(
                version: try XCTUnwrap(StableSemanticVersion("1.0.0")),
                pageURL: try XCTUnwrap(URL(string: "https://github.com/example/canis97/releases/tag/v1.0.0"))
            ))),
            defaults: defaults
        )

        await checker.check(manual: true)

        XCTAssertEqual(checker.alert?.title, "Canis97 Is Up to Date")
    }

    func testAutomaticCheckIsRateLimitedAndSilentWhenCurrent() async throws {
        let client = CountingReleaseClient(release: GitHubReleaseInfo(
            version: try XCTUnwrap(StableSemanticVersion("1.0.0")),
            pageURL: try XCTUnwrap(URL(string: "https://github.com/example/canis97/releases/tag/v1.0.0"))
        ))
        let checker = UpdateChecker(
            configuration: try configuration(version: "1.0.0"),
            client: client,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 100_000) }
        )

        await checker.checkAutomaticallyIfNeeded()
        await checker.checkAutomaticallyIfNeeded()

        let fetchCount = await client.fetchCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNil(checker.alert)
    }

    func testMalformedLocalConfigurationFailsClosedWithoutNetwork() async {
        let client = CountingReleaseClient(release: nil)
        let checker = UpdateChecker(
            configuration: UpdateCheckConfiguration(repository: nil, currentVersion: nil),
            client: client,
            defaults: defaults
        )

        await checker.checkAutomaticallyIfNeeded()
        let fetchCount = await client.fetchCount
        XCTAssertEqual(fetchCount, 0)

        await checker.check(manual: true)
        XCTAssertEqual(checker.alert, .unavailable)
    }

    func testDownloadActionUsesTheMatchingDiskImageAndKeepsInstallInstructions() throws {
        let repository = try XCTUnwrap(GitHubRepository("gabeosx/canis97"))
        let url = "https://github.com/gabeosx/canis97/releases/download/v0.2.0/Canis97-0.2.0-arm64.dmg"
        let release = try GitHubReleaseClient.decodeLatestRelease(releaseData(downloadURL: url), repository: repository)
        let alert = SoftwareUpdateAlert.available(current: try XCTUnwrap(StableSemanticVersion("0.1.4")), release: release)
        XCTAssertEqual(alert.updateURL?.absoluteString, url)
        XCTAssertEqual(alert.actionTitle, "Download Update")
        XCTAssertFalse(alert.message.contains("GitHub"))
    }

    func testUnexpectedDownloadDestinationsUseFriendlyInstallationPage() throws {
        let repository = try XCTUnwrap(GitHubRepository("gabeosx/canis97"))
        for url in [
            "https://example.com/Canis97-0.2.0-arm64.dmg",
            "https://github.com/other/repository/releases/download/v0.2.0/Canis97-0.2.0-arm64.dmg",
            "https://github.com/gabeosx/canis97/releases/download/v0.1.4/Canis97-0.1.4-arm64.dmg",
            "https://github.com/gabeosx/canis97/releases/download/v0.2.0/Canis97-0.2.0-arm64.dmg?redirect=evil",
            "file:///Applications/Canis97.app"
        ] {
            let release = try GitHubReleaseClient.decodeLatestRelease(releaseData(downloadURL: url), repository: repository)
            XCTAssertNil(release.downloadURL)
            let alert = SoftwareUpdateAlert.available(current: try XCTUnwrap(StableSemanticVersion("0.1.4")), release: release)
            XCTAssertEqual(alert.updateURL?.absoluteString, "https://canis97.com/#install")
            XCTAssertEqual(alert.actionTitle, "Get the Update")
        }
    }

    func testReleasePageMustMatchTheAdvertisedVersionExactly() throws {
        let repository = try XCTUnwrap(GitHubRepository("gabeosx/canis97"))
        let data = releaseData(downloadURL: "https://example.com", pageURL: "https://github.com/gabeosx/canis97/releases/tag/v0.1.4")
        XCTAssertThrowsError(try GitHubReleaseClient.decodeLatestRelease(data, repository: repository))
    }

    private func releaseData(downloadURL: String, pageURL: String = "https://github.com/gabeosx/canis97/releases/tag/v0.2.0") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.2.0", "html_url": pageURL, "draft": false, "prerelease": false,
            "assets": [["name": "Canis97-0.2.0-arm64.dmg", "browser_download_url": downloadURL]]
        ])
    }

    private func configuration(version: String) throws -> UpdateCheckConfiguration {
        UpdateCheckConfiguration(
            repository: try XCTUnwrap(GitHubRepository("example/canis97")),
            currentVersion: try XCTUnwrap(StableSemanticVersion(version))
        )
    }
}

private struct FixedReleaseClient: GitHubReleaseFetching {
    let result: Result<GitHubReleaseInfo, FixedReleaseError>

    init(_ result: Result<GitHubReleaseInfo, FixedReleaseError>) {
        self.result = result
    }

    func latestStableRelease(in repository: GitHubRepository) async throws -> GitHubReleaseInfo {
        try result.get()
    }
}

private enum FixedReleaseError: Error {
    case failed
}

private actor CountingReleaseClient: GitHubReleaseFetching {
    private(set) var fetchCount = 0
    private let release: GitHubReleaseInfo?

    init(release: GitHubReleaseInfo?) {
        self.release = release
    }

    func latestStableRelease(in repository: GitHubRepository) async throws -> GitHubReleaseInfo {
        fetchCount += 1
        guard let release else { throw FixedReleaseError.failed }
        return release
    }
}

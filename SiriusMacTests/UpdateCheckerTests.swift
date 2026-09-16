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

    func testReleaseValidationRejectsNoncanonicalAndUnsafePayloads() throws {
        let repository = try XCTUnwrap(GitHubRepository("example/canis97"))
        let valid = Data(#"{"tag_name":"v1.2.3","html_url":"https://github.com/example/canis97/releases/tag/v1.2.3","draft":false,"prerelease":false}"#.utf8)
        let unsafePayloads = [
            Data(#"{"tag_name":"v1.2.3-beta.1","html_url":"https://github.com/example/canis97/releases/tag/v1.2.3-beta.1","draft":false,"prerelease":false}"#.utf8),
            Data(#"{"tag_name":"v1.2.3","html_url":"http://github.com/example/canis97/releases/tag/v1.2.3","draft":false,"prerelease":false}"#.utf8),
            Data(#"{"tag_name":"v1.2.3","html_url":"https://github.com/example/canis97/releases/redirect","draft":false,"prerelease":false}"#.utf8),
            Data(#"{"tag_name":"v1.2.3","html_url":"https://github.com/other/canis97/releases/tag/v1.2.3","draft":false,"prerelease":false}"#.utf8),
            Data(repeating: 0, count: 1_048_577),
        ]

        XCTAssertEqual(
            try GitHubReleaseClient.decodeLatestStableRelease(valid, statusCode: 200, repository: repository).version.description,
            "1.2.3"
        )
        for payload in unsafePayloads {
            XCTAssertThrowsError(
                try GitHubReleaseClient.decodeLatestStableRelease(payload, statusCode: 200, repository: repository)
            )
        }
    }

    func testAutomaticManualOverlapSharesFetchAndPublishesManualCurrentState() async throws {
        let client = GatedReleaseClient(release: GitHubReleaseInfo(
            version: try XCTUnwrap(StableSemanticVersion("1.0.0")),
            pageURL: try XCTUnwrap(URL(string: "https://github.com/example/canis97/releases/tag/v1.0.0"))
        ))
        let checker = UpdateChecker(
            configuration: try configuration(version: "1.0.0"),
            client: client,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 100_000) }
        )

        let automatic = Task { await checker.checkAutomaticallyIfNeeded() }
        await client.waitUntilFetchStarts()
        let manual = Task { await checker.check(manual: true) }
        await client.completeFetch()
        await automatic.value
        await manual.value

        let fetchCount = await client.count()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(checker.alert?.title, "Canis97 Is Up to Date")
        XCTAssertFalse(checker.isChecking)
    }

    func testAutomaticCheckIsEligibleAtTheExactRateLimitBoundary() async throws {
        let client = CountingReleaseClient(release: GitHubReleaseInfo(
            version: try XCTUnwrap(StableSemanticVersion("1.0.0")),
            pageURL: try XCTUnwrap(URL(string: "https://github.com/example/canis97/releases/tag/v1.0.0"))
        ))
        let checker = UpdateChecker(
            configuration: try configuration(version: "1.0.0"),
            client: client,
            defaults: defaults,
            automaticCheckInterval: 24 * 60 * 60,
            now: { Date(timeIntervalSince1970: 86_400) }
        )
        defaults.set(Date(timeIntervalSince1970: 0), forKey: "com.canis97.player.update-check.last-attempt.v1")

        await checker.checkAutomaticallyIfNeeded()
        let fetchCount = await client.count()
        XCTAssertEqual(fetchCount, 1)
    }

    func testAvailableAlertIncludesTheExactHomebrewUpgradeCommand() throws {
        let current = try XCTUnwrap(StableSemanticVersion("0.1.0"))
        let release = GitHubReleaseInfo(
            version: try XCTUnwrap(StableSemanticVersion("0.2.0")),
            pageURL: try XCTUnwrap(URL(string: "https://github.com/example/canis97/releases/tag/v0.2.0"))
        )

        XCTAssertTrue(
            SoftwareUpdateAlert.available(current: current, release: release)
                .message.contains("brew upgrade --cask canis97")
        )
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

    func count() -> Int { fetchCount }
}

private actor GatedReleaseClient: GitHubReleaseFetching {
    private(set) var fetchCount = 0
    private let release: GitHubReleaseInfo
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?

    init(release: GitHubReleaseInfo) {
        self.release = release
    }

    func latestStableRelease(in repository: GitHubRepository) async throws -> GitHubReleaseInfo {
        fetchCount += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { completion = $0 }
        return release
    }

    func waitUntilFetchStarts() async {
        guard fetchCount == 0 else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func completeFetch() {
        completion?.resume()
        completion = nil
    }

    func count() -> Int { fetchCount }
}

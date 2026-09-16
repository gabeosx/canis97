import Foundation

@main
@MainActor
struct UpdateCheckerOfflineTests {
    static func main() async throws {
        try await run("stable release validation stays canonical and repository-bound", testStableReleaseValidation)
        try await run("manual overlap shares one fetch and publishes one current result", testManualOverlap)
        try await run("automatic rate limit allows the exact 24-hour boundary", testExactRateLimitBoundary)
        try await run("available guidance includes the Homebrew command", testHomebrewGuidance)
    }

    private static func testStableReleaseValidation() async throws {
        let repository = try required(GitHubRepository("example/canis97"))
        let valid = Data(#"{"tag_name":"v1.2.3","html_url":"https://github.com/example/canis97/releases/tag/v1.2.3","draft":false,"prerelease":false}"#.utf8)
        _ = try GitHubReleaseClient.decodeLatestStableRelease(valid, statusCode: 200, repository: repository)

        let invalid = Data(#"{"tag_name":"v1.2.3-beta.1","html_url":"https://github.com/example/canis97/releases/tag/v1.2.3-beta.1","draft":false,"prerelease":false}"#.utf8)
        do {
            _ = try GitHubReleaseClient.decodeLatestStableRelease(invalid, statusCode: 200, repository: repository)
            throw Failure("prerelease payload was accepted")
        } catch is UpdateCheckError {}
    }

    private static func testManualOverlap() async throws {
        let client = GatedReleaseClient(release: try release("1.0.0"))
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let checker = UpdateChecker(
            configuration: try configuration("1.0.0"),
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
        try expect(fetchCount == 1, "overlap started more than one fetch")
        try expect(checker.alert?.title == "Canis97 Is Up to Date", "manual caller did not receive current result")
    }

    private static func testExactRateLimitBoundary() async throws {
        let client = CountingReleaseClient(release: try release("1.0.0"))
        let defaults = try defaults()
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set(Date(timeIntervalSince1970: 0), forKey: lastAttemptKey)
        let checker = UpdateChecker(
            configuration: try configuration("1.0.0"),
            client: client,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 86_400) }
        )

        await checker.checkAutomaticallyIfNeeded()
        let fetchCount = await client.count()
        try expect(fetchCount == 1, "exact 24-hour boundary was not eligible")
    }

    private static func testHomebrewGuidance() async throws {
        let alert = SoftwareUpdateAlert.available(current: try version("0.1.0"), release: try release("0.2.0"))
        try expect(alert.message.contains("brew upgrade --cask canis97"), "Homebrew command is absent")
    }

    private static let defaultsName = "UpdateCheckerOfflineTests"
    private static let lastAttemptKey = "com.canis97.player.update-check.last-attempt.v1"

    private static func configuration(_ currentVersion: String) throws -> UpdateCheckConfiguration {
        UpdateCheckConfiguration(repository: try required(GitHubRepository("example/canis97")), currentVersion: try version(currentVersion))
    }

    private static func release(_ value: String) throws -> GitHubReleaseInfo {
        GitHubReleaseInfo(
            version: try version(value),
            pageURL: try required(URL(string: "https://github.com/example/canis97/releases/tag/v\(value)"))
        )
    }

    private static func version(_ value: String) throws -> StableSemanticVersion {
        try required(StableSemanticVersion(value))
    }

    private static func defaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: defaultsName) else { throw Failure("could not create defaults suite") }
        defaults.removePersistentDomain(forName: defaultsName)
        return defaults
    }

    private static func run(_ name: String, _ test: () async throws -> Void) async throws {
        try await test()
        print("PASS: \(name)")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message) }
    }

    private static func required<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure("required fixture was invalid") }
        return value
    }
}

private actor CountingReleaseClient: GitHubReleaseFetching {
    private(set) var fetchCount = 0
    private let release: GitHubReleaseInfo

    init(release: GitHubReleaseInfo) {
        self.release = release
    }

    func latestStableRelease(in repository: GitHubRepository) async throws -> GitHubReleaseInfo {
        fetchCount += 1
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

private struct Failure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

import AppKit
import Foundation
import Observation
import SwiftUI

struct GitHubReleaseInfo: Equatable, Sendable {
    let version: StableSemanticVersion
    let pageURL: URL
}

protocol GitHubReleaseFetching: Sendable {
    func latestStableRelease(in repository: GitHubRepository) async throws -> GitHubReleaseInfo
}

struct GitHubReleaseClient: GitHubReleaseFetching, Sendable {
    private let session: URLSession

    init(session: URLSession = GitHubReleaseClient.makeSession()) {
        self.session = session
    }

    func latestStableRelease(in repository: GitHubRepository) async throws -> GitHubReleaseInfo {
        var request = URLRequest(url: repository.latestReleaseAPIURL)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Canis97-Update-Checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count <= 1_048_576
        else { throw UpdateCheckError.invalidResponse }

        let payload: LatestReleasePayload
        do {
            payload = try JSONDecoder().decode(LatestReleasePayload.self, from: data)
        } catch {
            throw UpdateCheckError.invalidResponse
        }

        guard !payload.draft,
              !payload.prerelease,
              let version = StableSemanticVersion(payload.tagName),
              let pageURL = URL(string: payload.htmlURL),
              Self.isExpectedReleaseURL(pageURL, repository: repository)
        else { throw UpdateCheckError.invalidRelease }

        return GitHubReleaseInfo(version: version, pageURL: pageURL)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }

    private static func isExpectedReleaseURL(_ url: URL, repository: GitHubRepository) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/\(repository.owner)/\(repository.name)/releases/")
    }
}

private struct LatestReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

enum UpdateCheckError: Error {
    case invalidResponse
    case invalidRelease
}

struct UpdateCheckConfiguration: Sendable {
    let repository: GitHubRepository?
    let currentVersion: StableSemanticVersion?

    static func bundled(_ bundle: Bundle = .main) -> Self {
        let repositoryValue = bundle.object(forInfoDictionaryKey: "Canis97GitHubRepository") as? String ?? ""
        let versionValue = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return Self(
            repository: GitHubRepository(repositoryValue),
            currentVersion: StableSemanticVersion(versionValue)
        )
    }
}

struct SoftwareUpdateAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let releaseURL: URL?

    static func available(current: StableSemanticVersion, release: GitHubReleaseInfo) -> Self {
        Self(
            id: "available-\(release.version)",
            title: "Canis97 \(release.version) Is Available",
            message: "You are using \(current). Open GitHub Releases to review and download the update, or update with Homebrew.",
            releaseURL: release.pageURL
        )
    }

    static func upToDate(current: StableSemanticVersion) -> Self {
        Self(
            id: "up-to-date-\(current)",
            title: "Canis97 Is Up to Date",
            message: "Version \(current) is the latest stable release.",
            releaseURL: nil
        )
    }

    static let unavailable = Self(
        id: "unavailable",
        title: "Unable to Check for Updates",
        message: "This build does not have a valid GitHub release source or version.",
        releaseURL: nil
    )

    static let failed = Self(
        id: "failed",
        title: "Unable to Check for Updates",
        message: "Canis97 could not reach a valid GitHub release. Try again later.",
        releaseURL: nil
    )
}

@MainActor
@Observable
final class UpdateChecker {
    private(set) var isChecking = false
    var alert: SoftwareUpdateAlert?

    private let configuration: UpdateCheckConfiguration
    private let client: any GitHubReleaseFetching
    private let defaults: UserDefaults
    private let now: @MainActor @Sendable () -> Date
    private let automaticCheckInterval: TimeInterval
    private let lastAttemptKey = "com.canis97.player.update-check.last-attempt.v1"

    init(
        configuration: UpdateCheckConfiguration = .bundled(),
        client: any GitHubReleaseFetching = GitHubReleaseClient(),
        defaults: UserDefaults = .standard,
        automaticCheckInterval: TimeInterval = 24 * 60 * 60,
        now: @escaping @MainActor @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.client = client
        self.defaults = defaults
        self.automaticCheckInterval = automaticCheckInterval
        self.now = now
    }

    func checkAutomaticallyIfNeeded() async {
        guard !OfflineReviewLaunchMode.isOfflineReviewRequested() else { return }
        guard configuration.repository != nil,
              configuration.currentVersion != nil,
              !isChecking,
              shouldPerformAutomaticCheck
        else { return }
        await check(manual: false)
    }

    func check(manual: Bool) async {
        guard !OfflineReviewLaunchMode.isOfflineReviewRequested() else { return }
        guard !isChecking else { return }
        guard let repository = configuration.repository,
              let currentVersion = configuration.currentVersion
        else {
            if manual { alert = .unavailable }
            return
        }

        isChecking = true
        defer { isChecking = false }
        defaults.set(now(), forKey: lastAttemptKey)

        do {
            let release = try await client.latestStableRelease(in: repository)
            if currentVersion < release.version {
                alert = .available(current: currentVersion, release: release)
            } else if manual {
                alert = .upToDate(current: currentVersion)
            }
        } catch {
            if manual { alert = .failed }
        }
    }

    private var shouldPerformAutomaticCheck: Bool {
        guard let lastAttempt = defaults.object(forKey: lastAttemptKey) as? Date else { return true }
        return now().timeIntervalSince(lastAttempt) >= automaticCheckInterval
    }
}

private struct SoftwareUpdatePresentationModifier: ViewModifier {
    @Bindable var checker: UpdateChecker

    func body(content: Content) -> some View {
        content
            .task { await checker.checkAutomaticallyIfNeeded() }
            .alert(item: $checker.alert) { alert in
                if let releaseURL = alert.releaseURL {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        primaryButton: .default(Text("View Release")) {
                            NSWorkspace.shared.open(releaseURL)
                        },
                        secondaryButton: .cancel(Text("Later"))
                    )
                } else {
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
    }
}

extension View {
    func softwareUpdatePresentation(checker: UpdateChecker) -> some View {
        modifier(SoftwareUpdatePresentationModifier(checker: checker))
    }
}

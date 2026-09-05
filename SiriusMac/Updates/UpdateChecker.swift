import AppKit
import Foundation
import Observation
import SwiftUI

struct GitHubReleaseInfo: Equatable, Sendable {
    let version: StableSemanticVersion
    let pageURL: URL
    let downloadURL: URL?

    init(version: StableSemanticVersion, pageURL: URL, downloadURL: URL? = nil) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
    }
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

        return try Self.decodeLatestRelease(data, repository: repository)
    }

    static func decodeLatestRelease(_ data: Data, repository: GitHubRepository) throws -> GitHubReleaseInfo {
        guard data.count <= 1_048_576 else { throw UpdateCheckError.invalidResponse }
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
              [version.description, "v\(version)"].contains(payload.tagName),
              pageURL.absoluteString == "https://github.com/\(repository.value)/releases/tag/\(payload.tagName)"
        else { throw UpdateCheckError.invalidRelease }

        let filename = "Canis97-\(version)-arm64.dmg"
        let expectedDownload = "https://github.com/\(repository.value)/releases/download/\(payload.tagName)/\(filename)"
        let downloadURL = payload.assets?.first {
            $0.name == filename && $0.browserDownloadURL == expectedDownload
        }.flatMap { URL(string: $0.browserDownloadURL) }
        return GitHubReleaseInfo(version: version, pageURL: pageURL, downloadURL: downloadURL)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }
}

private struct LatestReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAsset]?

    struct ReleaseAsset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
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
    var downloadURL: URL? = nil

    var updateURL: URL? {
        guard releaseURL != nil else { return nil }
        return downloadURL ?? URL(string: "https://canis97.com/#install")!
    }

    var actionTitle: String { downloadURL == nil ? "Get the Update" : "Download Update" }

    static func available(current: StableSemanticVersion, release: GitHubReleaseInfo) -> Self {
        Self(
            id: "available-\(release.version)",
            title: "Canis97 \(release.version) Is Available",
            message: "You are using Canis97 \(current). Your favorites and settings will be kept when you update.",
            releaseURL: release.pageURL,
            downloadURL: release.downloadURL
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

/// Keep update controls outside the compact player's borderless, floating
/// window and its custom drag/hit-testing behavior.
struct SoftwareUpdateScene: Scene {
    let checker: UpdateChecker
    var openURL: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }

    var body: some Scene {
        Window("Software Update", id: SoftwareUpdateView.sceneID) {
            SoftwareUpdateView(checker: checker, openURL: openURL)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}

struct SoftwareUpdateView: View {
    static let sceneID = "software-update"
    @Bindable var checker: UpdateChecker
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var browserStatus: String?
    @FocusState private var receivesKeyboardCommands: Bool
    var openURL: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let alert = checker.alert {
                Label(alert.title, systemImage: alert.updateURL == nil ? "info.circle" : "arrow.down.app")
                    .font(.title2.bold())
                Text(alert.message)
                    .foregroundStyle(.secondary)
                if let updateURL = alert.updateURL {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Download the update in your browser.")
                        Text("2. Quit Canis97 when the download finishes.")
                        Text("3. Open the downloaded disk image and drag Canis97 into Applications. Choose Replace if asked.")
                        Text("4. Open Canis97 again from Applications.")
                    }
                    DisclosureGroup("Installed with Homebrew?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quit Canis97, then run this in Terminal instead:")
                            Text("brew upgrade --cask gabeosx/homebrew-tap/canis97")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }.padding(.top, 8)
                    }
                    if let browserStatus {
                        Text(browserStatus).font(.callout).foregroundStyle(.secondary)
                    }
                    HStack {
                        if let releaseURL = alert.releaseURL {
                            Link("What’s New", destination: releaseURL)
                        }
                        Spacer()
                        Button("Not Now", action: close).keyboardShortcut(.cancelAction)
                        Button(alert.actionTitle) {
                            browserStatus = openURL(updateURL)
                                ? "Opened in your browser. Follow the steps above to finish updating."
                                : "Your browser could not be opened. Visit canis97.com to download the update."
                        }.keyboardShortcut(.defaultAction)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("OK", action: close).keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                Label("Software Update", systemImage: "arrow.down.app").font(.title2.bold())
                Text("Check for the latest version of Canis97.").foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Close", action: close).keyboardShortcut(.cancelAction)
                    Button(checker.isChecking ? "Checking…" : "Check for Updates") {
                        Task { await checker.check(manual: true) }
                    }
                    .disabled(checker.isChecking)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 470, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .focusable()
        .focusEffectDisabled()
        .focused($receivesKeyboardCommands)
        .onExitCommand(perform: close)
        .onAppear {
            browserStatus = nil
            receivesKeyboardCommands = true
        }
        .onChange(of: checker.alert) { browserStatus = nil }
        .onDisappear {
            browserStatus = nil
            checker.alert = nil
        }
    }

    private func close() {
        browserStatus = nil
        checker.alert = nil
        dismissWindow(id: Self.sceneID)
    }
}

private struct SoftwareUpdatePresentationModifier: ViewModifier {
    @Bindable var checker: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .task { await checker.checkAutomaticallyIfNeeded() }
            .onChange(of: checker.alert, initial: true) {
                if checker.alert != nil { openWindow(id: SoftwareUpdateView.sceneID) }
            }
    }
}

extension View {
    func softwareUpdatePresentation(checker: UpdateChecker) -> some View {
        modifier(SoftwareUpdatePresentationModifier(checker: checker))
    }
}

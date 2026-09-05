// Production-code checks run without XCTest, an app host, or network access.
import Foundation
func requireEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b) }
func requireFalse(_ a: Bool) { precondition(!a) }
func requireNil<T>(_ a: T?) { precondition(a == nil) }
func requireValue<T>(_ a: T?) throws -> T { guard let a else { throw ProbeError.invalid }; return a }
func requireRejection<T>(_ value: @autoclosure () throws -> T) { do { _ = try value(); preconditionFailure("Expected rejection") } catch {} }
enum ProbeError: Error { case invalid }
enum OfflineReviewLaunchMode { static func isOfflineReviewRequested() -> Bool { false } }
@main @MainActor struct UpdateContractProbe {
    static func main() throws {
        let p = Self()
        try p.testDownloadActionUsesTheMatchingDiskImageAndKeepsInstallInstructions()
        try p.testUnexpectedDownloadDestinationsUseFriendlyInstallationPage()
        try p.testReleasePageMustMatchTheAdvertisedVersionExactly()
        print("PASS: direct download, safe fallback, and exact release identity")
    }
    func testDownloadActionUsesTheMatchingDiskImageAndKeepsInstallInstructions() throws {
        let repository = try requireValue(GitHubRepository("gabeosx/canis97"))
        let url = "https://github.com/gabeosx/canis97/releases/download/v0.2.0/Canis97-0.2.0-arm64.dmg"
        let release = try GitHubReleaseClient.decodeLatestRelease(releaseData(downloadURL: url), repository: repository)
        let alert = SoftwareUpdateAlert.available(current: try requireValue(StableSemanticVersion("0.1.4")), release: release)
        requireEqual(alert.updateURL?.absoluteString, url)
        requireEqual(alert.actionTitle, "Download Update")
        requireFalse(alert.message.contains("GitHub"))
    }

    func testUnexpectedDownloadDestinationsUseFriendlyInstallationPage() throws {
        let repository = try requireValue(GitHubRepository("gabeosx/canis97"))
        for url in [
            "https://example.com/Canis97-0.2.0-arm64.dmg",
            "https://github.com/other/repository/releases/download/v0.2.0/Canis97-0.2.0-arm64.dmg",
            "https://github.com/gabeosx/canis97/releases/download/v0.1.4/Canis97-0.1.4-arm64.dmg",
            "https://github.com/gabeosx/canis97/releases/download/v0.2.0/Canis97-0.2.0-arm64.dmg?redirect=evil",
            "file:///Applications/Canis97.app"
        ] {
            let release = try GitHubReleaseClient.decodeLatestRelease(releaseData(downloadURL: url), repository: repository)
            requireNil(release.downloadURL)
            let alert = SoftwareUpdateAlert.available(current: try requireValue(StableSemanticVersion("0.1.4")), release: release)
            requireEqual(alert.updateURL?.absoluteString, "https://canis97.com/#install")
            requireEqual(alert.actionTitle, "Get the Update")
        }
    }

    func testReleasePageMustMatchTheAdvertisedVersionExactly() throws {
        let repository = try requireValue(GitHubRepository("gabeosx/canis97"))
        let data = releaseData(downloadURL: "https://example.com", pageURL: "https://github.com/gabeosx/canis97/releases/tag/v0.1.4")
        requireRejection(try GitHubReleaseClient.decodeLatestRelease(data, repository: repository))
    }

    private func releaseData(downloadURL: String, pageURL: String = "https://github.com/gabeosx/canis97/releases/tag/v0.2.0") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": "v0.2.0", "html_url": pageURL, "draft": false, "prerelease": false,
            "assets": [["name": "Canis97-0.2.0-arm64.dmg", "browser_download_url": downloadURL]]
        ])
    }

}

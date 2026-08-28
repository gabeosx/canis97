import AppKit
import Foundation

private struct RunningApp: Equatable {
    let processIdentifier: Int32
    let bundleURL: URL?
    let executableURL: URL?
}

@MainActor
private protocol ApplicationWorkspace: AnyObject {
    func runningApplications(bundleIdentifier: String) -> [RunningApp]
    @discardableResult func terminate(processIdentifier: Int32, force: Bool) -> Bool
    func openApplication(at bundleURL: URL) async throws
}

@MainActor
private final class NativeApplicationWorkspace: ApplicationWorkspace {
    func runningApplications(bundleIdentifier: String) -> [RunningApp] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map {
            RunningApp(
                processIdentifier: Int32($0.processIdentifier),
                bundleURL: $0.bundleURL,
                executableURL: $0.executableURL
            )
        }
    }

    func terminate(processIdentifier: Int32, force: Bool) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: pid_t(processIdentifier)) else {
            return true
        }
        return force ? application.forceTerminate() : application.terminate()
    }

    func openApplication(at bundleURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private enum LauncherFailure: String, Error {
    case configurationMissing = "native-configuration-missing"
    case prelaunchCleanupFailed = "native-prelaunch-cleanup-failed"
    case openFailed = "native-open-failed"
    case zeroAfterOpen = "native-zero-after-open"
    case multipleAfterOpen = "native-multiple-after-open"
    case identityMismatch = "native-identity-mismatch"
}

@MainActor
private struct SingleInstanceLauncher {
    let workspace: ApplicationWorkspace
    var pollNanoseconds: UInt64 = 100_000_000
    var gracefulPolls = 30
    var forcePolls = 30
    var launchPolls = 100

    func launch(bundleURL: URL, bundleIdentifier: String, executableURL: URL) async throws -> Int32 {
        try await closeAll(bundleIdentifier: bundleIdentifier)

        do {
            try await workspace.openApplication(at: bundleURL)
        } catch {
            throw LauncherFailure.openFailed
        }

        do {
            let application = try await waitForSingleApplication(bundleIdentifier: bundleIdentifier)
            guard canonical(application.bundleURL) == canonical(bundleURL),
                  canonical(application.executableURL) == canonical(executableURL) else {
                throw LauncherFailure.identityMismatch
            }
            return application.processIdentifier
        } catch {
            try? await closeAll(bundleIdentifier: bundleIdentifier)
            throw error
        }
    }

    private func closeAll(bundleIdentifier: String) async throws {
        var applications = workspace.runningApplications(bundleIdentifier: bundleIdentifier)
        for application in applications {
            _ = workspace.terminate(processIdentifier: application.processIdentifier, force: false)
        }
        if await waitForZero(bundleIdentifier: bundleIdentifier, polls: gracefulPolls) {
            return
        }

        applications = workspace.runningApplications(bundleIdentifier: bundleIdentifier)
        for application in applications {
            _ = workspace.terminate(processIdentifier: application.processIdentifier, force: true)
        }
        guard await waitForZero(bundleIdentifier: bundleIdentifier, polls: forcePolls) else {
            throw LauncherFailure.prelaunchCleanupFailed
        }
    }

    private func waitForZero(bundleIdentifier: String, polls: Int) async -> Bool {
        for attempt in 0...polls {
            if workspace.runningApplications(bundleIdentifier: bundleIdentifier).isEmpty {
                return true
            }
            if attempt < polls {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }
        return false
    }

    private func waitForSingleApplication(bundleIdentifier: String) async throws -> RunningApp {
        for attempt in 0...launchPolls {
            let applications = workspace.runningApplications(bundleIdentifier: bundleIdentifier)
            if applications.count == 1, let application = applications.first {
                return application
            }
            if applications.count > 1 {
                throw LauncherFailure.multipleAfterOpen
            }
            if attempt < launchPolls {
                try? await Task.sleep(nanoseconds: pollNanoseconds)
            }
        }
        throw LauncherFailure.zeroAfterOpen
    }

    private func canonical(_ url: URL?) -> URL? {
        url?.standardizedFileURL.resolvingSymlinksInPath()
    }
}

@MainActor
private final class FakeApplicationWorkspace: ApplicationWorkspace {
    enum OpenBehavior {
        case exact
        case none
        case multiple
        case wrongIdentity
        case failure
    }

    var applications: [RunningApp]
    var openBehavior: OpenBehavior
    var refusesTermination = false
    var openCount = 0
    var terminationCount = 0
    let expectedBundleURL: URL
    let expectedExecutableURL: URL

    init(
        applications: [RunningApp] = [],
        openBehavior: OpenBehavior,
        expectedBundleURL: URL,
        expectedExecutableURL: URL
    ) {
        self.applications = applications
        self.openBehavior = openBehavior
        self.expectedBundleURL = expectedBundleURL
        self.expectedExecutableURL = expectedExecutableURL
    }

    func runningApplications(bundleIdentifier: String) -> [RunningApp] {
        applications
    }

    func terminate(processIdentifier: Int32, force: Bool) -> Bool {
        terminationCount += 1
        guard !refusesTermination else { return false }
        applications.removeAll { $0.processIdentifier == processIdentifier }
        return true
    }

    func openApplication(at bundleURL: URL) async throws {
        openCount += 1
        switch openBehavior {
        case .exact:
            applications = [RunningApp(processIdentifier: 401, bundleURL: expectedBundleURL, executableURL: expectedExecutableURL)]
        case .none:
            applications = []
        case .multiple:
            applications = [
                RunningApp(processIdentifier: 401, bundleURL: expectedBundleURL, executableURL: expectedExecutableURL),
                RunningApp(processIdentifier: 402, bundleURL: expectedBundleURL, executableURL: expectedExecutableURL),
            ]
        case .wrongIdentity:
            applications = [RunningApp(
                processIdentifier: 401,
                bundleURL: URL(fileURLWithPath: "/tmp/Wrong.app"),
                executableURL: URL(fileURLWithPath: "/tmp/Wrong.app/Contents/MacOS/Wrong")
            )]
        case .failure:
            throw LauncherFailure.openFailed
        }
    }
}

@MainActor
private func runSelfTests() async throws {
    let bundleURL = URL(fileURLWithPath: "/tmp/Canis97.app")
    let executableURL = bundleURL.appending(path: "Contents/MacOS/Canis97")

    func launcher(_ workspace: FakeApplicationWorkspace) -> SingleInstanceLauncher {
        SingleInstanceLauncher(
            workspace: workspace,
            pollNanoseconds: 1,
            gracefulPolls: 1,
            forcePolls: 1,
            launchPolls: 1
        )
    }

    let oldApps = [
        RunningApp(processIdentifier: 101, bundleURL: bundleURL, executableURL: executableURL),
        RunningApp(processIdentifier: 102, bundleURL: bundleURL, executableURL: executableURL),
    ]
    let exact = FakeApplicationWorkspace(
        applications: oldApps,
        openBehavior: .exact,
        expectedBundleURL: bundleURL,
        expectedExecutableURL: executableURL
    )
    let pid = try await launcher(exact).launch(
        bundleURL: bundleURL,
        bundleIdentifier: "com.canis97.player",
        executableURL: executableURL
    )
    precondition(pid == 401 && exact.openCount == 1 && exact.terminationCount == 2)

    let sticky = FakeApplicationWorkspace(
        applications: oldApps,
        openBehavior: .exact,
        expectedBundleURL: bundleURL,
        expectedExecutableURL: executableURL
    )
    sticky.refusesTermination = true
    do {
        _ = try await launcher(sticky).launch(
            bundleURL: bundleURL,
            bundleIdentifier: "com.canis97.player",
            executableURL: executableURL
        )
        preconditionFailure("sticky applications must prevent opening")
    } catch LauncherFailure.prelaunchCleanupFailed {
        precondition(sticky.openCount == 0)
    }

    for behavior in [FakeApplicationWorkspace.OpenBehavior.none, .multiple, .wrongIdentity, .failure] {
        let workspace = FakeApplicationWorkspace(
            openBehavior: behavior,
            expectedBundleURL: bundleURL,
            expectedExecutableURL: executableURL
        )
        do {
            _ = try await launcher(workspace).launch(
                bundleURL: bundleURL,
                bundleIdentifier: "com.canis97.player",
                executableURL: executableURL
            )
            preconditionFailure("failure behavior must not succeed")
        } catch {
            precondition(workspace.openCount == 1)
            precondition(workspace.applications.isEmpty)
        }
    }
}

@main
private enum NativeSingleInstanceLauncherMain {
    @MainActor
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["self-test"] {
            do {
                try await runSelfTests()
                print("native-launcher-tests: PASS")
            } catch {
                fputs("native-launcher-tests: FAIL\n", stderr)
                Foundation.exit(1)
            }
            return
        }

        guard arguments.count == 4, arguments[0] == "launch" else {
            fputs("process-stage: \(LauncherFailure.configurationMissing.rawValue)\n", stderr)
            Foundation.exit(2)
        }

        let bundleURL = URL(fileURLWithPath: arguments[1])
        let bundleIdentifier = arguments[2]
        let executableURL = URL(fileURLWithPath: arguments[3])
        guard FileManager.default.fileExists(atPath: bundleURL.path),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            fputs("process-stage: \(LauncherFailure.configurationMissing.rawValue)\n", stderr)
            Foundation.exit(2)
        }

        do {
            let pid = try await SingleInstanceLauncher(workspace: NativeApplicationWorkspace()).launch(
                bundleURL: bundleURL,
                bundleIdentifier: bundleIdentifier,
                executableURL: executableURL
            )
            print(pid)
        } catch let failure as LauncherFailure {
            fputs("process-stage: \(failure.rawValue)\n", stderr)
            Foundation.exit(1)
        } catch {
            fputs("process-stage: \(LauncherFailure.openFailed.rawValue)\n", stderr)
            Foundation.exit(1)
        }
    }
}

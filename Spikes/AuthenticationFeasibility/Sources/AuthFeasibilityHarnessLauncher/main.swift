import AppKit
import AuthFeasibilityCore
import AuthFeasibilityHarness
import Foundation

private enum LauncherError: Error {
    case invalidArguments
    case invalidOutputPath
}

private struct LaunchConfiguration {
    let contract: AuthExperimentContract
    let approval: ExperimentApproval
}

@main
@MainActor
private struct AuthFeasibilityHarnessLauncher {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] {
                print("usage: AuthFeasibilityHarness --live-browser --output <phase-0-browser-probe-path>")
                return
            }

            let configuration = try launchConfiguration(arguments: arguments)
            let application = NSApplication.shared
            let delegate = try BrowserHarnessApplication(configuration: configuration)
            application.delegate = delegate
            application.setActivationPolicy(.regular)
            application.run()
        } catch {
            FileHandle.standardError.write(Data("launch gate failed\n".utf8))
        }
    }

    private static func launchConfiguration(arguments: [String]) throws -> LaunchConfiguration {
        guard arguments.count == 3,
              arguments[0] == "--live-browser",
              arguments[1] == "--output" else {
            throw LauncherError.invalidArguments
        }

        let output = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        guard output.lastPathComponent == "00-BROWSER-PROBE.md" else {
            throw LauncherError.invalidOutputPath
        }

        let phaseDirectory = output.deletingLastPathComponent()
        let toolchain = try String(
            contentsOf: phaseDirectory.appendingPathComponent("00-TOOLCHAIN.md"),
            encoding: .utf8
        )
        let contract = try AuthExperimentContract.parse(
            String(
                contentsOf: phaseDirectory.appendingPathComponent("00-PUBLIC-AUTH-CONTRACT.md"),
                encoding: .utf8
            )
        )
        let approval = try ExperimentApproval.parse(
            String(
                contentsOf: phaseDirectory.appendingPathComponent("00-PUBLIC-AUTH-CONTRACT-APPROVAL.md"),
                encoding: .utf8
            )
        )
        try BrowserLaunchGate.validate(
            toolchainArtifact: toolchain,
            contract: contract,
            approval: approval
        )

        return LaunchConfiguration(contract: contract, approval: approval)
    }
}

@MainActor
private final class BrowserHarnessApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let runtime: LiveBrowserRuntime
    private var window: NSWindow?

    init(configuration: LaunchConfiguration) throws {
        runtime = try LiveBrowserRuntime(
            contract: configuration.contract,
            approval: configuration.approval
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sirius Mac Authentication Feasibility"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        do {
            try runtime.startOwnerOperatedRun { [weak self] browser in
                guard let self, let window = self.window else { return }
                window.contentView = browser
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } catch {
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = runtime.cancel()
        window?.contentView = nil
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        _ = runtime.cancel()
        NSApp.terminate(nil)
    }
}

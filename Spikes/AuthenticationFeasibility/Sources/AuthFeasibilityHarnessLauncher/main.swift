import AppKit
import AuthFeasibilityCore
import AuthFeasibilityHarness
import Foundation
import Darwin

private enum LauncherError: Error {
    case invalidArguments
    case invalidOutputPath
}

private struct LaunchConfiguration {
    let contract: AuthExperimentContract
    let approval: ExperimentApproval
    let output: URL
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
            exit(1)
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

        return LaunchConfiguration(contract: contract, approval: approval, output: output)
    }
}

@MainActor
private final class BrowserHarnessApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let runtime: LiveBrowserRuntime
    private var window: NSWindow?
    private var shutdownStarted = false
    private var shutdownFinished = false
    private let renewalStatusLabel = NSTextField(labelWithString: RenewalStatus.pending.ownerVisibleText)
    private let proofStatusLabel = NSTextField(labelWithString: "Waiting for an app-bound return")

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
        renewalStatusLabel.alignment = .center
        renewalStatusLabel.setAccessibilityLabel("Renewal status")
        renewalStatusLabel.setAccessibilityValue(RenewalStatus.pending.ownerVisibleText)
        runtime.onRenewalStatusChanged = { [weak self] status in
            self?.renewalStatusLabel.stringValue = status.ownerVisibleText
            self?.renewalStatusLabel.setAccessibilityValue(status.ownerVisibleText)
        }
        proofStatusLabel.alignment = .center
        proofStatusLabel.setAccessibilityLabel("Proof status")
        proofStatusLabel.setAccessibilityValue("Waiting for an app-bound return")

        do {
            try runtime.startOwnerOperatedRun { [weak self] browser in
                guard let self, let window = self.window else { return }
                let content = NSStackView(views: [browser, self.proofStatusLabel, self.renewalStatusLabel])
                content.orientation = .vertical
                content.spacing = 8
                content.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
                browser.translatesAutoresizingMaskIntoConstraints = false
                self.renewalStatusLabel.translatesAutoresizingMaskIntoConstraints = false
                content.addConstraint(NSLayoutConstraint(
                    item: browser,
                    attribute: .height,
                    relatedBy: .greaterThanOrEqual,
                    toItem: nil,
                    attribute: .notAnAttribute,
                    multiplier: 1,
                    constant: 620
                ))
                window.contentView = content
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } catch {
            FileHandle.standardError.write(Data("browser startup failed\n".utf8))
            exit(1)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shutdownFinished { return .terminateNow }
        guard !shutdownStarted else { return .terminateLater }
        shutdownStarted = true
        proofStatusLabel.stringValue = "Verifying cleanup"
        proofStatusLabel.setAccessibilityValue("Verifying cleanup")

        Task { @MainActor [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            let proof = await runtime.cleanUp()
            guard proof == .verified else {
                shutdownStarted = false
                proofStatusLabel.stringValue = "Cleanup failed — window remains open"
                proofStatusLabel.setAccessibilityValue("Cleanup failed")
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            shutdownFinished = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
}

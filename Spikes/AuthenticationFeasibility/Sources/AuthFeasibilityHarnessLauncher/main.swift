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
    private let bridgeOutput: URL
    private let pageStatusOutput: URL
    private var window: NSWindow?
    private var importTask: Task<Void, Never>?
    private var shutdownStarted = false
    private var shutdownFinished = false
    private let renewalStatusLabel = NSTextField(labelWithString: RenewalStatus.pending.ownerVisibleText)
    private let proofStatusLabel = NSTextField(labelWithString: "Waiting for an app-bound return")
    private let sessionStatusLabel = NSTextField(labelWithString: BrowserPageStatus.loading.ownerVisibleText)
    private lazy var importSessionButton = NSButton(
        title: "Use Logged-In Session",
        target: self,
        action: #selector(importLoggedInSession)
    )
    private lazy var finishRunButton = NSButton(
        title: "Verify Sign-Out & Finish Run",
        target: self,
        action: #selector(verifySignOutAndFinishRun)
    )

    init(configuration: LaunchConfiguration) throws {
        runtime = try LiveBrowserRuntime(
            contract: configuration.contract,
            approval: configuration.approval
        )
        bridgeOutput = configuration.output
            .deletingLastPathComponent()
            .appendingPathComponent("00-WEB-SESSION-BRIDGE.md")
        pageStatusOutput = configuration.output
            .deletingLastPathComponent()
            .appendingPathComponent("00-WEB-PAGE-STATUS.md")
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
        sessionStatusLabel.alignment = .center
        sessionStatusLabel.maximumNumberOfLines = 2
        sessionStatusLabel.setAccessibilityLabel("Web session import status")
        runtime.onPageStatusChanged = { [weak self] status in
            guard let self else { return }
            sessionStatusLabel.stringValue = status.ownerVisibleText
            sessionStatusLabel.setAccessibilityValue(status.ownerVisibleText)
            try? status.canonicalText.write(to: pageStatusOutput, atomically: true, encoding: .utf8)
        }
        importSessionButton.setAccessibilityLabel("Use logged-in SiriusXM session")
        finishRunButton.isEnabled = false
        finishRunButton.setAccessibilityLabel("Verify sign-out and finish run")

        do {
            try runtime.startOwnerOperatedRun { [weak self] browser in
                guard let self, let window = self.window else { return }
                let content = NSStackView(views: [
                    browser,
                    self.sessionStatusLabel,
                    self.importSessionButton,
                    self.finishRunButton,
                    self.proofStatusLabel,
                    self.renewalStatusLabel,
                ])
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

    @objc private func importLoggedInSession() {
        guard importTask == nil else { return }
        importSessionButton.isEnabled = false
        sessionStatusLabel.stringValue = "Importing first-party session in memory…"
        sessionStatusLabel.setAccessibilityValue("Importing session")

        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await runtime.importAuthenticatedWebSession()
            do {
                try result.canonicalText.write(to: bridgeOutput, atomically: true, encoding: .utf8)
                sessionStatusLabel.stringValue = result.ownerVisibleText
                sessionStatusLabel.setAccessibilityValue(result.ownerVisibleText)
            } catch {
                sessionStatusLabel.stringValue = "Could not write sanitized bridge result"
                sessionStatusLabel.setAccessibilityValue("Bridge result write failed")
            }
            importSessionButton.isEnabled = false
            self.finishRunButton.isEnabled = result == .authenticated
            importTask = nil
        }
    }

    @objc private func verifySignOutAndFinishRun() {
        guard importTask == nil else { return }
        finishRunButton.isEnabled = false
        proofStatusLabel.stringValue = "Verifying sign-out and local cleanup"
        proofStatusLabel.setAccessibilityValue("Verifying sign-out and cleanup")
        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let proof = await runtime.verifySignOutAndClean()
            let text = proof == .verified ? "Run cleanup verified" : "Run closed without completion"
            proofStatusLabel.stringValue = text
            proofStatusLabel.setAccessibilityValue(text)
            importTask = nil
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
        importTask?.cancel()
        window?.contentView = nil
        window = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
}

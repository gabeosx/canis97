import Foundation
import Testing
@testable import AuthFeasibilityCore

@Test("only the researched current Xcode and SDK qualify")
func toolchainGateRequiresTheExactResearchedToolchain() {
    #expect(
        ToolchainGate.evaluate(
            xcodeVersion: "Xcode 26.6\nBuild version synthetic",
            sdkVersion: "26.5",
            frameworkImportsPassed: true
        ) == .currentSDKReady
    )

    #expect(ToolchainGate.evaluate(xcodeVersion: nil, sdkVersion: "26.5", frameworkImportsPassed: true) == .environmentPending)
    #expect(ToolchainGate.evaluate(xcodeVersion: "Xcode 26.5", sdkVersion: "26.5", frameworkImportsPassed: true) == .environmentPending)
    #expect(ToolchainGate.evaluate(xcodeVersion: "Xcode 26.6", sdkVersion: "26.4", frameworkImportsPassed: true) == .environmentPending)
    #expect(ToolchainGate.evaluate(xcodeVersion: "Xcode 26.6", sdkVersion: "26.5", frameworkImportsPassed: false) == .environmentPending)
}

@Test("toolchain artifacts use a closed, non-diagnostic vocabulary")
func toolchainGateEmitsOnlyClosedArtifacts() {
    #expect(ToolchainGate.artifact(for: .currentSDKReady).contains("Status: current-sdk-ready"))
    #expect(ToolchainGate.artifact(for: .environmentPending).contains("Status: environment-pending"))
    #expect(!ToolchainGate.artifact(for: .environmentPending).contains("/Applications"))
}

@Test("browser launch requires the exact current toolchain, ready contract, and bound approval")
func browserLaunchGateRequiresEveryOfflinePrerequisite() throws {
    let toolchain = ToolchainGate.artifact(for: .currentSDKReady)
    let contract = AuthExperimentContract.readyForBrowserExperiment()
    let approval = try ExperimentApproval.record(for: contract)

    try BrowserLaunchGate.validate(
        toolchainArtifact: toolchain,
        contract: contract,
        approval: approval
    )

    #expect(throws: ContractError.self) {
        try BrowserLaunchGate.validate(
            toolchainArtifact: ToolchainGate.artifact(for: .environmentPending),
            contract: contract,
            approval: approval
        )
    }

    var incomplete = contract
    incomplete.browser.renewalExpectation = .open
    #expect(throws: ContractError.self) {
        try BrowserLaunchGate.validate(
            toolchainArtifact: toolchain,
            contract: incomplete,
            approval: approval
        )
    }
}

@Test("shell preflight fails closed for each command failure and records the real environment")
func shellPreflightWritesOnlyClosedStatuses() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("auth-feasibility-toolchain-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    for scenario in ["selected-developer", "xcode-version", "sdk-version", "framework-import", "ready"] {
        let output = root.appendingPathComponent("\(scenario).md")
        let result = try runPreflight(in: root, output: output, scenario: scenario)
        #expect(result == 0)
        let expected: ToolchainEligibility = scenario == "ready" ? .currentSDKReady : .environmentPending
        #expect(try String(contentsOf: output, encoding: .utf8) == ToolchainGate.artifact(for: expected))
    }

    let realOutput = root.appendingPathComponent("real-environment.md")
    #expect(try runPreflight(in: root, output: realOutput, scenario: nil) == 0)
    let realArtifact = try String(contentsOf: realOutput, encoding: .utf8)
    #expect(
        realArtifact == ToolchainGate.artifact(for: .currentSDKReady) ||
        realArtifact == ToolchainGate.artifact(for: .environmentPending)
    )
}

private func runPreflight(in root: URL, output: URL, scenario: String?) throws -> Int32 {
    let fixtureBin = root.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: fixtureBin, withIntermediateDirectories: true)
    try writeFixtureCommands(to: fixtureBin)

    let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Scripts/verify-current-xcode.sh")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, "--output", output.path]
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = fixtureBin.path + ":" + (environment["PATH"] ?? "")
    if let scenario { environment["AUTH_FEASIBILITY_TEST_SCENARIO"] = scenario }
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

private func writeFixtureCommands(to directory: URL) throws {
    let commands: [String: String] = [
        "xcode-select": "#!/bin/sh\n[ \"${AUTH_FEASIBILITY_TEST_SCENARIO:-}\" = selected-developer ] && exit 1\nprintf '%s\\n' /synthetic/developer\n",
        "xcodebuild": "#!/bin/sh\n[ \"${AUTH_FEASIBILITY_TEST_SCENARIO:-}\" = xcode-version ] && { printf '%s\\n' 'Xcode 26.5'; exit 0; }\nprintf '%s\\n' 'Xcode 26.6' 'Build version synthetic'\n",
        "xcrun": "#!/bin/sh\nif [ \"$1\" = --sdk ] && [ \"$3\" = --show-sdk-version ]; then [ \"${AUTH_FEASIBILITY_TEST_SCENARIO:-}\" = sdk-version ] && printf '%s\\n' 26.4 || printf '%s\\n' 26.5; exit 0; fi\n[ \"${AUTH_FEASIBILITY_TEST_SCENARIO:-}\" = framework-import ] && exit 1\nexit 0\n",
    ]
    for (name, contents) in commands {
        let path = directory.appendingPathComponent(name)
        try contents.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
}

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

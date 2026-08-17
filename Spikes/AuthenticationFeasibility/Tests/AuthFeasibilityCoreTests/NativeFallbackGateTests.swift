import Testing
@testable import AuthFeasibilityCore

@Test("renewal-pending keeps native-direct not applicable")
func renewalPendingCannotSelectNativeDirect() throws {
    let contract = AuthExperimentContract.readyForBrowserExperiment()

    #expect(
        try NativeLaunchGate.evaluate(
            toolchainArtifact: ToolchainGate.artifact(for: .currentSDKReady),
            contract: contract,
            browserProbe: .renewalPending,
            nativeApproval: .notApplicable
        ) == .notApplicable
    )
}

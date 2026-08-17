public enum ToolchainEligibility: Equatable, Sendable {
    case currentSDKReady
    case environmentPending
}

/// Keeps environment readiness separate from provider feasibility.  This gate only
/// recognizes the exact researched local toolchain; every other result is incomplete.
public enum ToolchainGate {
    public static func evaluate(
        xcodeVersion: String?,
        sdkVersion: String?,
        frameworkImportsPassed: Bool
    ) -> ToolchainEligibility {
        guard xcodeVersion?.split(separator: "\n").first == "Xcode 26.6",
              sdkVersion == "26.5",
              frameworkImportsPassed else {
            return .environmentPending
        }
        return .currentSDKReady
    }

    public static func artifact(for eligibility: ToolchainEligibility) -> String {
        switch eligibility {
        case .currentSDKReady:
            return [
                "Schema: phase-0-toolchain-v1",
                "Status: current-sdk-ready",
                "Xcode: 26.6",
                "macOS SDK: 26.5",
                "Deployment target: macOS 26.0",
                "Framework imports: passed",
                "Replacement execution: incomplete",
                "Phase 1 continuation: blocked",
                "",
            ].joined(separator: "\n")
        case .environmentPending:
            return [
                "Schema: phase-0-toolchain-v1",
                "Status: environment-pending",
                "Toolchain: unavailable-or-mismatched",
                "Replacement execution: incomplete",
                "Phase 1 continuation: blocked",
                "",
            ].joined(separator: "\n")
        }
    }
}

/// Validates the complete offline conjunction that permits presentation of the
/// owner-operated browser checkpoint. This gate deliberately accepts only
/// canonical, non-secret artifacts; it performs no provider or browser work.
public enum BrowserLaunchGate {
    public static func validate(
        toolchainArtifact: String,
        contract: AuthExperimentContract,
        approval: ExperimentApproval
    ) throws {
        guard toolchainArtifact == ToolchainGate.artifact(for: .currentSDKReady),
              try CandidateSelection.experimentReadiness(for: contract) == .browserExperimentReady else {
            throw ContractError.invalidArtifact
        }
        try approval.validate(against: contract)
    }
}

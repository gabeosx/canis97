// swift-tools-version: 6.3
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repositoryRoot = packageRoot
    .deletingLastPathComponent()
    .deletingLastPathComponent()

func hasExactContents(_ relativePath: String, _ expected: String) -> Bool {
    let path = repositoryRoot.appendingPathComponent(relativePath).path
    return (try? String(contentsOfFile: path, encoding: .utf8)) == expected
}

let readyToolchain = """
Schema: phase-0-toolchain-v1
Status: current-sdk-ready
Xcode: 26.6
macOS SDK: 26.5
Deployment target: macOS 26.0
Framework imports: passed
Replacement execution: incomplete
Phase 1 continuation: blocked
""" + "\n"

let approvedContract = """
Schema: auth-experiment-v1
Review revision: empirical-proof-v2
Browser entry URL: https://www.siriusxm.com/
Browser entry state: established
Browser entry provenance: public-first-party
Navigation state: established
Navigation provenance: public-first-party
Return shape state: established
Return shape provenance: sanitized-preliminary
Transition state: established
Transition provenance: sanitized-preliminary
Stop bounds state: established
Stop bounds provenance: sanitized-preliminary
Authentication expectation state: established
Authentication expectation provenance: sanitized-preliminary
Entitlement expectation state: established
Entitlement expectation provenance: sanitized-preliminary
Renewal expectation state: established
Renewal expectation provenance: sanitized-preliminary
Tune/key expectation state: established
Tune/key expectation provenance: sanitized-preliminary
Sign-out expectation state: established
Sign-out expectation provenance: sanitized-preliminary
Third-party callback documentation state: open
Third-party callback documentation provenance: open
Native purpose identity state: established
Native purpose identity provenance: sanitized-preliminary
Native authentication state: established
Native authentication provenance: sanitized-preliminary
Native result state: established
Native result provenance: sanitized-preliminary
Native entitlement state: established
Native entitlement provenance: sanitized-preliminary
Native renewal state: established
Native renewal provenance: sanitized-preliminary
Native tune/key state: established
Native tune/key provenance: sanitized-preliminary
Native sign-out state: established
Native sign-out provenance: sanitized-preliminary
Digest: 573f6ba270924112
""" + "\n"

let digestBoundApproval = """
Schema: experiment-approval-v1
Contract digest: 573f6ba270924112
Owner approval: confirmed
""" + "\n"

let browserExperimentEnabled =
    hasExactContents(".planning/phases/00-authentication-feasibility-gate/00-TOOLCHAIN.md", readyToolchain) &&
    hasExactContents(".planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT.md", approvedContract) &&
    hasExactContents(".planning/phases/00-authentication-feasibility-gate/00-PUBLIC-AUTH-CONTRACT-APPROVAL.md", digestBoundApproval)

var products: [Product] = [
    .library(name: "AuthFeasibilityCore", targets: ["AuthFeasibilityCore"]),
    .executable(name: "auth-feasibility", targets: ["AuthFeasibilityRunner"]),
]

var targets: [Target] = [
    .target(name: "AuthFeasibilityCore"),
    .executableTarget(name: "AuthFeasibilityRunner", dependencies: ["AuthFeasibilityCore"]),
]

if browserExperimentEnabled {
    products.append(.library(name: "AuthFeasibilityHarness", targets: ["AuthFeasibilityHarness"]))
    targets.append(
        .target(
            name: "AuthFeasibilityHarness",
            dependencies: ["AuthFeasibilityCore"],
            linkerSettings: [.linkedFramework("WebKit")]
        )
    )
}

var testDependencies: [Target.Dependency] = ["AuthFeasibilityCore"]
if browserExperimentEnabled {
    testDependencies.append("AuthFeasibilityHarness")
}
targets.append(.testTarget(name: "AuthFeasibilityCoreTests", dependencies: testDependencies))

let package = Package(
    name: "AuthenticationFeasibility",
    platforms: [.macOS(.v26)],
    products: products,
    targets: targets
)

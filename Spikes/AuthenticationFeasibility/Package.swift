// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AuthenticationFeasibility",
    products: [
        .library(name: "AuthFeasibilityCore", targets: ["AuthFeasibilityCore"]),
        .executable(name: "auth-feasibility", targets: ["AuthFeasibilityRunner"]),
    ],
    targets: [
        .target(name: "AuthFeasibilityCore"),
        .executableTarget(name: "AuthFeasibilityRunner", dependencies: ["AuthFeasibilityCore"]),
        .testTarget(name: "AuthFeasibilityCoreTests", dependencies: ["AuthFeasibilityCore"]),
    ]
)

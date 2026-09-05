// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Canis97MotionSafety",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Canis97MotionSafety", targets: ["Canis97MotionSafety"]),
    ],
    targets: [
        .target(name: "Canis97MotionSafety"),
        .testTarget(name: "Canis97MotionSafetyTests", dependencies: ["Canis97MotionSafety"]),
    ]
)

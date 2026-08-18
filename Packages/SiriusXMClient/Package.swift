// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SiriusXMClient",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SiriusXMClient", targets: ["SiriusXMClient"]),
    ],
    targets: [
        .target(name: "SiriusXMClient"),
        .testTarget(name: "SiriusXMClientTests", dependencies: ["SiriusXMClient"]),
        .testTarget(name: "PublicAPITests", dependencies: ["SiriusXMClient"]),
    ]
)

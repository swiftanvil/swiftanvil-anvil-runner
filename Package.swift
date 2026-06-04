// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AnvilRunner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AnvilRunner", targets: ["AnvilRunner"]),
        .executable(name: "anvil-runner", targets: ["AnvilRunnerCLI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AnvilRunner"
        ),
        .executableTarget(
            name: "AnvilRunnerCLI",
            dependencies: ["AnvilRunner"]
        ),
        .testTarget(
            name: "AnvilRunnerTests",
            dependencies: ["AnvilRunner"]
        )
    ],
    swiftLanguageModes: [.v6]
)

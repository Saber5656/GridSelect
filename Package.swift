// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GridSelect",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "GridSelect",
            targets: ["GridSelect"]
        ),
        .library(
            name: "GridSelectCore",
            targets: ["GridSelectCore"]
        )
    ],
    targets: [
        .executableTarget(
            name: "GridSelect",
            dependencies: ["GridSelectCore"]
        ),
        .target(
            name: "GridSelectCore"
        ),
        .testTarget(
            name: "GridSelectCoreTests",
            dependencies: ["GridSelectCore"]
        )
    ]
)

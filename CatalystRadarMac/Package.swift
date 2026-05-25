// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CatalystRadar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CatalystRadar", targets: ["CatalystRadar"])
    ],
    targets: [
        .executableTarget(
            name: "CatalystRadar",
            path: "Sources/CatalystRadar"
        )
    ]
)

// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CRT",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CRT", targets: ["CRT"])
    ],
    targets: [
        .executableTarget(
            name: "CRT",
            path: "Sources/CRT"
        )
    ]
)

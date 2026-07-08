// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RustTopTahoe",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "RustTopTahoe",
            targets: ["RustTopTahoe"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RustTopTahoe",
            path: "Sources/RustTopTahoe"
        ),
        .testTarget(
            name: "RustTopTahoeTests",
            dependencies: ["RustTopTahoe"],
            path: "Tests/RustTopTahoeTests",
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)

// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Loops",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LoopsCore", targets: ["LoopsCore"]),
        .library(name: "LoopsEngine", targets: ["LoopsEngine"]),
        .library(name: "LoopsApp", targets: ["LoopsApp"]),
    ],
    targets: [
        .target(
            name: "LoopsCore",
            dependencies: [],
            path: "Sources/LoopsCore"
        ),
        .testTarget(
            name: "LoopsCoreTests",
            dependencies: ["LoopsCore"],
            path: "Tests/LoopsCoreTests"
        ),
        .target(
            name: "LoopsEngine",
            dependencies: ["LoopsCore"],
            path: "Sources/LoopsEngine"
        ),
        .testTarget(
            name: "LoopsEngineTests",
            dependencies: ["LoopsEngine"],
            path: "Tests/LoopsEngineTests"
        ),
        .target(
            name: "LoopsApp",
            dependencies: ["LoopsCore", "LoopsEngine"],
            path: "Sources/LoopsApp"
        ),
        .testTarget(
            name: "LoopsAppTests",
            dependencies: ["LoopsApp"],
            path: "Tests/LoopsAppTests"
        ),
    ]
)

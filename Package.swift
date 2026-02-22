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
        .executable(name: "Loops", targets: ["LoopsRunner"]),
    ],
    targets: [
        .executableTarget(
            name: "LoopsRunner",
            dependencies: ["LoopsApp", "LoopsEngine"],
            path: "LoopsApp/LoopsApp",
            exclude: ["LoopsApp.entitlements"]
        ),
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
            dependencies: ["LoopsEngine", "LoopsApp"],
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

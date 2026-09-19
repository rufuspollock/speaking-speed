// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "speaking-speed",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "speaking-speed", targets: ["speaking-speed"]),
    ],
    targets: [
        .target(name: "SpeakingSpeedCore"),
        .executableTarget(name: "speaking-speed", dependencies: ["SpeakingSpeedCore"]),
        .testTarget(name: "SpeakingSpeedCoreTests", dependencies: ["SpeakingSpeedCore"]),
    ]
)

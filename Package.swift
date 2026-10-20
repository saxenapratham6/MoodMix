// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MoodMix",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MoodMixCore", targets: ["MoodMixCore"]),
        .executable(name: "MoodMix", targets: ["MoodMixMac"]),
    ],
    targets: [
        .target(name: "MoodMixCore"),
        .executableTarget(name: "MoodMixMac", dependencies: ["MoodMixCore"]),
        .testTarget(name: "MoodMixCoreTests", dependencies: ["MoodMixCore"]),
    ]
)

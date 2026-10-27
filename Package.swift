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
        .executableTarget(
            name: "MoodMixMac",
            dependencies: ["MoodMixCore"],
            exclude: ["Info.plist"],
            // Embed an Info.plist so macOS can show "MoodMix wants to control Spotify".
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                                           "-Xlinker", "Sources/MoodMixMac/Info.plist"])]
        ),
        .testTarget(name: "MoodMixCoreTests", dependencies: ["MoodMixCore"]),
    ]
)

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
            // Embed an Info.plist so macOS can show "MoodMix wants to control Spotify". The path is absolute
            // because Xcode links from a different working directory than `swift build`.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                                           "-Xlinker", Context.packageDirectory + "/Sources/MoodMixMac/Info.plist"],
                                          .when(platforms: [.macOS]))]
        ),
        .testTarget(name: "MoodMixCoreTests", dependencies: ["MoodMixCore"]),
    ]
)

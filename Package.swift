// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LimitsBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "LimitsBarCore"),
        .executableTarget(
            name: "LimitsBar",
            dependencies: ["LimitsBarCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "LimitsBarCoreTests", dependencies: ["LimitsBarCore"]),
    ]
)

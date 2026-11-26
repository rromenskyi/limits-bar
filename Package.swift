// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LimitsBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LimitsBarCore"),
        .executableTarget(name: "LimitsBar", dependencies: ["LimitsBarCore"]),
        .testTarget(name: "LimitsBarCoreTests", dependencies: ["LimitsBarCore"]),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Timekeeper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TimekeeperCore"),
        .executableTarget(name: "Timekeeper", dependencies: ["TimekeeperCore"]),
        .testTarget(name: "TimekeeperCoreTests", dependencies: ["TimekeeperCore"]),
    ]
)

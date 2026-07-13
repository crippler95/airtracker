// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "AirTrackerCore",
            resources: [.copy("Resources/Web")]
        ),
        .executableTarget(
            name: "AirTracker",
            dependencies: ["AirTrackerCore"]
        ),
        .testTarget(
            name: "AirTrackerCoreTests",
            dependencies: ["AirTrackerCore"]
        ),
    ]
)

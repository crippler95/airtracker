// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirTracker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AirTracker",
            resources: [.copy("Resources/Web")]
        )
    ]
)

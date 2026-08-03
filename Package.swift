// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HotspotTraffic",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HotspotTrafficApp", targets: ["HotspotTrafficApp"])
    ],
    targets: [
        .executableTarget(
            name: "HotspotTrafficApp",
            path: "Sources/HotspotTrafficApp",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)

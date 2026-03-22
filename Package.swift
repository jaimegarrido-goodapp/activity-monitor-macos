// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ActivityMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ActivityMonitor",
            // SPM includes all .swift files under this path recursively.
            path: "ActivityMonitor"
        )
    ]
)

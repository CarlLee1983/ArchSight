// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArchSightMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ArchSight", targets: ["ArchSightApp"]),
        .library(name: "ArchSightKit", targets: ["ArchSightKit"])
    ],
    targets: [
        .target(
            name: "ArchSightKit",
            path: "Sources/ArchSightKit"
        ),
        .executableTarget(
            name: "ArchSightApp",
            dependencies: ["ArchSightKit"],
            path: "Sources/ArchSightApp"
        ),
        .testTarget(
            name: "ArchSightKitTests",
            dependencies: ["ArchSightKit", "ArchSightApp"],
            path: "Tests/ArchSightKitTests"
        )
    ]
)

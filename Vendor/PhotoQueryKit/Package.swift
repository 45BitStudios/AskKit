// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotoQueryKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PhotoQueryKit",
            targets: ["PhotoQueryKit"]
        )
    ],
    targets: [
        .target(
            name: "PhotoQueryKit",
            dependencies: [],
            path: "Sources/PhotoQuery"
        ),
        .testTarget(
            name: "PhotoQueryTests",
            dependencies: ["PhotoQueryKit"],
            path: "Tests/PhotoQueryTests"
        )
    ]
)

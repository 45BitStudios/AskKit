// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AskKit",
    platforms: [
        .iOS(.v27)
    ],
    products: [
        .library(name: "AskKit", targets: ["AskKit"])
    ],
    targets: [
        .target(name: "AskKit"),
        .testTarget(name: "AskKitTests", dependencies: ["AskKit"])
    ],
    swiftLanguageModes: [.v6]
)

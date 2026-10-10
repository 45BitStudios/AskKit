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
    dependencies: [
        .package(path: "Vendor/VoiceGlowKit"),
        .package(path: "Vendor/ThinkingOrbsKit"),
        .package(path: "Vendor/BorderBeamKit")
    ],
    targets: [
        .target(
            name: "AskKit",
            dependencies: [
                .product(name: "VoiceGlowKit", package: "VoiceGlowKit"),
                .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit"),
                .product(name: "BorderBeamKit", package: "BorderBeamKit")
            ]
        ),
        .testTarget(name: "AskKitTests", dependencies: ["AskKit"]),
        .testTarget(name: "AskKitEvaluations", dependencies: ["AskKit"])
    ],
    swiftLanguageModes: [.v6]
)

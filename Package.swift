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
        .package(path: "Vendor/BorderBeamKit"),
        .package(path: "Vendor/PhotoQueryKit"),
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.5.0")
    ],
    targets: [
        .target(
            name: "AskKit",
            dependencies: [
                .product(name: "VoiceGlowKit", package: "VoiceGlowKit"),
                .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit"),
                .product(name: "BorderBeamKit", package: "BorderBeamKit"),
                .product(name: "PhotoQueryKit", package: "PhotoQueryKit"),
                .product(name: "Textual", package: "textual")
            ],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Contacts")
            ]
        ),
        .testTarget(name: "AskKitTests", dependencies: ["AskKit"]),
        .testTarget(name: "AskKitEvaluations", dependencies: ["AskKit"])
    ],
    swiftLanguageModes: [.v6]
)

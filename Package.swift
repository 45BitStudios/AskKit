// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AskKit",
    platforms: [
        .iOS(.v27)
    ],
    products: [
        .library(name: "AskKit", targets: ["AskKit"]),
        .library(name: "AskKitIntents", targets: ["AskKitIntents"])
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
            name: "AskContactsChangeHistory",
            dependencies: [],
            path: "Sources/AskContactsChangeHistory",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Contacts")
            ]
        ),
        .target(
            name: "AskKitIntents",
            dependencies: [],
            path: "Sources/AskKitIntents",
            linkerSettings: [
                .linkedFramework("ActivityKit"),
                .linkedFramework("AppIntents"),
                .linkedFramework("WidgetKit")
            ]
        ),
        .target(
            name: "AskKit",
            dependencies: [
                "AskKitIntents",
                "AskContactsChangeHistory",
                .product(name: "VoiceGlowKit", package: "VoiceGlowKit"),
                .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit"),
                .product(name: "BorderBeamKit", package: "BorderBeamKit"),
                .product(name: "PhotoQueryKit", package: "PhotoQueryKit"),
                .product(name: "Textual", package: "textual")
            ],
            linkerSettings: [
                .linkedFramework("Contacts")
            ]
        ),
        .testTarget(name: "AskKitTests", dependencies: ["AskKit", "AskKitIntents"]),
        .testTarget(name: "AskKitEvaluations", dependencies: ["AskKit"])
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.4

import PackageDescription

/// Foundation Models runs on these platforms. Apple TV and Apple Watch build without the model.
let foundationModels: [SwiftSetting] = [
    .define("ASK_FOUNDATION_MODELS", .when(platforms: [.iOS, .macOS, .macCatalyst, .visionOS]))
]

let package = Package(
    name: "AskKit",
    platforms: [
        .iOS(.v27),
        .macOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27)
    ],
    products: [
        /// The assistant: skills, routing, Apple sources, storage, and traces. No views.
        .library(name: "AskKit", targets: ["AskKit"]),
        /// The chat, the built-in cards, the card gallery, and the trace viewer.
        .library(name: "AskKitUI", targets: ["AskKitUI"]),
        /// App Intents: Ask, the answer snippet, and the intents the cards' buttons run.
        .library(name: "AskKitIntents", targets: ["AskKitIntents"]),
        /// What widgets and Live Activities read. Small enough for an extension.
        .library(name: "AskKitSurface", targets: ["AskKitSurface"])
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
                .linkedFramework("Contacts", .when(platforms: [.iOS, .macOS, .macCatalyst, .watchOS, .visionOS]))
            ]
        ),
        .target(
            name: "AskKitSurface",
            dependencies: [],
            path: "Sources/AskKitSurface"
        ),
        .target(
            name: "AskKit",
            dependencies: [
                "AskKitSurface",
                .target(name: "AskContactsChangeHistory", condition: .when(platforms: [.iOS, .macOS, .macCatalyst, .watchOS, .visionOS])),
                .product(name: "PhotoQueryKit", package: "PhotoQueryKit")
            ],
            swiftSettings: foundationModels
        ),
        .target(
            name: "AskKitIntents",
            dependencies: [
                "AskKit",
                "AskKitSurface"
            ],
            swiftSettings: foundationModels
        ),
        .target(
            name: "AskKitUI",
            dependencies: [
                "AskKit",
                "AskKitIntents",
                "AskKitSurface",
                .product(name: "VoiceGlowKit", package: "VoiceGlowKit"),
                .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit"),
                .product(name: "BorderBeamKit", package: "BorderBeamKit"),
                .product(name: "Textual", package: "textual")
            ],
            swiftSettings: foundationModels
        ),
        .testTarget(
            name: "AskKitTests",
            dependencies: ["AskKit", "AskKitUI", "AskKitIntents", "AskKitSurface"],
            swiftSettings: foundationModels
        ),
        .testTarget(name: "AskKitEvaluations", dependencies: ["AskKit"], swiftSettings: foundationModels)
    ],
    swiftLanguageModes: [.v6]
)

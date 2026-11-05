// swift-tools-version: 6.4

import PackageDescription

/// On-device Foundation Models. Apple Watch has no on-device model.
/// `AskOnDeviceResponder` can still call Private Cloud Compute on watchOS.
/// Apple's Private Cloud Compute type and entitlement omit tvOS, so this flag stays off there.
let foundationModels: [SwiftSetting] = [
    .define("ASK_FOUNDATION_MODELS", .when(platforms: [.iOS, .macOS, .macCatalyst, .visionOS]))
]

/// `SnippetRepresentableEntity` and `CardSnippet` shipped in the 27.3 SDK.
/// The bridge compiles on iOS, macOS, Mac Catalyst, tvOS, and visionOS.
/// watchOS does not build it. AskKitUI is already left out of that build, and the entity card follows it.
/// Xcode 27.2 does not have these symbols, so that SDK cannot compile AskEntitySnippetBridge.swift.
let entitySnippets: [SwiftSetting] = [
    .define("ASK_ENTITY_SNIPPETS", .when(platforms: [.iOS, .macOS, .macCatalyst, .tvOS, .visionOS]))
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
        /// App Intents: Ask, the answer snippet, entity cards, and the intents the cards' buttons run.
        .library(name: "AskKitIntents", targets: ["AskKitIntents"]),
        /// What widgets and Live Activities read. Small enough for an extension.
        .library(name: "AskKitSurface", targets: ["AskKitSurface"])
    ],
    dependencies: [
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
        // In-tree so a host can depend on AskKit. A path dependency cannot.
        // These kits were written as Swift 5 packages, so they stay in that language mode.
        .target(
            name: "PhotoQueryKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "VoiceGlowKit",
            resources: [.process("VoiceGlowShaders.metal")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ThinkingOrbsKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "BorderBeamKit",
            resources: [
                .copy("Resources/beam-spec.json"),
                .process("BeamShaders.metal")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "AskKit",
            dependencies: [
                "AskKitSurface",
                "PhotoQueryKit",
                .target(name: "AskContactsChangeHistory", condition: .when(platforms: [.iOS, .macOS, .macCatalyst, .watchOS, .visionOS]))
            ],
            swiftSettings: foundationModels
        ),
        .target(
            name: "AskKitIntents",
            dependencies: [
                "AskKit",
                "AskKitSurface"
            ],
            swiftSettings: foundationModels + entitySnippets
        ),
        // Compiled out on watchOS. The views use SwiftUI that watchOS does not provide.
        // Sources/AskKitUI/AskKitUIWatch.swift is the only file that builds there.
        .target(
            name: "AskKitUI",
            dependencies: [
                "AskKit",
                "AskKitIntents",
                "AskKitSurface",
                "VoiceGlowKit",
                "ThinkingOrbsKit",
                "BorderBeamKit",
                .product(name: "Textual", package: "textual")
            ],
            swiftSettings: foundationModels
        ),
        .testTarget(
            name: "AskKitTests",
            dependencies: ["AskKit", "AskKitUI", "AskKitIntents", "AskKitSurface", "PhotoQueryKit"],
            swiftSettings: foundationModels + entitySnippets
        ),
        .testTarget(name: "AskKitEvaluations", dependencies: ["AskKit"], swiftSettings: foundationModels)
    ],
    swiftLanguageModes: [.v6]
)

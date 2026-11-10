import Foundation
import Testing
@testable import AskKit

@Suite("Generated card hardening")
struct AskCardHardeningTests {
    @Test func decodeAndSanitizeDropUnsafeNodes() throws {
        let json = """
        {"kind":"vstack","text":"","detail":"","actionID":"","children":[
          {"kind":"mystery","text":"nope","detail":"","actionID":"","children":[]},
          {"kind":" STAT ","text":"72°","detail":"","actionID":"","children":[]},
          {"kind":"symbol","text":"not-a-symbol","detail":"","actionID":"","children":[]},
          {"kind":"symbol","text":"heart.fill","detail":"","actionID":"","children":[]},
          {"kind":"action","text":"Open","detail":"","actionID":"open","children":[]},
          {"kind":"action","text":"Nope","detail":"","actionID":"missing","children":[]}
        ]}
        """
        let sanitized = try #require(pipeline(json, allowed: ["open"]))
        #expect(sanitized.children.map(\.kind) == ["stat", "symbol", "action"])
        #expect(sanitized.children.map(\.text) == ["72°", "heart.fill", "Open"])
        #expect(sanitized.children.map(\.actionID) == ["", "", "open"])
    }

    @Test func depthPastThreeIsDroppedAndDepthThreeStays() throws {
        let kept = try #require(AskGeneratedCard.sanitize(wrapped(3, AskCardNode(kind: "text", text: "shallow"))))
        #expect(contains(kept, text: "shallow"))
        #expect(AskGeneratedCard.sanitize(wrapped(4, AskCardNode(kind: "text", text: "too deep"))) == nil)
    }

    @Test func moreThanTwentyFourNodesKeepsTheFirstBudget() throws {
        let root = AskCardNode(
            kind: "vstack",
            children: (0..<40).map { AskCardNode(kind: "text", text: "\($0)") }
        )
        let sanitized = try #require(AskGeneratedCard.sanitize(root))
        #expect(sanitized.children.count == AskGeneratedCard.maxNodes - 1)
        #expect(sanitized.children.map(\.text) == (0..<23).map { "\($0)" })
    }

    @Test func hugeStringsControlCharactersAndBidiAreClamped() throws {
        let long = String(repeating: "b", count: AskGeneratedCard.maxTextLength + 300)
        let huge = try #require(AskGeneratedCard.sanitize(AskCardNode(kind: "text", text: long)))
        #expect(huge.text.count == AskGeneratedCard.maxTextLength)
        #expect(huge.text == String(repeating: "b", count: AskGeneratedCard.maxTextLength))

        let dirty = try #require(AskGeneratedCard.sanitize(
            AskCardNode(kind: "stat", text: "\u{0000}72°\u{0007}", detail: "\u{202E}High")
        ))
        #expect(dirty.text == "72°")
        #expect(dirty.detail == "High")
        #expect(AskGeneratedCard.sanitize(AskCardNode(kind: "text", text: "\u{0000}\u{202E}")) == nil)

        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let emoji = try #require(AskGeneratedCard.sanitize(AskCardNode(kind: "text", text: family)))
        #expect(emoji.text == family)

        let lines = try #require(AskGeneratedCard.sanitize(
            AskCardNode(kind: "text", text: "one\ntwo", detail: "\tkept")
        ))
        #expect(lines.text == "one\ntwo")
    }

    @Test func malformedAndOversizedPayloadsDecodeToNil() {
        #expect(AskGeneratedCard.decode("") == nil)
        #expect(AskGeneratedCard.decode("{") == nil)
        #expect(AskGeneratedCard.decode("null") == nil)
        #expect(AskGeneratedCard.decode("[]") == nil)
        #expect(AskGeneratedCard.decode("\"text\"") == nil)
        let huge = String(repeating: "a", count: AskGeneratedCard.maxEncodedLength)
        let json = "{\"kind\":\"text\",\"text\":\"\(huge)\",\"detail\":\"\",\"actionID\":\"\",\"children\":[]}"
        #expect(json.count > AskGeneratedCard.maxEncodedLength)
        #expect(AskGeneratedCard.decode(json) == nil)
    }

    @Test func partialJSONAndADeepChainStaySafe() throws {
        let partial = try #require(AskGeneratedCard.decode("{\"kind\":\"text\",\"text\":\"Hi\"}"))
        let sanitized = try #require(AskGeneratedCard.sanitize(partial))
        #expect(sanitized.kind == "text")
        #expect(sanitized.text == "Hi")
        #expect(sanitized.children.isEmpty)

        var json = "{\"kind\":\"text\",\"text\":\"leaf\",\"detail\":\"\",\"actionID\":\"\",\"children\":[]}"
        for _ in 0..<30 {
            json = "{\"kind\":\"vstack\",\"text\":\"\",\"detail\":\"\",\"actionID\":\"\",\"children\":[\(json)]}"
        }
        let decoded = try #require(AskGeneratedCard.decode(json))
        #expect(depth(decoded) <= AskGeneratedCard.maxParseDepth)
        #expect(AskGeneratedCard.sanitize(decoded) == nil)
    }

    @Test func encodeStillRoundTripsAFactTree() throws {
        let root = AskGeneratedCard.factTree(title: "Range", value: "210 mi", detail: "Eco on")
        let decoded = try #require(AskGeneratedCard.decode(AskGeneratedCard.encode(root)))
        #expect(decoded == root)
    }

    @Test @MainActor func emptyTreeFallsBackAndAnActionOnlyTreeIsNotABlankStat() throws {
        let empty = AskGeneratedCard.card(
            title: "Hours",
            spoken: "The desk opens at 8.",
            facts: "8 a.m.",
            root: AskCardNode(kind: "vstack")
        )
        #expect(empty.shareText.contains("8 a.m."))
        #expect(empty.generatedRoot?.kind == "vstack")

        let onlyAction = AskGeneratedCard.card(
            title: "Hours",
            spoken: "The desk opens at 8.",
            allowedActions: [AskAction(id: "open", title: "Open")],
            root: AskCardNode(kind: "vstack", children: [
                AskCardNode(kind: "action", text: "Open", actionID: "open")
            ])
        )
        #expect(onlyAction.action?.title == "Open")
        let display = try #require(generatedDisplay(onlyAction))
        #expect(display.kind == "spacer")
        #expect(display.text != " ")

        let withText = AskGeneratedCard.card(
            title: "Hours",
            spoken: "The desk opens at 8.",
            allowedActions: [AskAction(id: "open", title: "Open")],
            root: AskCardNode(kind: "vstack", children: [
                AskCardNode(kind: "text", text: "Desk opens"),
                AskCardNode(kind: "action", text: "Open", actionID: "open")
            ])
        )
        let kept = try #require(generatedDisplay(withText))
        #expect(kept.children.map(\.kind) == ["text"])
        #expect(kept.children.map(\.text) == ["Desk opens"])
    }

    @Test func accessibilityLabelsNameTheValueAndTheCaption() {
        #expect(AskGeneratedCardAccessibility.stat(text: "72°", detail: "Partly cloudy") == "72°, Partly cloudy")
        #expect(AskGeneratedCardAccessibility.stat(text: "72°", detail: "") == "72°")
        #expect(AskGeneratedCardAccessibility.figure(text: "78°", detail: "High") == "High: 78°")
        #expect(AskGeneratedCardAccessibility.figure(text: "78°", detail: "  ") == "78°")
        #expect(AskGeneratedCardAccessibility.row(text: "Range", detail: "210 mi") == "Range, 210 mi")
        #expect(AskGeneratedCardAccessibility.badge("Weather", title: "Forecast") == "Weather")
        #expect(AskGeneratedCardAccessibility.badge("  ", title: "Forecast") == "Forecast")
        #expect(AskGeneratedCardAccessibility.badge("", title: "") == "Card")
        #expect(AskGeneratedCardAccessibility.action("Trip") == "Trip")
        #expect(AskGeneratedCardAccessibility.action("  ") == "Action")
        for label in [
            AskGeneratedCardAccessibility.stat(text: "8,420", detail: "Steps"),
            AskGeneratedCardAccessibility.figure(text: "3.2 mi", detail: "Distance"),
            AskGeneratedCardAccessibility.badge("Steps", title: ""),
            AskGeneratedCardAccessibility.action("Activity")
        ] {
            #expect(!label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    #if !os(watchOS)
    @Test func theRendererUsesThoseLabelsAndScalesTheHero() throws {
        let view = try sourceText("AskGeneratedCardView.swift", in: "AskKitUI")
        #expect(view.contains("AskGeneratedCardAccessibility.stat"))
        #expect(view.contains("AskGeneratedCardAccessibility.figure"))
        #expect(view.contains("AskGeneratedCardAccessibility.badge"))
        #expect(view.contains("AskGeneratedCardAccessibility.row"))
        #expect(view.contains("AskCardScaledFont"))
        #expect(view.contains("ScaledMetric"))
        let chat = try sourceText("AskChatView.swift", in: "AskKitUI")
        #expect(chat.contains("AskGeneratedCardAccessibility.action"))
    }
    #endif

    @Test func dynamicTypeMetricsKeepTheDefaultSizesAndChatDoesNotClip() {
        #expect(AskCardStyle.snippet.displayMetric.base == 34)
        #expect(AskCardStyle.chat.displayMetric.base == 44)
        #expect(AskCardStyle.fullScreen.displayMetric.base == 64)
        #expect(AskCardStyle.snippet.displayMetric.relativeTo == .title)
        #expect(AskCardStyle.chat.displayMetric.relativeTo == .largeTitle)
        #expect(AskCardStyle.fullScreen.displayMetric.relativeTo == .largeTitle)
        for style in AskCardStyle.allCases {
            #expect(style.heroMetric.base == style.heroSymbol)
            #expect(style.miniMetric.base == style.miniSymbol)
            #expect(style.plateMetric.base == style.plateSize)
            #expect(style.displayMetric.base > 0)
        }
        #expect(AskCardStyle.chat.detailLineLimit == nil)
        #expect(AskCardStyle.fullScreen.detailLineLimit == nil)
        #expect(AskCardStyle.snippet.detailLineLimit == 1)
    }

    /// Records a duration. A slow machine still passes. There is no upper bound.
    @Test func compositionMeasurementRecordsDurationWithoutADeadline() async throws {
        let model = ScriptedCardModel()
        model.composeResult = AskCardNode(kind: "stat", text: "72°")
        let request = AskModelRequest(instructions: "Compose.", prompt: "72°")
        let measured = await AskCardComposeMeter.measure {
            try await model.client.composeCard(request)
        }
        #expect(measured.measurement.succeeded)
        #expect(measured.value?.text == "72°")
        #expect(measured.measurement.duration >= .zero)

        let failed: AskCardMeasureResult<AskCardNode> = await AskCardComposeMeter.measure {
            throw AskCardComposeError.unavailable
        }
        #expect(!failed.measurement.succeeded)
        #expect(failed.value == nil)
        #expect(failed.measurement.duration >= .zero)
    }

    private func pipeline(_ json: String, allowed: Set<String>) -> AskCardNode? {
        guard let decoded = AskGeneratedCard.decode(json) else { return nil }
        return AskGeneratedCard.sanitize(decoded, allowedActionIDs: allowed)
    }

    private func wrapped(_ levels: Int, _ leaf: AskCardNode) -> AskCardNode {
        var node = leaf
        for _ in 0..<levels {
            node = AskCardNode(kind: "vstack", children: [node])
        }
        return node
    }

    private func contains(_ node: AskCardNode, text: String) -> Bool {
        if node.text == text { return true }
        return node.children.contains { contains($0, text: text) }
    }

    private func depth(_ node: AskCardNode) -> Int {
        node.children.map { depth($0) + 1 }.max() ?? 0
    }

    private func generatedDisplay(_ card: AskIntentCard) -> AskCardNode? {
        guard case .builtIn(let built) = card.content, case .generated(let root, _) = built else {
            return nil
        }
        return root
    }

    private func sourceText(_ name: String, in folder: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root
                .appendingPathComponent("Sources")
                .appendingPathComponent(folder)
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }
}

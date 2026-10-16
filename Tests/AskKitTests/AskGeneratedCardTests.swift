import XCTest
@testable import AskKit

final class AskGeneratedCardTests: XCTestCase {
    func testFactTreeUsesStatBadgeAndDetail() {
        let root = AskGeneratedCard.factTree(
            title: "Charge",
            value: "68 percent",
            detail: "About 40 minutes to the limit."
        )
        XCTAssertEqual(AskCardNodeKind.parse(root.kind), .vstack)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(AskCardNodeKind.parse(root.children[0].kind), .hstack)
        let headline = root.children[0].children
        XCTAssertEqual(headline.map { AskCardNodeKind.parse($0.kind) }, [.stat, .badge])
        XCTAssertEqual(headline[0].text, "68 percent")
        XCTAssertEqual(headline[1].text, "Charge")
        XCTAssertEqual(AskCardNodeKind.parse(root.children[1].kind), .text)
        XCTAssertEqual(root.children[1].text, "About 40 minutes to the limit.")
        XCTAssertEqual(
            AskGeneratedCard.outline(root),
            """
            vstack
              hstack
                stat · 68 percent
                badge · Charge
              text · About 40 minutes to the limit.
            """
        )
    }

    func testSanitizeDropsUnknownKindsAndCapsDepth() throws {
        let deep = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "text", text: "shallow"),
                AskCardNode(
                    kind: "vstack",
                    children: [
                        AskCardNode(
                            kind: "vstack",
                            children: [
                                AskCardNode(
                                    kind: "vstack",
                                    children: [
                                        AskCardNode(
                                            kind: "vstack",
                                            children: [AskCardNode(kind: "text", text: "too deep")]
                                        )
                                    ]
                                )
                            ]
                        )
                    ]
                ),
                AskCardNode(kind: "mystery", text: "nope"),
                AskCardNode(kind: "text", text: "kept")
            ]
        )
        let sanitized = try XCTUnwrap(AskGeneratedCard.sanitize(deep))
        XCTAssertEqual(AskCardNodeKind.parse(sanitized.kind), .vstack)
        XCTAssertEqual(sanitized.children.map(\.text), ["shallow", "kept"])
    }

    func testShareTextIncludesFiguresAndSkipsSymbols() {
        let root = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "figure", text: "78°", detail: "High"),
                AskCardNode(kind: "quote", text: "I give myself permission to do what is right for me."),
                AskCardNode(kind: "symbol", text: "cloud.sun.fill")
            ]
        )
        let text = AskGeneratedCard.shareText(in: root)
        XCTAssertTrue(text.contains("High: 78°"))
        XCTAssertTrue(text.contains("I give myself permission to do what is right for me."))
        XCTAssertFalse(text.contains("cloud.sun"))
    }

    func testSanitizeKeepsOneResolvedSymbol() throws {
        let root = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "symbol", text: "not-a-symbol"),
                AskCardNode(kind: "symbol", text: "Weather"),
                AskCardNode(kind: "symbol", text: "heart.fill"),
                AskCardNode(kind: "figure", text: "72°", detail: "High"),
                AskCardNode(kind: "quote", text: "A short note.")
            ]
        )
        let sanitized = try XCTUnwrap(AskGeneratedCard.sanitize(root))
        XCTAssertEqual(sanitized.children.map(\.kind), ["symbol", "symbol", "figure", "quote"])
        XCTAssertEqual(sanitized.children[0].text, "Weather")
        XCTAssertEqual(sanitized.children[1].text, "heart.fill")
        XCTAssertEqual(AskCardSymbol.systemName(for: "Weather"), "cloud.sun.fill")
        XCTAssertNil(AskCardSymbol.systemName(for: "not-a-symbol"))
        XCTAssertEqual(sanitized.children[3].detail, "")
    }

    func testGallerySamplesStayWithinTheNodeBudget() {
        XCTAssertEqual(AskGeneratedCard.gallerySamples.map(\.title), [
            "Next drive", "Agenda", "Forecast", "Steps", "Reminders", "Now playing", "Note"
        ])
        for sample in AskGeneratedCard.gallerySamples {
            let sanitized = AskGeneratedCard.sanitize(sample.root)
            XCTAssertEqual(sanitized, sample.root, sample.title)
            XCTAssertLessThanOrEqual(nodeCount(sample.root), AskGeneratedCard.maxNodes, sample.title)
            XCTAssertLessThanOrEqual(leafDepth(sample.root), AskGeneratedCard.maxDepth, sample.title)
        }
        let kinds = Set(AskGeneratedCard.gallerySamples.flatMap { flatKinds($0.root) })
        XCTAssertTrue(kinds.isSuperset(of: ["plate", "symbol", "eyebrow", "stat", "figure", "quote"]))
        XCTAssertLessThanOrEqual(nodeCount(AskGeneratedCard.forecastSample), AskGeneratedCard.maxNodes)
    }

    func testSanitizeKeepsOnlyAllowedActions() throws {
        let root = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "stat", text: "80%"),
                AskCardNode(kind: "action", text: "Open", actionID: "open"),
                AskCardNode(kind: "action", text: "Nope", actionID: "missing")
            ]
        )
        let sanitized = try XCTUnwrap(
            AskGeneratedCard.sanitize(root, allowedActionIDs: ["open"])
        )
        let actions = AskGeneratedCard.actions(
            in: sanitized,
            allowed: [
                AskAction(id: "open", title: "Open"),
                AskAction(id: "other", title: "Other")
            ]
        )
        XCTAssertEqual(actions.map(\.id), ["open"])
        XCTAssertEqual(actions.map(\.title), ["Open"])
    }

    func testEncodeDecodeRoundTrip() throws {
        let root = AskGeneratedCard.factTree(title: "Range", value: "210 mi", detail: "Eco on")
        let json = AskGeneratedCard.encode(root)
        XCTAssertFalse(json.isEmpty)
        let decoded = try XCTUnwrap(AskGeneratedCard.decode(json))
        XCTAssertEqual(decoded, root)
    }

    @MainActor
    func testCardExtractsActionAndStoresGeneratedRoot() {
        let root = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "stat", text: "8 a.m."),
                AskCardNode(kind: "text", text: "Desk opens"),
                AskCardNode(kind: "action", text: "Hours", actionID: "hours")
            ]
        )
        let card = AskGeneratedCard.card(
            title: "Hours",
            spoken: "The desk opens at 8 a.m.",
            coveredPhrases: ["8 a.m."],
            allowedActions: [AskAction(id: "hours", title: "Hours")],
            root: root
        )
        XCTAssertEqual(card.action?.id, "hours")
        XCTAssertEqual(card.generatedRoot?.children.count, 3)
        XCTAssertTrue(card.expands)
        XCTAssertTrue(card.shareText.contains("8 a.m."))
    }

    @MainActor
    func testFallbackWhenComposeFails() async throws {
        let model = ScriptedCardModel()
        model.composeError = AskCardComposeError.unavailable
        model.replyText = "Next drive at 5 p.m."
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "DSL",
                persistence: .memory,
                domains: [AskDomain(id: "trip", summary: "Trip", routingNotes: "Trip")],
                skills: [
                    AskSkill(
                        id: "nextDrive",
                        domainID: "trip",
                        title: "Next drive",
                        summary: "When the next drive leaves",
                        routingNotes: "Next drive.",
                        fulfillment: .generated { _ in
                            AskGeneratedBlueprint(
                                title: "Next drive",
                                spoken: "Your next drive is at 5 p.m.",
                                facts: "The next drive is at 5 p.m.",
                                actions: [AskAction(id: "nextDrive", title: "Trip")]
                            )
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "nextDrive") },
                guide: AskGuide(replyInstructions: "Rewrite FACTS.", followUpInstructions: "")
            ),
            model: model.client
        )
        let result = await assistant.handle(utterance: "when is my next drive?")
        XCTAssertEqual(model.composeCalls, 1)
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected a generated card")
        }
        XCTAssertNotNil(card.generatedRoot)
        XCTAssertEqual(card.action?.id, "nextDrive")
        XCTAssertTrue(card.shareText.contains("5 p.m.") || card.spoken.contains("5 p.m."))

        let turns = try assistant.transcript()
        let saved = try XCTUnwrap(turns.last { $0.role == "assistant" })
        let restored = await assistant.pages(for: saved.id)
        XCTAssertEqual(restored.count, 1)
        XCTAssertNotNil(restored[0].card?.generatedRoot)
        XCTAssertEqual(restored[0].card?.action?.id, "nextDrive")
    }

    @MainActor
    func testPrebuiltRootSkipsCompose() async throws {
        let model = ScriptedCardModel()
        model.replyText = "Limit is 80 percent."
        let tree = AskGeneratedCard.factTree(title: "Limit", value: "80 percent", detail: "Stops here")
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "DSL",
                persistence: .memory,
                domains: [AskDomain(id: "battery", summary: "Battery", routingNotes: "Battery")],
                skills: [
                    AskSkill(
                        id: "limit",
                        domainID: "battery",
                        title: "Charge limit",
                        summary: "Charge limit",
                        routingNotes: "Limit.",
                        fulfillment: .generated { _ in
                            AskGeneratedBlueprint(
                                title: "Limit",
                                spoken: "The charge limit is 80 percent.",
                                facts: "The charge limit is 80 percent.",
                                coveredPhrases: ["80 percent"],
                                actions: [AskAction(id: "limit", title: "Limit")],
                                root: tree
                            )
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "limit") },
                guide: AskGuide(replyInstructions: "Rewrite FACTS.", followUpInstructions: "")
            ),
            model: model.client
        )
        let result = await assistant.handle(utterance: "what is the charge limit?")
        XCTAssertEqual(model.composeCalls, 0)
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected a generated card")
        }
        XCTAssertEqual(card.generatedRoot, tree)
    }

    @MainActor
    func testAppleFactCardUsesGeneratedRoot() {
        let card = AskAppleCards.make(
            AskAppleReading(name: "skill", lines: ["68 percent", "About 40 minutes to the limit."]),
            spoken: "68 percent",
            custom: nil
        )
        XCTAssertNotNil(card.generatedRoot)
        XCTAssertEqual(AskCardNodeKind.parse(card.generatedRoot?.kind ?? ""), .vstack)
        XCTAssertTrue(card.expands)
    }

    func testCardSpecialistAppendsAppInstructions() {
        let specialist = AskCardSpecialist(
            instructions: .append("Prefer a large stat for the main number.")
        )
        let text = AskGeneratedCard.composeInstructions(
            specialist: specialist,
            allowedActions: [AskAction(id: "trip", title: "Trip")],
            layoutNotes: "Show range under the departure time."
        )
        XCTAssertTrue(text.contains("CARD DSL"))
        XCTAssertTrue(text.contains("figure"))
        XCTAssertTrue(text.contains("quote"))
        XCTAssertTrue(text.contains("plate"))
        XCTAssertTrue(text.contains("eyebrow"))
        XCTAssertTrue(text.contains("symbol"))
        XCTAssertTrue(text.contains("Prefer a large stat for the main number."))
        XCTAssertTrue(text.contains("LAYOUT"))
        XCTAssertTrue(text.contains("Show range under the departure time."))
        XCTAssertTrue(text.contains("trip=Trip"))
    }

    func testCardSpecialistReplaceDropsBuiltinLibrary() {
        let specialist = AskCardSpecialist(
            instructions: .replace("Only use a single stat node.")
        )
        let text = AskGeneratedCard.composeInstructions(
            specialist: specialist,
            allowedActions: []
        )
        XCTAssertFalse(text.contains("CARD DSL"))
        XCTAssertTrue(text.contains("Only use a single stat node."))
        XCTAssertTrue(text.contains("ALLOWED"))
    }

    @MainActor
    func testComposeUsesCardSpecialistProfile() async throws {
        let model = ScriptedCardModel()
        model.composeError = AskCardComposeError.unavailable
        model.replyText = "Next drive at 5 p.m."
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "DSL",
                persistence: .memory,
                domains: [AskDomain(id: "trip", summary: "Trip", routingNotes: "Trip")],
                skills: [
                    AskSkill(
                        id: "nextDrive",
                        domainID: "trip",
                        title: "Next drive",
                        summary: "When the next drive leaves",
                        routingNotes: "Next drive.",
                        fulfillment: .generated { _ in
                            AskGeneratedBlueprint(
                                title: "Next drive",
                                spoken: "Your next drive is at 5 p.m.",
                                facts: "The next drive is at 5 p.m.",
                                actions: [AskAction(id: "nextDrive", title: "Trip")],
                                layoutNotes: "Badge says Trip."
                            )
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "nextDrive") },
                guide: AskGuide(replyInstructions: "Rewrite FACTS.", followUpInstructions: ""),
                cardSpecialist: AskCardSpecialist(
                    id: "app.card",
                    title: "App card",
                    symbolName: "square.grid.2x2",
                    workingTitle: "Building the card",
                    instructions: .append("Keep one primary stat.")
                )
            ),
            model: model.client
        )
        _ = await assistant.handle(utterance: "when is my next drive?")
        XCTAssertEqual(model.composeCalls, 1)
        let request = try XCTUnwrap(model.composeRequests.last)
        XCTAssertEqual(request.profileID, "app.card")
        XCTAssertEqual(request.profileTitle, "App card")
        XCTAssertEqual(request.workingTitle, "Building the card")
        XCTAssertEqual(request.symbolName, "square.grid.2x2")
        XCTAssertTrue(request.instructions.contains("Keep one primary stat."))
        XCTAssertTrue(request.instructions.contains("Badge says Trip."))
    }

    @MainActor
    func testScenarioComposeUsesTheModel() async throws {
        let model = ScriptedCardModel()
        model.composeResult = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "stat", text: "7:30 a.m."),
                AskCardNode(kind: "badge", text: "Next drive"),
                AskCardNode(kind: "text", text: "About 214 miles")
            ]
        )
        let assistant = try scenarioAssistant(model: model, specialist: AskCardSpecialist(
            id: "garage.card",
            title: "Garage card",
            symbolName: "car.side",
            instructions: .append("Prefer a large stat.")
        ))
        let composed = await assistant.composeCard(from: AskGeneratedBlueprint(
            title: "Next drive",
            spoken: "Your next drive is at 7:30 a.m.",
            facts: "7:30 a.m.\nNext drive\nAbout 214 miles",
            actions: [AskAction(id: "trip", title: "Trip")],
            layoutNotes: "Badge says Next drive."
        ))
        XCTAssertEqual(composed.layout, .model)
        XCTAssertEqual(composed.layout.sentence, "The model composed the card layout.")
        XCTAssertEqual(model.composeCalls, 1)
        XCTAssertEqual(model.replyCalls, 0)
        let request = try XCTUnwrap(model.composeRequests.last)
        XCTAssertEqual(request.profileID, "garage.card")
        XCTAssertTrue(request.instructions.contains("Prefer a large stat."))
        XCTAssertTrue(request.instructions.contains("Badge says Next drive."))
        XCTAssertEqual(composed.card.generatedRoot?.children.map(\.text), ["7:30 a.m.", "Next drive", "About 214 miles"])
        XCTAssertEqual(AskTraceFormatter.entryWords(.toolkit), "Card toolkit")
        XCTAssertEqual(AskTraceFormatter.entrySymbol(.toolkit), "rectangle.3.group")
        XCTAssertNotEqual(AskTraceEntry.toolkit, AskTraceEntry.siri)
    }

    @MainActor
    func testScenarioComposeFallsBackToFacts() async throws {
        let model = ScriptedCardModel()
        model.composeError = AskCardComposeError.unavailable
        let assistant = try scenarioAssistant(model: model, specialist: .default)
        let composed = await assistant.composeCard(from: AskGeneratedBlueprint(
            title: "Battery",
            spoken: "The battery is at 68 percent.",
            facts: "68 percent\nAbout 40 minutes until 80 percent.",
            actions: [AskAction(id: "charge", title: "Charge")]
        ))
        XCTAssertEqual(composed.layout, .facts)
        XCTAssertEqual(model.composeCalls, 1)
        XCTAssertEqual(composed.card.action?.id, "charge")
        XCTAssertNotNil(composed.card.generatedRoot)
        XCTAssertTrue(composed.card.shareText.contains("68 percent"))
    }

    @MainActor
    func testScenarioWithRootSkipsTheModel() async throws {
        let model = ScriptedCardModel()
        let tree = AskGeneratedCard.factTree(title: "Next drive", value: "7:30 a.m.", detail: "About 214 miles")
        let assistant = try scenarioAssistant(model: model, specialist: .default)
        let composed = await assistant.composeCard(from: AskGeneratedBlueprint(
            title: "Next drive",
            spoken: "Your next drive is at 7:30 a.m.",
            facts: "7:30 a.m.\nAbout 214 miles",
            actions: [AskAction(id: "trip", title: "Trip")],
            root: tree
        ))
        XCTAssertEqual(composed.layout, .skill)
        XCTAssertEqual(model.composeCalls, 0)
        XCTAssertEqual(composed.card.generatedRoot, tree)
    }

    @MainActor
    private func scenarioAssistant(
        model: ScriptedCardModel,
        specialist: AskCardSpecialist
    ) throws -> AskAssistant {
        try AskAssistant(
            AskConfiguration(
                assistantName: "Toolkit",
                persistence: .memory,
                domains: [AskDomain(id: "trip", summary: "Trip", routingNotes: "Trip")],
                skills: [],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in nil },
                guide: AskGuide(replyInstructions: "", followUpInstructions: ""),
                cardSpecialist: specialist
            ),
            model: model.client
        )
    }

    private func nodeCount(_ node: AskCardNode) -> Int {
        1 + node.children.map(nodeCount).reduce(0, +)
    }

    private func leafDepth(_ node: AskCardNode, depth: Int = 0) -> Int {
        node.children.map { leafDepth($0, depth: depth + 1) }.max() ?? depth
    }

    private func flatKinds(_ node: AskCardNode) -> [String] {
        [node.kind] + node.children.flatMap(flatKinds)
    }
}

/// Minimal scripted client for generative-card tests.
final class ScriptedCardModel: @unchecked Sendable {
    var domainResult = "trip"
    var skillResult = AskModelSkillChoice(skillID: "nextDrive")
    var replyText = ""
    var composeError: Error?
    var composeResult: AskCardNode?
    var composeCalls = 0
    var replyCalls = 0
    var composeRequests: [AskModelRequest] = []

    var client: AskModelClient {
        AskModelClient(
            routeDomain: { [self] _ in self.domainResult },
            routeSkill: { [self] _ in self.skillResult },
            fillSlots: { _, _ in [:] },
            route: { [self] _ in self.skillResult },
            writeReply: { [self] _ in
                self.replyCalls += 1
                return self.replyText
            },
            offerFollowUp: { _ in AskFollowUp(skillID: "none", question: "") },
            composeCard: { [self] request in
                self.composeCalls += 1
                self.composeRequests.append(request)
                if let composeError = self.composeError { throw composeError }
                if let composeResult = self.composeResult { return composeResult }
                throw AskCardComposeError.unavailable
            }
        )
    }
}

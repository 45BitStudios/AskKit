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
    }

    func testSanitizeDropsUnknownKindsAndCapsDepth() {
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

    func testSanitizeKeepsOnlyAllowedActions() {
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
        let model = ScriptedModel()
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
        let model = ScriptedModel()
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
}

/// Minimal scripted client for generative-card tests.
final class ScriptedModel {
    var domainResult = "trip"
    var skillResult = AskModelSkillChoice(skillID: "nextDrive")
    var replyText = ""
    var composeError: Error?
    var composeResult: AskCardNode?
    var composeCalls = 0
    var replyCalls = 0

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
            composeCard: { [self] _ in
                self.composeCalls += 1
                if let composeError = self.composeError { throw composeError }
                if let composeResult = self.composeResult { return composeResult }
                throw AskCardComposeError.unavailable
            }
        )
    }
}

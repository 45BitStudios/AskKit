import AskKit
import FoundationModels
import SwiftData
import SwiftUI
import XCTest

@MainActor
final class AskAssistantTests: XCTestCase {
    func testChipDoesNotCallTheModel() async throws {
        let model = ScriptedModel()
        let assistant = try makeAssistant(model: model.client)
        let result = await assistant.handle(
            chip: AskChip(id: "dinner", skillID: "dinner", title: "What's for dinner?", slots: [:])
        )
        XCTAssertEqual(model.domainCalls, 0)
        XCTAssertEqual(model.skillCalls, 0)
        XCTAssertTrue(model.fillCounts.isEmpty)
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.spoken, "Pasta.")
        XCTAssertFalse(result.usedModel)
    }

    func testTwelveSkillsLeaveTheRouterWithoutTools() async throws {
        let model = ScriptedModel()
        model.domainResult = "desk"
        model.skillResult = AskModelSkillChoice(skillID: "s0")
        let lookups = Counter()
        let skills = (0..<12).map { index in
            AskSkill(
                id: "s\(index)",
                domainID: "desk",
                title: "Skill \(index)",
                summary: "Skill \(index)",
                routingNotes: "Route here for \(index).",
                fulfillment: .reply { _ in AskReply(text: "ok", spoken: "ok") }
            )
        }
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Desk",
                domains: [AskDomain(id: "desk", summary: "Desk", routingNotes: "Desk questions.")],
                skills: skills,
                context: { AskContext() },
                chips: { _ in [] },
                tools: { _ in
                    lookups.value += 1
                    return (0..<6).map { StubTool(name: "tool-\($0)") }
                }
            ),
            model: model.client
        )
        _ = await assistant.handle(utterance: "hello")
        XCTAssertEqual(AskSessionPolicy.routerToolCount, 0)
        XCTAssertEqual(model.domainCalls, 1)
        XCTAssertEqual(model.skillCalls, 1)
        XCTAssertTrue(model.fillCounts.isEmpty)
        XCTAssertEqual(lookups.value, 0)
        XCTAssertFalse(model.requests[0].instructions.contains("s11"))
        XCTAssertTrue(model.requests[1].instructions.contains("s11"))
    }

    func testSixToolsAreRejectedAndTheHandlerStillRuns() async throws {
        let model = ScriptedModel()
        model.domainResult = "desk"
        model.skillResult = AskModelSkillChoice(skillID: "lookup")
        let counter = Counter()
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Desk",
                domains: [AskDomain(id: "desk", summary: "Desk", routingNotes: "Desk.")],
                skills: [
                    AskSkill(
                        id: "lookup",
                        domainID: "desk",
                        title: "Lookup",
                        summary: "Look something up",
                        requiredSlots: ["city"],
                        routingNotes: "Needs a city.",
                        fulfillment: .reply { invocation in
                            counter.handlerRan = true
                            return AskReply(text: invocation.slots["city"] ?? "missing", spoken: "missing")
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                tools: { _ in
                    counter.value += 1
                    return (0..<6).map { StubTool(name: "tool-\($0)") }
                }
            ),
            model: model.client
        )
        let result = await assistant.handle(utterance: "look it up")
        XCTAssertEqual(counter.value, 1)
        XCTAssertTrue(model.fillCounts.isEmpty)
        XCTAssertNil(AskSessionPolicy.acceptedSkillToolCount(6))
        XCTAssertTrue(counter.handlerRan)
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.spoken, "missing")
    }

    func testUnknownModelIdUsesTheUnknownSkill() async throws {
        let model = ScriptedModel()
        model.domainResult = "nope"
        let assistant = try makeAssistant(
            model: model.client,
            extraSkills: [
                AskSkill(
                    id: "unknown",
                    domainID: "other",
                    title: "Unknown",
                    summary: "Anything else",
                    routingNotes: "Unrelated questions.",
                    fulfillment: .reply { _ in
                        AskReply(text: "Help is open.", spoken: "Help is open.")
                    }
                )
            ]
        )
        let result = await assistant.handle(utterance: "Who won the game?")
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected the unknown skill")
        }
        XCTAssertEqual(result.skillID, "unknown")
        XCTAssertEqual(reply.spoken, "Help is open.")
        XCTAssertEqual(model.domainCalls, 1)
    }

    func testIntentSkillDoesNotBuildAskReplyText() async throws {
        let model = ScriptedModel()
        model.domainResult = "travel"
        model.skillResult = AskModelSkillChoice(skillID: "flightStatus")
        let replyBuilds = Counter()
        let assistant = try AskAssistant(
            sampleConfiguration(replyBuilds: replyBuilds),
            model: model.client
        )
        let result = await assistant.handle(utterance: "What's my flight status?")
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected the flight status card")
        }
        XCTAssertEqual(card.spoken, "On time")
        XCTAssertEqual(replyBuilds.value, 0)
        if case .stop(let stopped) = AskConversation().step(after: result) {
            XCTAssertEqual(stopped.skillID, "flightStatus")
        } else {
            XCTFail("An intent card ends the follow-up loop")
        }
    }

    func testStoredTurnIsTheNextFollowUp() async throws {
        let model = ScriptedModel()
        let assistant = try makeAssistant(model: model.client)
        _ = await assistant.handle(utterance: "pasta please")
        _ = await assistant.handle(utterance: "what about dinner")
        XCTAssertTrue(model.prompts.contains { $0.contains("pasta please") && $0.contains("what about dinner") })
    }

    func testOmittedSlotKeysAreDroppedFromTheStore() async throws {
        let seen = SlotBox()
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Pantry",
                domains: [AskDomain(id: "recipes", summary: "Cooking", routingNotes: "Food.")],
                skills: [
                    AskSkill(
                        id: "dinner",
                        domainID: "recipes",
                        title: "Dinner",
                        summary: "Suggest dinner",
                        routingNotes: "Dinner questions.",
                        fulfillment: .reply { invocation in
                            seen.slots = invocation.slots
                            return AskReply(text: "Pasta.", spoken: "Pasta.")
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in
                    AskRoute(skillID: "dinner", slots: ["city": "Austin", "recordLocator": "ABC123"])
                },
                omittedSlotKeys: ["recordLocator"]
            ),
            model: ScriptedModel().client
        )
        _ = await assistant.handle(utterance: "dinner")
        XCTAssertEqual(seen.slots["recordLocator"], "ABC123")
        XCTAssertEqual(seen.slots["city"], "Austin")
        let saved = try assistant.transcript().last { $0.role == "assistant" }
        XCTAssertFalse(saved?.slotsJSON.contains("ABC123") ?? true)
        XCTAssertTrue(saved?.slotsJSON.contains("Austin") ?? false)
    }

    func testSkillReceivesCurrentContextWithoutSendingPrivateValuesToTheModel() async throws {
        struct PantrySource: AskContextSource {
            func currentContext() async -> AskContext {
                AskContext(
                    promptBlock: "phase=cooking",
                    values: ["phase": "cooking", "userID": "42"]
                )
            }
        }
        let seen = SlotBox()
        let model = ScriptedModel()
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Pantry",
                domains: [AskDomain(id: "recipes", summary: "Cooking", routingNotes: "Food.")],
                skills: [
                    AskSkill(
                        id: "dinner",
                        domainID: "recipes",
                        title: "Dinner",
                        summary: "Suggest dinner",
                        contextKeys: ["phase"],
                        routingNotes: "Dinner questions.",
                        fulfillment: .reply { invocation in
                            seen.slots = invocation.context.values
                            let phase = invocation.context.value(for: "phase") ?? "none"
                            return AskReply(text: phase, spoken: phase)
                        }
                    )
                ],
                source: PantrySource(),
                chips: { context in
                    [AskChip(id: "c", skillID: "dinner", title: context.value(for: "phase") ?? "Dinner")]
                }
            ),
            model: model.client
        )
        let chips = await assistant.chips()
        XCTAssertEqual(chips.first?.title, "cooking")
        let result = await assistant.handle(utterance: "dinner please")
        XCTAssertEqual(seen.slots["phase"], "cooking")
        XCTAssertNil(seen.slots["userID"])
        XCTAssertTrue(model.prompts.allSatisfy { !$0.contains("userID") && !$0.contains("42") })
        XCTAssertTrue(model.prompts.contains { $0.contains("phase=cooking") })
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.spoken, "cooking")
    }

    func testPrivateCloudConfigurationUsesThePrivateDatabase() throws {
        let configuration = try XCTUnwrap(
            AskStoreBuilder.modelConfiguration(
                for: .privateCloud(containerIdentifier: "iCloud.com.example.ask", storeURL: nil)
            )
        )
        XCTAssertEqual(
            String(describing: configuration.cloudKitDatabase),
            String(describing: ModelConfiguration.CloudKitDatabase.private("iCloud.com.example.ask"))
        )
        XCTAssertFalse(configuration.isStoredInMemoryOnly)

        let local = try XCTUnwrap(AskStoreBuilder.modelConfiguration(for: .swiftData(storeURL: nil)))
        XCTAssertEqual(
            String(describing: local.cloudKitDatabase),
            String(describing: ModelConfiguration.CloudKitDatabase.none)
        )
        let memory = try XCTUnwrap(AskStoreBuilder.modelConfiguration(for: .memory))
        XCTAssertTrue(memory.isStoredInMemoryOnly)
        XCTAssertEqual(
            String(describing: memory.cloudKitDatabase),
            String(describing: ModelConfiguration.CloudKitDatabase.none)
        )
    }

    func testSecondLaunchStillSeesTheFirstQuestion() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskKit-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        try await askOnce(storeURL: url, utterance: "pasta please")
        let model = ScriptedModel()
        let assistant = try makeAssistant(model: model.client, persistence: .swiftData(storeURL: url))
        _ = await assistant.handle(utterance: "what about dinner")
        XCTAssertTrue(model.prompts.contains { $0.contains("pasta please") && $0.contains("what about dinner") })
        let users = try assistant.transcript().filter { $0.role == "user" }.map(\.text)
        XCTAssertEqual(users, ["pasta please", "what about dinner"])
    }

    func testClearDeletesTheThread() async throws {
        let assistant = try makeAssistant(model: ScriptedModel().client)
        _ = await assistant.handle(chip: AskChip(id: "dinner", skillID: "dinner", title: "What's for dinner?"))
        XCTAssertFalse(try assistant.transcript().isEmpty)
        try assistant.clearThread()
        XCTAssertTrue(try assistant.transcript().isEmpty)
    }

    func testSampleSkillsCoverReplySlotAndIntent() async throws {
        let model = ScriptedModel()
        let assistant = try AskAssistant(sampleConfiguration(replyBuilds: Counter()), model: model.client)

        model.domainResult = "recipes"
        model.skillResult = AskModelSkillChoice(skillID: "whatsForDinner")
        let dinner = await assistant.handle(utterance: "What should I cook?")
        guard case .reply(let dinnerReply) = dinner.fulfillment else {
            return XCTFail("Expected a dinner reply")
        }
        XCTAssertEqual(dinnerReply.spoken, "Pasta.")
        XCTAssertTrue(dinner.slots.isEmpty)

        let callsBeforeChip = model.domainCalls
        let chip = await assistant.handle(
            chip: AskChip(id: "dinner", skillID: "whatsForDinner", title: "What's for dinner?")
        )
        XCTAssertEqual(model.domainCalls, callsBeforeChip)
        guard case .reply = chip.fulfillment else {
            return XCTFail("Expected the chip reply")
        }

        model.domainResult = "travel"
        model.skillResult = AskModelSkillChoice(skillID: "weather")
        model.fillResult = ["city": "Chicago"]
        let weather = await assistant.handle(utterance: "Will it rain?")
        guard case .reply(let weatherReply) = weather.fulfillment else {
            return XCTFail("Expected a weather reply")
        }
        XCTAssertEqual(weatherReply.spoken, "Rain in Chicago.")
        XCTAssertEqual(weather.slots["city"], "Chicago")
        XCTAssertEqual(model.fillCounts, [2])

        model.skillResult = AskModelSkillChoice(skillID: "flightStatus")
        let status = await assistant.handle(utterance: "What's my flight status?")
        guard case .intent(let card) = status.fulfillment else {
            return XCTFail("Expected a flight status card")
        }
        XCTAssertEqual(card.spoken, "On time")
        if case .askAgain = AskConversation().step(after: weather) {
        } else {
            XCTFail("A reply offers another question")
        }
    }

    private func askOnce(storeURL: URL, utterance: String) async throws {
        let model = ScriptedModel()
        let assistant = try makeAssistant(model: model.client, persistence: .swiftData(storeURL: storeURL))
        _ = await assistant.handle(utterance: utterance)
    }

    private func makeAssistant(
        model: AskModelClient,
        persistence: AskPersistence = .memory,
        extraSkills: [AskSkill] = []
    ) throws -> AskAssistant {
        try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Pantry",
                persistence: persistence,
                domains: [
                    AskDomain(id: "recipes", summary: "Cooking", routingNotes: "Food questions stay here."),
                    AskDomain(id: "other", summary: "Anything else", routingNotes: "Unrelated questions.")
                ],
                skills: [
                    AskSkill(
                        id: "dinner",
                        domainID: "recipes",
                        title: "Dinner",
                        summary: "Suggest dinner",
                        routingNotes: "Dinner, cook, and meal questions.",
                        fulfillment: .reply { _ in AskReply(text: "Pasta.", spoken: "Pasta.") }
                    )
                ] + extraSkills,
                context: { AskContext(promptBlock: "pantry=pasta") },
                chips: { _ in
                    [AskChip(id: "dinner", skillID: "dinner", title: "What's for dinner?")]
                }
            ),
            model: model
        )
    }

    private func sampleConfiguration(replyBuilds: Counter) -> AskConfiguration {
        AskConfiguration(
            assistantName: "Ask Sample",
            domains: [
                AskDomain(id: "recipes", summary: "Cooking", routingNotes: "Food questions."),
                AskDomain(id: "travel", summary: "Trips", routingNotes: "Travel questions.")
            ],
            skills: [
                AskSkill(
                    id: "whatsForDinner",
                    domainID: "recipes",
                    title: "Dinner",
                    summary: "Suggest dinner from what is on hand",
                    routingNotes: "Dinner, cook, and meal questions.",
                    fulfillment: .reply { _ in
                        replyBuilds.value += 1
                        return AskReply(text: "Pasta with what you have.", spoken: "Pasta.")
                    }
                ),
                AskSkill(
                    id: "weather",
                    domainID: "travel",
                    title: "Weather",
                    summary: "Weather in a city",
                    requiredSlots: ["city"],
                    routingNotes: "Rain, forecast, and weather.",
                    fulfillment: .reply { invocation in
                        let city = invocation.slots["city"] ?? "somewhere"
                        return AskReply(text: "Rain in \(city).", spoken: "Rain in \(city).")
                    }
                ),
                AskSkill(
                    id: "flightStatus",
                    domainID: "travel",
                    title: "Flight status",
                    summary: "Live status for a flight",
                    requiredSlots: ["flightNumber"],
                    routingNotes: "Flight status, gate, and boarding.",
                    fulfillment: .intent { _ in
                        AskIntentCard(spoken: "On time", view: Text("UA 123"))
                    }
                )
            ],
            context: { AskContext(promptBlock: "flight=UA123") },
            chips: { _ in
                [AskChip(id: "dinner", skillID: "whatsForDinner", title: "What's for dinner?")]
            },
            tools: { domain in
                guard domain == "travel" else { return [] }
                return [StubTool(name: "forecast"), StubTool(name: "place")]
            }
        )
    }
}

final class ScriptedModel: @unchecked Sendable {
    var domainResult = "recipes"
    var skillResult = AskModelSkillChoice(skillID: "dinner")
    var fillResult: [String: String] = [:]
    var domainCalls = 0
    var skillCalls = 0
    var fillCounts: [Int] = []
    var requests: [AskModelRequest] = []
    var prompts: [String] { requests.map(\.prompt) }

    var client: AskModelClient {
        AskModelClient(
            routeDomain: { [self] request in
                self.domainCalls += 1
                self.requests.append(request)
                return self.domainResult
            },
            routeSkill: { [self] request in
                self.skillCalls += 1
                self.requests.append(request)
                return self.skillResult
            },
            fillSlots: { [self] request, tools in
                self.fillCounts.append(tools.count)
                self.requests.append(request)
                return self.fillResult
            }
        )
    }
}

final class Counter {
    var value = 0
    var handlerRan = false
}

final class SlotBox {
    var slots: [String: String] = [:]
}

struct StubTool: Tool {
    var name: String
    let description = "Test tool"

    @Generable
    struct Arguments {
        var note: String
    }

    func call(arguments: Arguments) async throws -> String {
        name
    }
}

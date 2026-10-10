import FoundationModels
import XCTest
@testable import AskKit

@MainActor
final class AskCapabilitiesTests: XCTestCase {
    func testWhatCanIDoNamesTwoExamplesAndSkipsTheModel() async throws {
        let model = ScriptedModel()
        let assistant = try assistant(model: model.client, guide: AskGuide())
        let result = await assistant.handle(
            utterance: "What can I do?",
            priorUserQuestions: ["Where's the closest charger"]
        )
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected the capabilities card")
        }
        XCTAssertEqual(result.skillID, AskCapabilities.skillID)
        XCTAssertNil(result.followUp)
        XCTAssertEqual(model.domainCalls, 0)
        XCTAssertEqual(model.skillCalls, 0)
        XCTAssertEqual(model.routeCalls, 0)
        XCTAssertEqual(model.replyCalls, 0)
        XCTAssertEqual(model.followCalls, 0)
        XCTAssertEqual(
            card.spoken,
            "You can ask me questions like Charge status or Range and I can help with that."
        )
        XCTAssertEqual(card.title, "I can help with")
        let groups = AskCapabilities.groups(domains: assistant.configuration.domains, skills: assistant.configuration.skills)
        XCTAssertEqual(groups.map(\.title), ["Charging", "Driving"])
        XCTAssertEqual(groups[0].items.map(\.title), ["Charge status"])
        XCTAssertEqual(groups[1].items.map(\.title), ["Range"])
        XCTAssertTrue(card.shareText.contains("Charge status"))
        XCTAssertTrue(card.shareText.contains("Current battery"))
        XCTAssertTrue(card.shareText.contains("Range"))
        XCTAssertFalse(card.shareText.contains("You can ask me questions like"))
    }

    func testATopicAfterWhatCanIDoStillRoutes() async throws {
        let model = ScriptedModel()
        model.domainResult = "battery"
        model.skillResult = AskModelSkillChoice(skillID: "chargeStatus")
        let assistant = try assistant(model: model.client, guide: nil)
        let result = await assistant.handle(utterance: "What can I do about the battery?")
        XCTAssertEqual(result.skillID, "chargeStatus")
        XCTAssertEqual(model.domainCalls, 1)
        XCTAssertNotEqual(result.skillID, AskCapabilities.skillID)
    }

    func testAMissShowsWhatTheAppCanDo() async throws {
        let model = ScriptedModel()
        model.domainResult = "nope"
        let assistant = try assistant(model: model.client, guide: nil)
        let result = await assistant.handle(utterance: "Who won the game?")
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected the capabilities card")
        }
        XCTAssertEqual(result.skillID, AskCapabilities.skillID)
        XCTAssertNil(result.followUp)
        XCTAssertEqual(
            card.spoken,
            "I can't help with that. You can ask me questions like Charge status or Range and I can help with that."
        )
        XCTAssertFalse(card.spoken.contains("Who won"))
    }

    func testGuardrailStopsTheTurnAndDoesNotRepeatTheQuestion() async throws {
        let model = ScriptedModel()
        model.failure = LanguageModelError.guardrailViolation(
            LanguageModelError.GuardrailViolation(debugDescription: "blocked")
        )
        let assistant = try assistant(model: model.client, guide: nil)
        let result = await assistant.handle(utterance: "zz forbidden topic")
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected the capabilities card")
        }
        XCTAssertEqual(result.skillID, AskCapabilities.skillID)
        XCTAssertEqual(model.domainCalls, 1)
        XCTAssertEqual(model.skillCalls, 0)
        XCTAssertTrue(card.spoken.hasPrefix("Sorry, this feature isn't designed to handle that kind of input."))
        XCTAssertTrue(card.spoken.contains("Charge status or Range"))
        XCTAssertFalse(card.spoken.localizedCaseInsensitiveContains("forbidden"))
    }

    func testRefusalIsTheSameBoundary() {
        let error = LanguageModelError.refusal(
            LanguageModelError.Refusal(explanation: "no", debugDescription: "refused")
        )
        XCTAssertTrue(AskModelSafety.isBlocked(error))
        XCTAssertFalse(AskModelSafety.isBlocked(CocoaError(.fileNoSuchFile)))
        XCTAssertFalse(AskCapabilities.isQuestion("What can I do about the battery?"))
        XCTAssertTrue(AskCapabilities.isQuestion("What can you help with, please?"))
    }

    func testAModelFailureSpeaksOneLineAndHidesTheDebugText() {
        let window = LanguageModelError.contextSizeExceeded(
            LanguageModelError.ContextSizeExceeded(contextSize: 4096, tokenCount: 5000, debugDescription: "secret")
        )
        let notice = AskModelSafety.notice(window)
        XCTAssertEqual(notice?.decision, "context window")
        XCTAssertEqual(notice?.spoken, AskModelSafety.contextWindow)
        XCTAssertFalse(notice?.spoken.contains("secret") ?? true)
        XCTAssertEqual(AskModelSafety.failure(window), "context window")

        let limited = LanguageModelError.rateLimited(
            LanguageModelError.RateLimited(resetDate: nil, debugDescription: "secret")
        )
        XCTAssertEqual(AskModelSafety.notice(limited)?.spoken, AskModelSafety.rateLimit)
        let timedOut = LanguageModelError.timeout(LanguageModelError.Timeout(debugDescription: "secret"))
        XCTAssertEqual(AskModelSafety.notice(timedOut)?.decision, "timeout")
        XCTAssertEqual(AskModelSafety.notice(timedOut)?.spoken, AskModelSafety.timeout)
        let language = LanguageModelError.unsupportedLanguageOrLocale(
            LanguageModelError.UnsupportedLanguageOrLocale(
                languageCode: Locale.LanguageCode("en"),
                debugDescription: "secret"
            )
        )
        XCTAssertEqual(AskModelSafety.notice(language)?.decision, "language")
        XCTAssertFalse(AskModelSafety.notice(language)?.spoken.contains("secret") ?? true)

        let guide = LanguageModelError.unsupportedGenerationGuide(
            LanguageModelError.UnsupportedGenerationGuide(schemaName: "Arguments", debugDescription: "secret")
        )
        XCTAssertEqual(AskModelSafety.notice(guide)?.decision, "unsupported guide")
        XCTAssertEqual(AskModelSafety.notice(guide)?.spoken, "")
        let schema = GeneratedContent.ParsingError(rawContent: "{", debugDescription: "secret")
        XCTAssertEqual(AskModelSafety.notice(schema)?.decision, "schema")
        XCTAssertEqual(AskModelSafety.notice(schema)?.spoken, "")
        XCTAssertTrue(AskModelSafety.keepsToolRead(schema))
        XCTAssertFalse(AskModelSafety.keepsToolRead(timedOut))
        XCTAssertFalse(AskModelSafety.keepsToolRead(guide))

        let offline = PrivateCloudComputeLanguageModel.Error.networkFailure(
            PrivateCloudComputeLanguageModel.Error.NetworkFailure(debugDescription: "secret")
        )
        XCTAssertEqual(AskModelSafety.notice(offline)?.decision, "cloud network")
        XCTAssertEqual(AskModelSafety.notice(offline)?.spoken, AskModelSafety.cloudNetwork)
        XCTAssertFalse(AskModelSafety.notice(offline)?.spoken.contains("secret") ?? true)
        let quota = PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
            PrivateCloudComputeLanguageModel.Error.QuotaLimitReached(debugDescription: "secret")
        )
        XCTAssertEqual(AskModelSafety.notice(quota)?.decision, "cloud quota")
        let down = PrivateCloudComputeLanguageModel.Error.serviceUnavailable(
            PrivateCloudComputeLanguageModel.Error.ServiceUnavailable(debugDescription: "secret")
        )
        XCTAssertEqual(AskModelSafety.notice(down)?.spoken, AskModelSafety.cloudUnavailable)
        let assets = SystemLanguageModel.Error.assetsUnavailable(
            SystemLanguageModel.Error.AssetsUnavailable(debugDescription: "secret")
        )
        XCTAssertEqual(AskModelSafety.notice(assets)?.spoken, AskModelSafety.modelAssets)
        XCTAssertEqual(AskModelSafety.notice(LanguageModelSession.Error.concurrentRequests)?.decision, "busy")

        let blocked = LanguageModelError.guardrailViolation(
            LanguageModelError.GuardrailViolation(debugDescription: "secret")
        )
        XCTAssertNil(AskModelSafety.notice(blocked))
        XCTAssertEqual(AskModelSafety.failure(blocked), "guardrail")
    }

    private func assistant(model: AskModelClient, guide: AskGuide?) throws -> AskAssistant {
        try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Garage",
                domains: [
                    AskDomain(id: "battery", summary: "Charging", routingNotes: "Battery questions."),
                    AskDomain(id: "trip", summary: "Driving", routingNotes: "Range questions.")
                ],
                skills: [
                    AskSkill(
                        id: "chargeStatus",
                        domainID: "battery",
                        title: "Charge status",
                        summary: "Current battery",
                        routingNotes: "Battery percent.",
                        fulfillment: .reply { _ in AskReply(text: "68 percent.", spoken: "68 percent.") }
                    ),
                    AskSkill(
                        id: "rangeLeft",
                        domainID: "trip",
                        title: "Range",
                        summary: "Miles left",
                        routingNotes: "How far the car can go.",
                        fulfillment: .reply { _ in AskReply(text: "214 miles.", spoken: "214 miles.") }
                    )
                ],
                context: { AskContext() },
                chips: { _ in
                    [
                        AskChip(id: "charge", skillID: "chargeStatus", title: "Charge status"),
                        AskChip(id: "range", skillID: "rangeLeft", title: "Range")
                    ]
                },
                guide: guide
            ),
            model: model
        )
    }
}

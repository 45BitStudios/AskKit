import FoundationModels
import XCTest
@testable import AskKit

/// The script stands in for `LanguageModelSession`. These tests never load the system model.
@MainActor
final class AskOnDeviceTests: XCTestCase {
    func testVersionBoundaryIs27Point3() {
        XCTAssertFalse(AskOnDeviceBoundary.allows(major: 26, minor: 0))
        XCTAssertFalse(AskOnDeviceBoundary.allows(major: 27, minor: 0))
        XCTAssertFalse(AskOnDeviceBoundary.allows(major: 27, minor: 2, patch: 9))
        XCTAssertTrue(AskOnDeviceBoundary.allows(major: 27, minor: 3))
        XCTAssertTrue(AskOnDeviceBoundary.allows(major: 27, minor: 3, patch: 1))
        XCTAssertTrue(AskOnDeviceBoundary.allows(major: 27, minor: 4))
        XCTAssertTrue(AskOnDeviceBoundary.allows(major: 28, minor: 0))
        XCTAssertEqual(AskOnDeviceBoundary.major, 27)
        XCTAssertEqual(AskOnDeviceBoundary.minor, 3)
        XCTAssertEqual(AskOnDeviceBoundary.onDeviceTokenWindow, 8_192)
        XCTAssertEqual(AskOnDeviceBoundary.legacyOnDeviceTokenWindow, 4_096)
    }

    func testInstructionBudgetLeavesRoomForToolResults() {
        XCTAssertEqual(AskOnDeviceBoundary.estimatedTokens(in: "   "), 0)
        XCTAssertTrue(AskOnDeviceBoundary.instructionsFit("Use the shelf tool."))
        XCTAssertTrue(AskOnDeviceBoundary.instructionsFitComfortably("Use the shelf tool."))

        let quarter = String(repeating: "a", count: 8_192)
        XCTAssertEqual(AskOnDeviceBoundary.estimatedTokens(in: quarter), 2_048)
        XCTAssertTrue(AskOnDeviceBoundary.instructionsFitComfortably(quarter))

        let overQuarter = String(repeating: "a", count: 8_193)
        XCTAssertFalse(AskOnDeviceBoundary.instructionsFitComfortably(overQuarter))
        XCTAssertTrue(AskOnDeviceBoundary.instructionsFit(overQuarter))

        let overWindow = String(repeating: "a", count: 8_192 * 4 + 1)
        XCTAssertFalse(AskOnDeviceBoundary.instructionsFit(overWindow))
        XCTAssertFalse(AskOnDeviceBoundary.instructionsFit(overWindow, window: AskOnDeviceBoundary.legacyOnDeviceTokenWindow))
    }

    func testAvailabilityChecksTheModelLast() {
        XCTAssertEqual(
            AskOnDeviceBoundary.availability(
                allowModel: false,
                platformSupportsFoundationModels: false,
                operatingSystemAllows: false,
                model: .modelNotReady
            ),
            .unavailable(.turnedOff)
        )
        XCTAssertEqual(
            AskOnDeviceBoundary.availability(
                allowModel: true,
                platformSupportsFoundationModels: false,
                operatingSystemAllows: true,
                model: .available
            ),
            .unavailable(.unsupportedPlatform)
        )
        XCTAssertEqual(
            AskOnDeviceBoundary.availability(
                allowModel: true,
                platformSupportsFoundationModels: true,
                operatingSystemAllows: false,
                model: .available
            ),
            .unavailable(.operatingSystem)
        )
        XCTAssertEqual(
            AskOnDeviceBoundary.availability(
                allowModel: true,
                platformSupportsFoundationModels: true,
                operatingSystemAllows: true,
                model: .deviceNotEligible
            ),
            .unavailable(.deviceNotEligible)
        )
        XCTAssertEqual(
            AskOnDeviceBoundary.availability(
                allowModel: true,
                platformSupportsFoundationModels: true,
                operatingSystemAllows: true,
                model: .appleIntelligenceNotEnabled
            ),
            .unavailable(.appleIntelligenceNotEnabled)
        )
        XCTAssertEqual(
            AskOnDeviceBoundary.availability(
                allowModel: true,
                platformSupportsFoundationModels: true,
                operatingSystemAllows: true,
                model: .modelNotReady
            ),
            .unavailable(.modelNotReady)
        )
        XCTAssertEqual(
            AskOnDeviceBoundary.availability(
                allowModel: true,
                platformSupportsFoundationModels: true,
                operatingSystemAllows: true,
                model: .available
            ),
            .available
        )
    }

    func testSystemAvailabilityMapsOntoTheReport() {
        XCTAssertEqual(AskOnDeviceBoundary.report(.available), .available)
        XCTAssertEqual(AskOnDeviceBoundary.report(.unavailable(.deviceNotEligible)), .deviceNotEligible)
        XCTAssertEqual(
            AskOnDeviceBoundary.report(.unavailable(.appleIntelligenceNotEnabled)),
            .appleIntelligenceNotEnabled
        )
        XCTAssertEqual(AskOnDeviceBoundary.report(.unavailable(.modelNotReady)), .modelNotReady)
    }

    func testTurnedOffUsesTheFallbackAndDoesNotOpenASession() async {
        let script = ScriptedOnDeviceSessions()
        var causes: [AskOnDeviceFallbackCause] = []
        let responder = makeResponder(script: script, allowModel: false) { _, cause in
            causes.append(cause)
            return AskOnDeviceAnswer(text: "Four tins on the shelf.")
        }
        XCTAssertEqual(responder.availability, .unavailable(.turnedOff))
        XCTAssertFalse(responder.modelIsAvailable)
        let turn = await responder.answer("How many tomatoes?")
        XCTAssertEqual(turn.engine, .fallback)
        XCTAssertFalse(turn.continuedSession)
        XCTAssertEqual(turn.answer.text, "Four tins on the shelf.")
        XCTAssertEqual(causes, [.unavailable(.turnedOff)])
        XCTAssertTrue(script.instructions.isEmpty)
        XCTAssertTrue(script.sessionsMade.isEmpty)
    }

    func testOlderOperatingSystemUsesTheFallback() async {
        let script = ScriptedOnDeviceSessions()
        let responder = makeResponder(
            script: script,
            environment: .fixed(operatingSystemAllows: false)
        ) { _, cause in
            XCTAssertEqual(cause, .unavailable(.operatingSystem))
            return AskOnDeviceAnswer(text: "Rules.")
        }
        let turn = await responder.answer("How many tomatoes?")
        XCTAssertEqual(turn.engine, .fallback)
        XCTAssertEqual(turn.answer.text, "Rules.")
        XCTAssertTrue(script.sessionsMade.isEmpty)
    }

    func testEachModelReasonUsesTheFallback() async {
        let reasons: [AskOnDeviceModelReport] = [.deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady]
        let expected: [AskOnDeviceUnavailability] = [.deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady]
        for (model, reason) in zip(reasons, expected) {
            let script = ScriptedOnDeviceSessions()
            let responder = makeResponder(script: script, environment: .fixed(model: model)) { _, cause in
                XCTAssertEqual(cause, .unavailable(reason))
                return AskOnDeviceAnswer(text: "Rules.")
            }
            let turn = await responder.answer("How many?")
            XCTAssertEqual(turn.engine, .fallback)
            XCTAssertTrue(script.sessionsMade.isEmpty)
        }
    }

    func testAPlatformWithoutFoundationModelsUsesTheFallback() async {
        let script = ScriptedOnDeviceSessions()
        let responder = makeResponder(
            script: script,
            environment: .fixed(platformSupportsFoundationModels: false)
        ) { _, cause in
            XCTAssertEqual(cause, .unavailable(.unsupportedPlatform))
            return AskOnDeviceAnswer(text: "Rules.")
        }
        let turn = await responder.answer("How many?")
        XCTAssertEqual(turn.engine, .fallback)
        XCTAssertTrue(script.sessionsMade.isEmpty)
    }

    func testInstructionsThatExceedTheWindowDoNotOpenASession() async {
        let script = ScriptedOnDeviceSessions()
        var instructionReads = 0
        var toolReads = 0
        let responder = AskOnDeviceResponder(
            instructions: {
                instructionReads += 1
                return String(repeating: "a", count: 8_192 * 4 + 1)
            },
            tools: {
                toolReads += 1
                return [ShelfTool()]
            },
            fallback: { _, cause in
                XCTAssertEqual(cause, .instructionsTooLong)
                return AskOnDeviceAnswer(text: "Rules.")
            },
            environment: .fixed(),
            sessions: script.factory
        )
        let turn = await responder.answer("How many tomatoes?")
        XCTAssertEqual(turn.engine, .fallback)
        XCTAssertEqual(instructionReads, 1)
        XCTAssertEqual(toolReads, 0)
        XCTAssertTrue(script.sessionsMade.isEmpty)
    }

    func testTheModelTurnUsesTheAppToolsPromptAndCitations() async {
        let script = ScriptedOnDeviceSessions()
        script.handler = { prompt in
            XCTAssertEqual(prompt, "How many tomatoes?")
            return AskOnDeviceAnswerDraft(
                text: "  Four tins.  ",
                citedIDs: [" tomatoes ", "", "basil", "nope"],
                reason: "  shelf  "
            )
        }
        var fallbacks = 0
        var instructionReads = 0
        let responder = AskOnDeviceResponder(
            instructions: {
                instructionReads += 1
                return "Use the shelf tool for every count."
            },
            tools: { [ShelfTool(), NoteTool()] },
            acceptCitation: { $0 == "tomatoes" || $0 == "basil" },
            fallback: { _, _ in
                fallbacks += 1
                return AskOnDeviceAnswer(text: "Rules.")
            },
            environment: .fixed(),
            sessions: script.factory
        )
        let turn = await responder.answer("How many tomatoes?")
        XCTAssertEqual(turn.engine, .foundationModels)
        XCTAssertFalse(turn.continuedSession)
        XCTAssertEqual(turn.answer.text, "Four tins.")
        XCTAssertEqual(turn.answer.citedIDs, ["tomatoes", "basil"])
        XCTAssertEqual(turn.answer.reason, "shelf")
        XCTAssertEqual(fallbacks, 0)
        XCTAssertEqual(instructionReads, 1)
        XCTAssertEqual(script.instructions, ["Use the shelf tool for every count."])
        XCTAssertEqual(script.toolNames, [["shelfLookup", "noteLookup"]])
        XCTAssertEqual(script.sessionsMade.count, 1)
    }

    func testAnEmptyModelSentenceUsesTheFallback() async {
        let script = ScriptedOnDeviceSessions()
        script.handler = { _ in
            AskOnDeviceAnswerDraft(text: " \n ", citedIDs: ["tomatoes"], reason: "shelf")
        }
        let responder = makeResponder(script: script) { _, cause in
            XCTAssertEqual(cause, .emptyAnswer)
            return AskOnDeviceAnswer(text: "Rules.", citedIDs: ["from-rules"])
        }
        let turn = await responder.answer("How many tomatoes?")
        XCTAssertEqual(turn.engine, .fallback)
        XCTAssertEqual(turn.answer.text, "Rules.")
        XCTAssertEqual(turn.answer.citedIDs, ["from-rules"])
        XCTAssertFalse(turn.continuedSession)
    }

    func testAFollowUpReusesTheSessionUntilReset() async {
        let script = ScriptedOnDeviceSessions()
        var prompts: [String] = []
        script.handler = { prompt in
            prompts.append(prompt)
            if prompts.count == 1 {
                throw ProbeError.failed
            }
            return AskOnDeviceAnswerDraft(text: "Still four.", citedIDs: ["tomatoes"], reason: "shelf")
        }
        var instructionReads = 0
        let responder = AskOnDeviceResponder(
            instructions: {
                instructionReads += 1
                return "Use the shelf tool."
            },
            tools: { [ShelfTool()] },
            fallback: { utterance, cause in
                XCTAssertEqual(utterance, "How many tomatoes?")
                XCTAssertEqual(cause, .modelFailed)
                return AskOnDeviceAnswer(text: "Rules.")
            },
            environment: .fixed(),
            sessions: script.factory
        )
        let failed = await responder.answer("How many tomatoes?")
        XCTAssertEqual(failed.engine, .fallback)
        XCTAssertFalse(failed.continuedSession)
        XCTAssertEqual(failed.answer.text, "Rules.")

        let followUp = await responder.answer("And basil?")
        XCTAssertEqual(followUp.engine, .foundationModels)
        XCTAssertTrue(followUp.continuedSession)
        XCTAssertEqual(followUp.answer.text, "Still four.")
        XCTAssertEqual(prompts, ["How many tomatoes?", "And basil?"])
        XCTAssertEqual(script.sessionsMade.count, 1)
        XCTAssertEqual(instructionReads, 1)

        responder.reset()
        let fresh = await responder.answer("How many now?")
        XCTAssertEqual(fresh.engine, .foundationModels)
        XCTAssertFalse(fresh.continuedSession)
        XCTAssertEqual(script.sessionsMade.count, 2)
        XCTAssertEqual(instructionReads, 2)
        XCTAssertEqual(script.sessionsMade[1].prompts, ["How many now?"])
    }

    func testAGuardrailUsesTheBlockedFallback() async {
        let script = ScriptedOnDeviceSessions()
        script.handler = { _ in
            throw LanguageModelError.guardrailViolation(
                LanguageModelError.GuardrailViolation(debugDescription: "blocked")
            )
        }
        let responder = makeResponder(script: script) { utterance, cause in
            XCTAssertEqual(cause, .blocked)
            XCTAssertFalse(utterance.isEmpty)
            return AskOnDeviceAnswer(text: "Sorry, this feature isn't designed to handle that kind of input.")
        }
        let turn = await responder.answer("zz forbidden")
        XCTAssertEqual(turn.engine, .fallback)
        XCTAssertEqual(turn.answer.text, "Sorry, this feature isn't designed to handle that kind of input.")
        XCTAssertFalse(turn.answer.text.contains("forbidden"))
    }

    func testACallThatArrivesDuringATurnDoesNotTouchTheSession() async {
        let script = ScriptedOnDeviceSessions()
        let responder = makeResponder(script: script) { _, cause in
            XCTAssertEqual(cause, .busy)
            return AskOnDeviceAnswer(text: "Busy rules.")
        }
        var nested: AskOnDeviceTurn<AskOnDeviceAnswer>?
        script.handler = { _ in
            nested = await responder.answer("meanwhile")
            return AskOnDeviceAnswerDraft(text: "Four tins.", citedIDs: [], reason: "shelf")
        }
        let outer = await responder.answer("How many tomatoes?")
        XCTAssertEqual(outer.engine, .foundationModels)
        XCTAssertEqual(outer.answer.text, "Four tins.")
        XCTAssertEqual(nested?.engine, .fallback)
        XCTAssertEqual(nested?.answer.text, "Busy rules.")
        XCTAssertEqual(script.sessionsMade.first?.prompts, ["How many tomatoes?"])
    }

    func testACustomSchemaReusesTheSessionAndFallsBackOnFailure() async {
        let script = ScriptedOnDeviceSessions()
        var calls = 0
        script.handler = { _ in
            calls += 1
            if calls == 1 {
                return StockLine(text: "Four tins.")
            }
            throw ProbeError.failed
        }
        let responder = makeResponder(script: script) { _, _ in
            AskOnDeviceAnswer(text: "Unused.")
        }
        let first = await responder.answer("How many?", generating: StockLine.self) { _, _ in
            StockLine(text: "Rules.")
        }
        XCTAssertEqual(first.engine, .foundationModels)
        XCTAssertEqual(first.answer.text, "Four tins.")
        XCTAssertFalse(first.continuedSession)

        let second = await responder.answer("And now?", generating: StockLine.self) { _, cause in
            XCTAssertEqual(cause, .modelFailed)
            return StockLine(text: "Rules.")
        }
        XCTAssertEqual(second.engine, .fallback)
        XCTAssertTrue(second.continuedSession)
        XCTAssertEqual(second.answer.text, "Rules.")
        XCTAssertEqual(script.sessionsMade.count, 1)
        XCTAssertEqual(script.sessionsMade[0].prompts, ["How many?", "And now?"])
    }

    func testACustomSchemaStaysOnTheFallbackWhenTheOSIsOlder() async {
        let script = ScriptedOnDeviceSessions()
        let responder = makeResponder(
            script: script,
            environment: .fixed(operatingSystemAllows: false)
        ) { _, _ in
            AskOnDeviceAnswer(text: "Unused.")
        }
        let turn = await responder.answer("How many?", generating: StockLine.self) { _, cause in
            XCTAssertEqual(cause, .unavailable(.operatingSystem))
            return StockLine(text: "Rules.")
        }
        XCTAssertEqual(turn.engine, .fallback)
        XCTAssertEqual(turn.answer.text, "Rules.")
        XCTAssertTrue(script.sessionsMade.isEmpty)
    }

    func testANotReadyTurnLeavesTheSessionInPlace() async {
        let script = ScriptedOnDeviceSessions()
        let gate = ModelGate()
        script.handler = { _ in
            AskOnDeviceAnswerDraft(text: "Four tins.", citedIDs: [], reason: "shelf")
        }
        let responder = AskOnDeviceResponder(
            instructions: { "Use the shelf tool." },
            tools: { [ShelfTool()] },
            fallback: { _, cause in
                XCTAssertEqual(cause, .unavailable(.modelNotReady))
                return AskOnDeviceAnswer(text: "Rules.")
            },
            environment: AskOnDeviceEnvironment(
                platformSupportsFoundationModels: true,
                operatingSystemAllows: { true },
                model: { gate.ready ? .available : .modelNotReady }
            ),
            sessions: script.factory
        )
        let first = await responder.answer("How many?")
        XCTAssertEqual(first.engine, .foundationModels)
        XCTAssertFalse(first.continuedSession)

        gate.ready = false
        let skipped = await responder.answer("And basil?")
        XCTAssertEqual(skipped.engine, .fallback)
        XCTAssertEqual(skipped.answer.text, "Rules.")
        XCTAssertFalse(skipped.continuedSession)

        gate.ready = true
        let again = await responder.answer("And now?")
        XCTAssertEqual(again.engine, .foundationModels)
        XCTAssertTrue(again.continuedSession)
        XCTAssertEqual(again.answer.text, "Four tins.")
        XCTAssertEqual(script.sessionsMade.count, 1)
        XCTAssertEqual(script.sessionsMade[0].prompts, ["How many?", "And now?"])
    }

    func testShelfLookupIsPure() {
        XCTAssertEqual(ShelfTool.lookup("tomato", stock: ["tomatoes": "4"]), "tomato: 4")
        XCTAssertEqual(ShelfTool.lookup("  ", stock: ["tomatoes": "4"]), "Which item?")
        XCTAssertEqual(ShelfTool.lookup("basil", stock: [:]), "Nothing named basil is on the shelf.")
    }

    private func makeResponder(
        script: ScriptedOnDeviceSessions,
        allowModel: Bool = true,
        environment: AskOnDeviceEnvironment = .fixed(),
        fallback: @escaping @MainActor (String, AskOnDeviceFallbackCause) -> AskOnDeviceAnswer
    ) -> AskOnDeviceResponder {
        AskOnDeviceResponder(
            allowModel: allowModel,
            instructions: { "Use the shelf tool." },
            tools: { [ShelfTool()] },
            fallback: fallback,
            environment: environment,
            sessions: script.factory
        )
    }
}

private enum ProbeError: Error {
    case failed
}

private final class ModelGate: @unchecked Sendable {
    var ready = true
}

@Generable
struct StockLine: Sendable {
    @Guide(description: "One sentence.")
    var text: String
}

struct ShelfTool: Tool {
    let name = "shelfLookup"
    let description = "Looks up how many of one item are on the shelf."

    @Generable
    struct Arguments {
        @Guide(description: "The item name.")
        var item: String
    }

    func call(arguments: Arguments) async throws -> String {
        Self.lookup(arguments.item, stock: ["tomatoes": "4"])
    }

    static func lookup(_ item: String, stock: [String: String]) -> String {
        let name = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let count = stock.first(where: { $0.key.localizedStandardContains(name) })?.value else {
            return name.isEmpty ? "Which item?" : "Nothing named \(name) is on the shelf."
        }
        return "\(name): \(count)"
    }
}

struct NoteTool: Tool {
    let name = "noteLookup"
    let description = "Reads one note the app stored."

    @Generable
    struct Arguments {
        @Guide(description: "Note id.")
        var id: String
    }

    func call(arguments: Arguments) async throws -> String {
        "Note \(arguments.id)"
    }
}

@MainActor
private final class ScriptedOnDeviceSession: AskOnDeviceGenerating {
    var prompts: [String] = []
    var handler: (String) async throws -> Any = { _ in
        AskOnDeviceAnswerDraft(text: "ok", citedIDs: [], reason: "")
    }

    func respond<Answer: Generable & Sendable>(
        to prompt: String,
        generating type: Answer.Type
    ) async throws -> Answer {
        prompts.append(prompt)
        let value = try await handler(prompt)
        guard let typed = value as? Answer else {
            throw ProbeError.failed
        }
        return typed
    }
}

@MainActor
private final class ScriptedOnDeviceSessions {
    var instructions: [String] = []
    var toolNames: [[String]] = []
    var sessionsMade: [ScriptedOnDeviceSession] = []
    var handler: (String) async throws -> Any = { _ in
        AskOnDeviceAnswerDraft(text: "ok", citedIDs: [], reason: "")
    }

    private var storedFactory: AskOnDeviceSessions?

    var factory: AskOnDeviceSessions {
        if let storedFactory { return storedFactory }
        let made = AskOnDeviceSessions { [self] instructions, tools in
            self.instructions.append(instructions)
            self.toolNames.append(tools.map(\.name))
            let session = ScriptedOnDeviceSession()
            session.handler = { [self] prompt in
                try await self.handler(prompt)
            }
            self.sessionsMade.append(session)
            return session
        }
        storedFactory = made
        return made
    }
}

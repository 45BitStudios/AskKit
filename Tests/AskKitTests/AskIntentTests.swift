import os
import SwiftUI
import XCTest
@testable import AskKit

@MainActor
final class AskIntentTests: XCTestCase {
    func testAnswerRecordsAShortcutTurn() async throws {
        let finished = OSAllocatedUnfairLock(initialState: [AskTraceTurn]())
        let recorder = AskTraceRecorder { turn in
            finished.withLock { $0.append(turn) }
        }
        let assistant = try makeAssistant()
        let answer = try await AskTrace.$recorder.withValue(recorder) {
            try await AskIntent.answer("  what's for dinner?  ", using: assistant)
        }
        XCTAssertEqual(answer.spoken, "Pasta.")
        guard case .reply(let reply) = answer.turn.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.text, "Pasta tonight.")
        let turn = try XCTUnwrap(finished.withLock { $0.last })
        XCTAssertEqual(turn.entry, .shortcut)
        XCTAssertEqual(turn.question, "what's for dinner?")
        let saved = try XCTUnwrap(assistant.transcript().last { $0.role == "user" })
        XCTAssertEqual(saved.text, "what's for dinner?")
    }

    func testClientEntryIsRecorded() async throws {
        let finished = OSAllocatedUnfairLock(initialState: [AskTraceTurn]())
        let recorder = AskTraceRecorder { turn in
            finished.withLock { $0.append(turn) }
        }
        let client = AskIntentClient(assistant: try makeAssistant(), entry: .siri)
        _ = try await AskTrace.$recorder.withValue(recorder) {
            try await AskIntent.answer("dinner", using: client)
        }
        XCTAssertEqual(finished.withLock { $0.last }?.entry, .siri)
    }

    func testBlankQuestionDoesNotAppend() async throws {
        let assistant = try makeAssistant()
        do {
            _ = try await AskIntent.answer("   ", using: assistant)
            XCTFail("Expected an empty question")
        } catch AskIntentError.emptyQuestion {
        } catch {
            XCTFail("Unexpected \(error)")
        }
        XCTAssertTrue(try assistant.transcript().isEmpty)
    }

    func testIntentCardSpeaksTheFullLine() async throws {
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Garage",
                domains: [AskDomain(id: "ev", summary: "Car", routingNotes: "The car.")],
                skills: [
                    AskSkill(
                        id: "charge",
                        domainID: "ev",
                        title: "Charge",
                        summary: "Battery",
                        routingNotes: "Battery questions.",
                        fulfillment: .intent { _ in
                            AskIntentCard(
                                title: "Charge",
                                spoken: "The car is at 68 percent. I can open charging.",
                                text: "I can open charging.",
                                action: AskAction(id: "charging", title: "Charging"),
                                view: Text("68 percent")
                            )
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "charge") }
            )
        )
        let answer = try await AskIntent.answer("battery", using: assistant)
        XCTAssertEqual(answer.spoken, "The car is at 68 percent. I can open charging.")
        XCTAssertEqual(answer.speech, answer.spoken)
        guard case .intent(let card) = answer.turn.fulfillment else {
            return XCTFail("Expected a card")
        }
        XCTAssertEqual(card.title, "Charge")
        XCTAssertEqual(AskCardTranscript.bubble(card.text, card: card), nil)
    }

    func testIntentDialogKeepsTheSpeechAndLeavesTheCardSeparate() async throws {
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Garage",
                domains: [AskDomain(id: "travel", summary: "Trips", routingNotes: "Travel.")],
                skills: [
                    AskSkill(
                        id: "status",
                        domainID: "travel",
                        title: "Flight status",
                        summary: "Live status",
                        routingNotes: "Flight status.",
                        fulfillment: .intent { _ in
                            AskIntentCard(
                                title: "Flight status",
                                spoken: "UA 123 is on time. Doors close at noon.",
                                coveredPhrases: ["on time"],
                                view: Text("UA 123")
                            )
                        }
                    ),
                    AskSkill(
                        id: "gate",
                        domainID: "travel",
                        title: "Gate",
                        summary: "The gate",
                        routingNotes: "Gate.",
                        fulfillment: .intent { _ in
                            AskIntentCard(
                                title: "Gate",
                                spoken: "The gate is C12.",
                                view: Text("C12")
                            )
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { utterance in
                    let lower = utterance.lowercased()
                    if lower.contains("status") { return AskRoute(skillID: "status") }
                    if lower.contains("gate") { return AskRoute(skillID: "gate") }
                    return nil
                }
            )
        )
        let one = try await AskIntent.answer("status", using: assistant)
        XCTAssertEqual(one.spoken, "UA 123 is on time. Doors close at noon.")
        XCTAssertEqual(one.speech, "Doors close at noon.")
        XCTAssertNotNil(one.turn.pages.first?.card)

        let both = try await AskIntent.answer("status and gate", using: assistant)
        XCTAssertEqual(both.turn.pages.map(\.skillID), ["status", "gate"])
        XCTAssertEqual(both.speech, "Doors close at noon.\nThe gate is C12.")
        XCTAssertEqual(both.turn.pages.compactMap(\.card).map(\.title), ["Flight status", "Gate"])
    }

    func testAnswerKeepsTheTurnTheSnippetReloads() async throws {
        let assistant = try makeAssistant()
        let answer = try await AskIntent.answer("what's for dinner?", using: assistant)
        XCTAssertEqual(answer.snippet.turnID, answer.turn.id.uuidString)
        let saved = try XCTUnwrap(try assistant.transcript().last { $0.role == "assistant" })
        XCTAssertEqual(saved.id, answer.turn.id)
        let pages = await assistant.pages(for: answer.turn.id)
        XCTAssertEqual(pages.map(\.spoken), ["Pasta."])
    }

    func testAnswerExportsTypedOutputsForShortcuts() async throws {
        let assistant = try makeAssistant()
        let answer = try await AskIntent.answer("what's for dinner?", using: assistant)
        XCTAssertEqual(answer.outputs, [.text("Pasta.")])
    }

    private func makeAssistant() throws -> AskAssistant {
        try AskAssistant(
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
                        fulfillment: .reply { _ in
                            AskReply(text: "Pasta tonight.", spoken: "Pasta.")
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "dinner") }
            )
        )
    }
}

import CoreGraphics
import FoundationModels
import ImageIO
import os
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import AskKit

@MainActor
final class AskPagesTests: XCTestCase {
    func testPiecesSplitOnQuestionsAndConjunctions() {
        XCTAssertEqual(AskPages.pieces("What's for dinner?"), ["What's for dinner?"])
        XCTAssertEqual(AskPages.pieces("What can I do?"), ["What can I do?"])
        XCTAssertEqual(AskPages.pieces("What can I do about the battery?"), ["What can I do about the battery?"])
        XCTAssertEqual(AskPages.pieces("what about the range"), ["what about the range"])
        XCTAssertEqual(AskPages.pieces("also what's on hand"), ["also what's on hand"])
        XCTAssertEqual(AskPages.pieces(""), [])

        let andParts = AskPages.pieces("what's for dinner and what's on hand?")
        XCTAssertEqual(andParts.count, 2)
        XCTAssertTrue(andParts[0].lowercased().contains("dinner"))
        XCTAssertTrue(andParts[1].lowercased().contains("on hand"))
        XCTAssertFalse(andParts[1].contains("?"))

        let punctuated = AskPages.pieces("What's for dinner? And what's on hand?")
        XCTAssertEqual(punctuated.count, 2)
        XCTAssertFalse(punctuated[1].lowercased().hasPrefix("and"))
        XCTAssertTrue(punctuated[1].lowercased().contains("on hand"))

        let decimal = AskPages.pieces("0.4 miles and range")
        XCTAssertEqual(decimal.count, 2)
        XCTAssertTrue(decimal[0].contains("0.4"))
        XCTAssertEqual(decimal[1], "range")

        let capped = AskPages.pieces("charge status and range and tires and lights")
        XCTAssertEqual(capped.count, 3)
        XCTAssertEqual(capped[0], "charge status")
        XCTAssertEqual(capped[2], "tires")
    }

    func testTwoFastPathSkillsBecomeTwoPagesAndSkipFollowUp() async throws {
        let finished = OSAllocatedUnfairLock(initialState: [AskTraceTurn]())
        let recorder = AskTraceRecorder { turn in
            finished.withLock { $0.append(turn) }
        }
        let model = ScriptedModel()
        model.replyText = "Ready tonight."
        model.followUp = AskFollowUp(skillID: "stock", question: "What is on hand?")
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Pantry",
                domains: [
                    AskDomain(id: "meals", summary: "Cooking", routingNotes: "Meals."),
                    AskDomain(id: "supplies", summary: "The shelf", routingNotes: "Stock.")
                ],
                skills: [
                    AskSkill(
                        id: "dinner",
                        domainID: "meals",
                        title: "Dinner",
                        summary: "Tonight's meal",
                        routingNotes: "Dinner.",
                        fulfillment: .reply { _ in
                            AskReply(
                                text: "Pasta.",
                                spoken: "Pasta.",
                                actions: [AskAction(id: "recipes", title: "Recipes")],
                                facts: "Tomato pasta."
                            )
                        }
                    ),
                    AskSkill(
                        id: "stock",
                        domainID: "supplies",
                        title: "On hand",
                        summary: "The shelf",
                        routingNotes: "Stock.",
                        fulfillment: .intent { _ in
                            AskIntentCard(
                                title: "On hand",
                                spoken: "Pasta and oil.",
                                action: AskAction(id: "shelf", title: "Shelf"),
                                facts: "Pasta and oil.",
                                view: Text("Pantry")
                            )
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { utterance in
                    let lower = utterance.lowercased()
                    if lower.contains("dinner") { return AskRoute(skillID: "dinner") }
                    if lower.contains("on hand") { return AskRoute(skillID: "stock") }
                    return nil
                },
                guide: AskGuide(
                    replyInstructions: "Rewrite FACTS.",
                    followUpInstructions: "Offer one question."
                )
            ),
            model: model.client
        )
        let result = await AskTrace.$recorder.withValue(recorder) {
            await assistant.handle(utterance: "what's for dinner and what's on hand?")
        }
        XCTAssertEqual(model.domainCalls, 0)
        XCTAssertEqual(model.routeCalls, 0)
        XCTAssertEqual(model.replyCalls, 2)
        XCTAssertEqual(model.followCalls, 0)
        XCTAssertNil(result.followUp)
        XCTAssertEqual(result.skillID, "dinner")
        XCTAssertEqual(result.pages.map(\.skillID), ["dinner", "stock"])
        XCTAssertEqual(result.pages[0].actions.map(\.title), ["Recipes"])
        XCTAssertNil(result.pages[0].card)
        XCTAssertEqual(result.pages[1].card?.title, "On hand")
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected the first page")
        }
        XCTAssertEqual(reply.spoken, "Ready tonight.")

        let turns = try assistant.transcript()
        XCTAssertEqual(turns.filter { $0.role == "user" }.map(\.text), ["what's for dinner and what's on hand?"])
        XCTAssertEqual(turns.filter { $0.role == "assistant" }.count, 1)
        let saved = try XCTUnwrap(turns.last { $0.role == "assistant" })
        XCTAssertTrue(saved.text.contains("Ready tonight."))
        XCTAssertEqual(saved.skillID, "dinner")

        let restored = await assistant.pages(for: saved.id)
        XCTAssertEqual(restored.map(\.id), result.pages.map(\.id))
        XCTAssertEqual(restored.map(\.skillID), ["dinner", "stock"])
        XCTAssertEqual(restored[0].actions.map(\.title), ["Recipes"])
        XCTAssertNil(restored[0].card)
        XCTAssertEqual(restored[1].card?.title, "On hand")
        XCTAssertEqual(restored[1].card?.action?.title, "Shelf")

        let fulfill = finished.withLock { $0.last }?.spans.first { $0.name == "fulfill" }
        XCTAssertEqual(fulfill?.attributes.first { $0.key == "pageCount" }?.value, "2")
        XCTAssertEqual(fulfill?.attributes.first { $0.key == "skill" }?.value, "dinner")
        XCTAssertEqual(fulfill?.attributes.first { $0.key == "shownCards" }?.value, "On hand")
    }

    func testTheSameSkillStaysOnePage() async throws {
        let seen = OSAllocatedUnfairLock(initialState: "")
        let model = ScriptedModel()
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Garage",
                domains: [AskDomain(id: "trip", summary: "Driving", routingNotes: "Range.")],
                skills: [
                    AskSkill(
                        id: "range",
                        domainID: "trip",
                        title: "Range",
                        summary: "Miles left",
                        routingNotes: "Range.",
                        fulfillment: .reply { invocation in
                            seen.withLock { $0 = invocation.utterance }
                            return AskReply(text: "214 miles.", spoken: "214 miles.")
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { utterance in
                    let lower = utterance.lowercased()
                    if lower.contains("range") || lower.contains("how far") || lower.contains("miles") {
                        return AskRoute(skillID: "range")
                    }
                    return nil
                }
            ),
            model: model.client
        )
        let result = await assistant.handle(utterance: "how far and miles left")
        XCTAssertEqual(model.domainCalls, 0)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.skillID, "range")
        XCTAssertEqual(seen.withLock { $0 }, "how far and miles left")
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected one reply")
        }
        XCTAssertEqual(reply.spoken, "214 miles.")
    }

    func testASplitThatMissesDoesNotRouteTheWholeQuestionAgain() async throws {
        let model = ScriptedModel()
        model.domainResult = "nope"
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Pantry",
                domains: [AskDomain(id: "supplies", summary: "The shelf", routingNotes: "Stock.")],
                skills: [
                    AskSkill(
                        id: "stock",
                        domainID: "supplies",
                        title: "On hand",
                        summary: "The shelf",
                        routingNotes: "Stock.",
                        fulfillment: .reply { _ in AskReply(text: "Pasta.", spoken: "Pasta.") }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [AskChip(id: "stock", skillID: "stock", title: "What's on hand?")] }
            ),
            model: model.client
        )
        let result = await assistant.handle(utterance: "olive oil and parmesan")
        XCTAssertEqual(model.domainCalls, 2)
        XCTAssertEqual(model.skillCalls, 0)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.skillID, AskCapabilities.skillID)
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected the capabilities card")
        }
        XCTAssertTrue(card.spoken.hasPrefix("I can't help with that."))
    }

    func testWhatCanIDoStaysOnePage() async throws {
        let model = ScriptedModel()
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Garage",
                domains: [AskDomain(id: "battery", summary: "Charging", routingNotes: "Battery.")],
                skills: [
                    AskSkill(
                        id: "chargeStatus",
                        domainID: "battery",
                        title: "Charge status",
                        summary: "How full the battery is",
                        routingNotes: "Charge.",
                        fulfillment: .reply { _ in AskReply(text: "68 percent.", spoken: "68 percent.") }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [AskChip(id: "charge", skillID: "chargeStatus", title: "Charge status")] },
                fastPath: { _ in AskRoute(skillID: "chargeStatus") },
                guide: AskGuide()
            ),
            model: model.client
        )
        let result = await assistant.handle(utterance: "What can I do?")
        XCTAssertEqual(model.domainCalls, 0)
        XCTAssertEqual(model.routeCalls, 0)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.skillID, AskCapabilities.skillID)
        XCTAssertNotNil(result.pages[0].card)
        XCTAssertNil(result.followUp)
    }

    func testPhotoQuestionsShareOneTurnAndKeepEachAnswer() async throws {
        let seen = OSAllocatedUnfairLock(initialState: [String]())
        let model = ScriptedModel()
        model.followUp = AskFollowUp(skillID: "answer", question: "Anything else?")
        let photo = try photoFile()
        defer { try? FileManager.default.removeItem(at: photo) }
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask Open",
                domains: [AskDomain(id: "open", summary: "Answers", routingNotes: "Anything.")],
                skills: [
                    AskSkill(
                        id: "answer",
                        domainID: "open",
                        title: "Answer",
                        summary: "A direct answer",
                        routingNotes: "Answer.",
                        fulfillment: .reply { invocation in
                            seen.withLock { $0.append(invocation.utterance) }
                            return AskReply(text: "Skill line.", spoken: "Skill line.")
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "answer") },
                guide: AskGuide(
                    replyInstructions: "Rewrite FACTS.",
                    followUpInstructions: "Offer one question."
                )
            ),
            model: model.client
        )
        let asked = "Where was it taken and on what date and with what phone"
        let result = await assistant.handle(utterance: asked, images: [photo])
        XCTAssertEqual(model.replyCalls, 0)
        XCTAssertEqual(model.followCalls, 0)
        XCTAssertNil(result.followUp)
        XCTAssertEqual(result.pages.count, 3)
        XCTAssertEqual(result.pages.map(\.skillID), ["answer", "answer", "answer"])
        XCTAssertEqual(seen.withLock { $0 }, ["Where was it taken", "on what date", "with what phone"])
        XCTAssertEqual(result.pages[0].text, "It was taken at Cupertino.")
        XCTAssertNil(result.pages[0].card)
        XCTAssertEqual(result.pages[1].text, "It was taken on 12 March 2024 at 3:04 PM.")
        XCTAssertNil(result.pages[1].card)
        XCTAssertEqual(result.pages[2].text, "It was taken on an Apple iPhone 17 Pro.")
        XCTAssertNil(result.pages[2].card)
        let turns = try assistant.transcript()
        XCTAssertEqual(turns.filter { $0.role == "user" }.map(\.text), [asked])
        XCTAssertEqual(turns.filter { $0.role == "assistant" }.count, 1)
        let saved = try XCTUnwrap(turns.last { $0.role == "assistant" })
        XCTAssertTrue(saved.text.contains("Cupertino."))
        XCTAssertTrue(saved.text.contains("12 March 2024 at 3:04 PM."))
        XCTAssertTrue(saved.text.contains("Apple iPhone 17 Pro."))
    }

    /// Place from IPTC, with a date and a camera, and no GPS so the test does not geocode.
    private func photoFile() throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 6,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-shot.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:03:12 15:04:05"
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 17 Pro"
            ] as [CFString: Any],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCity: "Cupertino"
            ] as [CFString: Any]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}

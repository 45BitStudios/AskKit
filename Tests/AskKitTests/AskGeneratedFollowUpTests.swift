import Foundation
import Testing
@testable import AskKit

@Suite("Generated card follow-ups")
struct AskGeneratedFollowUpTests {
    @Test func anEmptyPriorBlockLeavesTheComposePromptUnchanged() {
        let prompt = AskGeneratedCard.composePrompt(
            facts: "5 p.m.",
            title: "Next drive",
            spoken: "At 5."
        )
        #expect(prompt == """
        TITLE
        Next drive

        SPOKEN
        At 5.

        FACTS
        5 p.m.
        """)
        #expect(!prompt.contains("PRIOR FACTS"))
    }

    @Test func priorFactsAreCappedAndStayInOrder() {
        #expect(AskGeneratedContext.bounded(["  ", ""]) == "")
        #expect(AskGeneratedContext.bounded(["one", "two", "three"], limit: 100, cards: 2) == "two\n\nthree")

        let older = "older-fact"
        let newer = String(repeating: "n", count: 50)
        #expect(AskGeneratedContext.bounded([older, newer], limit: 10) == String(repeating: "n", count: 10))

        let facts = (0..<10).map { index in String(repeating: "x", count: 300) + "\(index)" }
        let bounded = AskGeneratedContext.bounded(facts, limit: 700, cards: 6)
        #expect(bounded.count <= 700)
        #expect(bounded.hasSuffix("9"))
        #expect(bounded.contains("8"))
        #expect(!bounded.contains("7"))
        let eight = bounded.range(of: "8")
        let nine = bounded.range(of: "9")
        #expect(eight != nil && nine != nil && eight!.lowerBound < nine!.lowerBound)
    }

    @Test @MainActor func aFollowUpAppendsAndPassesBoundedFacts() async throws {
        let model = ScriptedCardModel()
        model.composeResult = AskCardNode(kind: "stat", text: "5 p.m.")
        let assistant = try followUpAssistant(model: model, passesContext: false)
        var thread = AskGeneratedThread()
        thread = await assistant.appendCard(
            "When is the next drive?",
            from: AskGeneratedBlueprint(
                title: "Next drive",
                spoken: "At 5 p.m.",
                facts: "FACT-ONE"
            ),
            to: thread
        )
        model.composeResult = AskCardNode(kind: "stat", text: "210 mi")
        thread = await assistant.appendCard(
            "What about the range?",
            from: AskGeneratedBlueprint(
                title: "Range",
                spoken: "About 210 miles.",
                facts: "FACT-TWO"
            ),
            to: thread
        )

        #expect(thread.entries.map(\.question) == ["When is the next drive?", "What about the range?"])
        #expect(thread.entries.map(\.card.card.title) == ["Next drive", "Range"])
        #expect(thread.entries[0].card.card.generatedRoot?.text == "5 p.m.")
        #expect(thread.entries[1].card.card.generatedRoot?.text == "210 mi")
        #expect(model.composeCalls == 2)
        let first = try #require(model.composeRequests.first?.prompt)
        let second = try #require(model.composeRequests.last?.prompt)
        #expect(!first.contains("PRIOR FACTS"))
        #expect(second.contains("PRIOR FACTS"))
        #expect(second.contains("FACT-ONE"))
        #expect(second.contains("FACT-TWO"))
        let prior = second.range(of: "FACT-ONE")
        let current = second.range(of: "FACT-TWO")
        #expect(prior != nil && current != nil && prior!.lowerBound < current!.lowerBound)
    }

    @Test @MainActor func savedCardsAreContextOnlyWhenTheAppOptsIn() async throws {
        let off = ScriptedCardModel()
        off.composeResult = AskCardNode(kind: "stat", text: "214 miles")
        let quiet = try followUpAssistant(model: off, passesContext: false)
        _ = await quiet.handle(utterance: "when is my next drive?")
        _ = await quiet.handle(utterance: "what about the range?")
        #expect(off.composeCalls == 2)
        #expect(off.composeRequests.allSatisfy { !$0.prompt.contains("PRIOR FACTS") })

        let on = ScriptedCardModel()
        on.composeResult = AskCardNode(kind: "stat", text: "214 miles")
        let sharing = try followUpAssistant(model: on, passesContext: true)
        _ = await sharing.handle(utterance: "when is my next drive?")
        _ = await sharing.handle(utterance: "what about the range?")
        #expect(on.composeCalls == 2)
        let first = try #require(on.composeRequests.first?.prompt)
        let second = try #require(on.composeRequests.last?.prompt)
        #expect(!first.contains("PRIOR FACTS"))
        #expect(second.contains("PRIOR FACTS"))
        #expect(second.contains("214 miles"))
        #expect(second.contains("Next drive"))
    }

    @MainActor
    private func followUpAssistant(model: ScriptedCardModel, passesContext: Bool) throws -> AskAssistant {
        try AskAssistant(
            AskConfiguration(
                assistantName: "Follow-up",
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
                                facts: "The next drive is at 5 p.m."
                            )
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "nextDrive") },
                guide: AskGuide(replyInstructions: "Rewrite FACTS.", followUpInstructions: ""),
                passesGeneratedFollowUpContext: passesContext
            ),
            model: model.client
        )
    }
}

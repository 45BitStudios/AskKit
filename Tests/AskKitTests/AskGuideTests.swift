import XCTest
@testable import AskKit

@MainActor
final class AskGuideTests: XCTestCase {
    func testRouteInstructionsPutTheOpeningBeforeCapabilitiesAndRules() {
        let guide = AskGuide(
            routeOpening: "Pick one skill id.",
            routeRules: "Dinner is dinner."
        )
        let text = guide.routeInstructions(
            domains: [AskDomain(id: "meals", summary: "Cooking", routingNotes: "Meals.")],
            skills: [
                AskSkill(
                    id: "dinner",
                    domainID: "meals",
                    title: "Dinner",
                    summary: "Suggest dinner",
                    routingNotes: "Dinner.",
                    fulfillment: .reply { _ in AskReply(text: "Pasta.", spoken: "Pasta.") }
                )
            ]
        )
        let opening = text.range(of: "Pick one skill id.")
        let capabilities = text.range(of: "\nCAPABILITIES\n")
        let rules = text.range(of: "\nRULES\n")
        XCTAssertNotNil(opening)
        XCTAssertNotNil(capabilities)
        XCTAssertNotNil(rules)
        XCTAssertLessThan(opening!.lowerBound, capabilities!.lowerBound)
        XCTAssertLessThan(capabilities!.lowerBound, rules!.lowerBound)
        XCTAssertTrue(text.contains("meals: dinner (Suggest dinner)"))
        XCTAssertTrue(text.contains("Dinner is dinner."))
        XCTAssertTrue(text.contains(AskGuide.defaultRouteOpening))
        XCTAssertTrue(text.contains("Return only a skill id copied from CAPABILITIES."))

        let replaced = AskGuide(
            routeOpening: .replace("Only this opening."),
            routeRules: .replace("Only this rule.")
        ).routeInstructions(
            domains: [AskDomain(id: "meals", summary: "Cooking", routingNotes: "Meals.")],
            skills: [
                AskSkill(
                    id: "dinner",
                    domainID: "meals",
                    title: "Dinner",
                    summary: "Suggest dinner",
                    routingNotes: "Dinner.",
                    fulfillment: .reply { _ in AskReply(text: "Pasta.", spoken: "Pasta.") }
                )
            ]
        )
        XCTAssertTrue(replaced.contains("Only this opening."))
        XCTAssertTrue(replaced.contains("Only this rule."))
        XCTAssertFalse(replaced.contains("Do not return a domain name."))
        XCTAssertFalse(replaced.contains("CONTEXT is not a request."))
    }

    func testReplyPromptUsesTheAppSectionAndDropsAKeyValueRewrite() {
        let guide = AskGuide(personLabel: "person")
        let prompt = guide.replyPrompt(
            question: "What's in the pantry",
            skillID: "stock",
            facts: "On hand: pasta and tomatoes.",
            sections: [AskPromptSection(title: "PANTRY", text: "Olive oil is on the shelf.")],
            conversation: "person: What's for dinner?\nAsk Pantry: Tomato pasta."
        )
        XCTAssertTrue(prompt.contains("QUESTION\nWhat's in the pantry"))
        XCTAssertTrue(prompt.contains("SKILL\nstock"))
        XCTAssertTrue(prompt.contains("FACTS\nOn hand: pasta and tomatoes."))
        XCTAssertTrue(prompt.contains("PANTRY\nOlive oil is on the shelf."))
        XCTAssertTrue(prompt.contains("CONVERSATION\nperson: What's for dinner?"))
        XCTAssertTrue(AskGuide.acceptsReply("You have pasta and tomatoes.", facts: "On hand: pasta and tomatoes."))
        XCTAssertFalse(AskGuide.acceptsReply("pantry=pasta", facts: "On hand: pasta and tomatoes."))

        let dumped = """
        You have pasta and tomatoes.

        Olive oil is on the shelf. The freezer has ice cream.
        """
        XCTAssertEqual(AskGuide.spokenAnswer(dumped), "You have pasta and tomatoes.")
        XCTAssertTrue(AskGuide.acceptsReply(dumped, facts: "On hand: pasta and tomatoes."))
        XCTAssertTrue(AskGuide.defaultReplyInstructions.contains("Do not write a second paragraph."))
    }

    func testFollowUpRejectsTheSkillThatJustAnswered() {
        let allowed = ["stock", "shopping"]
        XCTAssertNil(AskGuide.acceptedFollowUp(
            AskFollowUp(skillID: "dinner", question: "What is for dinner?"),
            allowed: allowed,
            after: "stock"
        ))
        XCTAssertNil(AskGuide.acceptedFollowUp(
            AskFollowUp(skillID: "stock", question: "What else is on hand?"),
            allowed: allowed,
            after: "stock"
        ))
        XCTAssertEqual(
            AskGuide.acceptedFollowUp(
                AskFollowUp(skillID: "shopping", question: "What should I buy?"),
                allowed: allowed,
                after: "stock"
            ),
            AskFollowUp(skillID: "shopping", question: "What should I buy?")
        )
        XCTAssertNil(AskGuide.acceptedFollowUp(
            AskFollowUp(skillID: "none", question: ""),
            allowed: allowed,
            after: "stock"
        ))
    }
}

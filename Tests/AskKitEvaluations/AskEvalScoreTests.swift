import Evaluations
import Testing
@testable import AskKit

@Suite("Evaluation scores")
struct AskEvalScoreTests {
    @Test func routeCreditPrefersTheSkillThenTheDomain() {
        #expect(AskEvalScore.routeCredit(gotSkill: "rangeLeft", gotDomain: "trip", expectedSkill: "rangeLeft", expectedDomain: "trip") == 1)
        #expect(AskEvalScore.routeCredit(gotSkill: "RangeLeft", gotDomain: "trip", expectedSkill: "rangeLeft", expectedDomain: "trip") == 1)
        #expect(AskEvalScore.routeCredit(gotSkill: "findCharger", gotDomain: "trip", expectedSkill: "rangeLeft", expectedDomain: "trip") == 0.5)
        #expect(AskEvalScore.routeCredit(gotSkill: "chargeStatus", gotDomain: "battery", expectedSkill: "rangeLeft", expectedDomain: "trip") == 0)
    }

    @Test func aReplyKeepsNumbersOnlyWhenFactsUseTheSameToken() {
        let facts = "The Ioniq 5 battery is at 68 percent. About 32 minutes until 80 percent. Range is 214 miles."
        #expect(AskEvalScore.inventedNumbers(in: "The battery is at 68 percent, about 32 minutes from 80 percent.", facts: facts).isEmpty)
        #expect(AskEvalScore.inventedNumbers(in: "You have 2 miles left.", facts: facts) == ["2"])
        #expect(AskEvalScore.inventedNumbers(in: "The odometer reads 18,420 miles.", facts: "The odometer reads 18,420 miles.").isEmpty)
        #expect(AskEvalScore.states("About 32 minutes until 80 percent.", phrases: ["32", "80 percent"]))
        #expect(!AskEvalScore.states("The battery is charging.", phrases: ["68 percent"]))
    }

    @Test func theReplyRulesRejectAnEqualsSignAndALongLine() {
        #expect(AskGuide.acceptsReply("The battery is at 68 percent.", facts: "68 percent"))
        #expect(!AskGuide.acceptsReply("battery=68", facts: "68 percent"))
        #expect(!AskGuide.acceptsReply(String(repeating: "a", count: 601), facts: "68 percent"))
        #expect(!AskGuide.acceptsReply("   ", facts: "68 percent"))
    }

    @Test func aDomainNameEarnsHalfCreditAndNotTheSkill() {
        #expect(AskEvalScore.resolvedDomain(of: "cabin", skills: [("precondition", "cabin")], domains: ["cabin", "trip"]) == "cabin")
        #expect(AskEvalScore.resolvedDomain(of: "precondition", skills: [("precondition", "cabin")], domains: ["cabin"]) == "cabin")
        #expect(AskEvalScore.resolvedDomain(of: "nope", skills: [], domains: ["cabin"]) == "")
        #expect(AskEvalScore.routeCredit(gotSkill: "cabin", gotDomain: "cabin", expectedSkill: "precondition", expectedDomain: "cabin") == 0.5)
    }

    @Test func theAnswerStopsBeforeTheGarageParagraph() {
        let written = """
        The battery is at 68 percent. Charging at home. About 32 minutes until 80 percent.

        The car is an Ioniq 5, plugged in at home, charging at 11 kW.
        """
        let facts = "The Ioniq 5 battery is at 68 percent. Charging at home. About 32 minutes until 80 percent."
        let answer = AskEvalScore.answerParagraph(written)
        #expect(answer == "The battery is at 68 percent. Charging at home. About 32 minutes until 80 percent.")
        #expect(AskGuide.spokenAnswer(written) == answer)
        #expect(AskGuide.acceptsReply(written, facts: facts))
        #expect(AskEvalScore.sentenceCount(answer) == 3)
        #expect(AskEvalScore.inventedNumbers(in: answer, facts: facts).isEmpty)
        #expect(AskEvalScore.hasBackgroundCopy(written))
        #expect(!AskEvalScore.hasBackgroundCopy(answer))
    }

    @Test func sentenceCountIgnoresDecimalsAndMorningTimes() {
        #expect(AskEvalScore.sentenceCount("The charger is 0.4 miles away.") == 1)
        #expect(AskEvalScore.sentenceCount("The cabin will be 72 degrees by 7:30 a.m.") == 1)
        #expect(AskEvalScore.sentenceCount("Range is 214 miles. Eco mode is on.") == 2)
        #expect(AskEvalScore.sentenceCount("One. Two. Three.") == 3)
    }

    @Test func aFollowUpMustBeADifferentAllowedQuestion() {
        let allowed = ["rangeLeft", "findCharger"]
        #expect(AskEvalScore.acceptedFollowUp(AskFollowUp(skillID: "rangeLeft", question: "How much range is left?"), allowed: allowed, after: "chargeStatus"))
        #expect(!AskEvalScore.acceptedFollowUp(AskFollowUp(skillID: "chargeStatus", question: "How full is it?"), allowed: allowed, after: "chargeStatus"))
        #expect(!AskEvalScore.acceptedFollowUp(AskFollowUp(skillID: "none", question: "Anything else?"), allowed: allowed, after: "chargeStatus"))
        #expect(!AskEvalScore.acceptedFollowUp(AskFollowUp(skillID: "rangeLeft", question: "range=214"), allowed: allowed, after: "chargeStatus"))
        #expect(!AskEvalScore.acceptedFollowUp(AskFollowUp(skillID: "rangeLeft", question: String(repeating: "a", count: 141)), allowed: allowed, after: "chargeStatus"))
        #expect(AskEvalScore.wordCount("How much range is left?") == 5)
    }

    @Test func theGarageCatalogCoversEverySkillOnce() throws {
        let ids = AskEvalCatalog.skills.map(\.id)
        #expect(ids.count == 19)
        #expect(Set(ids).count == 19)
        #expect(AskEvalCatalog.domain(of: "cabin") == "cabin")
        #expect(AskEvalCatalog.domain(of: "chargeStatus") == "battery")
        #expect(AskEvalCatalog.domain(of: "nope") == "")
        for sample in AskEvalCatalog.routeSamples {
            let gold = try #require(sample.expected)
            #expect(ids.contains(gold.skillID))
        }
        for sample in AskEvalCatalog.followUpSamples {
            let gold = try #require(sample.expected)
            #expect(!gold.plausibleSkillIDs.contains(gold.answeredSkillID))
            #expect(gold.plausibleSkillIDs.allSatisfy { ids.contains($0) })
            #expect(gold.allowedSkillIDs.allSatisfy { ids.contains($0) })
        }
    }
}

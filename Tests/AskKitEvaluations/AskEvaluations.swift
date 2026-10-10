import Evaluations
import Foundation
import FoundationModels
import Testing
@testable import AskKit

/// The on-device model picks one Garage skill. Accuracy is the gold skill. Credit gives half a point for the right domain.
struct AskRoutingEvaluation: Evaluation {
    var dataset = ArrayLoader(samples: AskEvalCatalog.routeSamples)

    let skillMatch = Metric("Skill match")
    let domainMatch = Metric("Domain match")
    let routeCredit = Metric("Route credit")

    func subject(from sample: ModelSample<AskRouteLabel>) async throws -> ModelSubject<AskRouteLabel> {
        let gold = sample.expected ?? AskRouteLabel(skillID: "", domainID: "", earlier: [])
        let choice = try await AskEvalSessions.route(
            AskEvalCatalog.routeRequest(question: sample.promptDescription, earlier: gold.earlier)
        )
        return ModelSubject(value: AskRouteLabel(
            skillID: choice.skillID,
            domainID: AskEvalCatalog.domain(of: choice.skillID),
            earlier: gold.earlier
        ))
    }

    var evaluators: Evaluators {
        Evaluator { sample, subject in
            let expected = sample.expected?.skillID ?? ""
            let got = subject.value.skillID
            if AskEvalScore.same(got, expected) {
                return skillMatch.passing(rationale: got)
            }
            return skillMatch.failing(rationale: "Got \(got), expected \(expected)")
        }
        Evaluator { sample, subject in
            let expected = sample.expected?.domainID ?? ""
            let got = subject.value.domainID
            if AskEvalScore.same(got, expected) {
                return domainMatch.passing(rationale: got)
            }
            return domainMatch.failing(rationale: "Got \(got), expected \(expected)")
        }
        Evaluator { sample, subject in
            let gold = sample.expected ?? AskRouteLabel(skillID: "", domainID: "", earlier: [])
            let credit = AskEvalScore.routeCredit(
                gotSkill: subject.value.skillID,
                gotDomain: subject.value.domainID,
                expectedSkill: gold.skillID,
                expectedDomain: gold.domainID
            )
            return routeCredit.scoring(credit, rationale: subject.value.skillID)
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.group("Accuracy") { group in
            group.computeMean(of: skillMatch)
            group.computeMean(of: domainMatch)
        }
        aggregator.group("Score") { group in
            group.computeMean(of: routeCredit)
            group.computeMinimum(of: routeCredit)
        }
    }
}

/// The rewrite of one skill's facts.
/// The answer is the paragraph before a blank line. A later paragraph is the garage background, which the prompt says not to copy.
/// A model judge is not used here. On a measured run it scored a 19-sentence garage copy as 4.
struct AskSkillEvaluation: Evaluation {
    var dataset = ArrayLoader(samples: AskEvalCatalog.replySamples)

    let keyFacts = Metric("Key facts")
    let numbersFromFacts = Metric("Numbers from FACTS")
    let twoSentences = Metric("One or two sentences")
    let kept = Metric("Rewrite kept")
    let noBackground = Metric("No background copy")

    func subject(from sample: ModelSample<AskReplyLabel>) async throws -> ModelSubject<AskReplyLabel> {
        let gold = sample.expected ?? AskReplyLabel(text: "", skillID: "", facts: "", requiredPhrases: [])
        let skill = AskEvalCatalog.skill(gold.skillID) ?? AskEvalCatalog.skills[0]
        let text = try await AskEvalSessions.reply(AskEvalCatalog.replyRequest(question: sample.promptDescription, skill: skill))
        return ModelSubject(value: AskReplyLabel(
            text: text,
            skillID: gold.skillID,
            facts: gold.facts,
            requiredPhrases: gold.requiredPhrases
        ))
    }

    var evaluators: Evaluators {
        Evaluator { _, subject in
            let answer = AskEvalScore.answerParagraph(subject.value.text)
            if AskEvalScore.states(answer, phrases: subject.value.requiredPhrases) {
                return keyFacts.passing(rationale: answer)
            }
            return keyFacts.failing(rationale: answer)
        }
        Evaluator { _, subject in
            let answer = AskEvalScore.answerParagraph(subject.value.text)
            let invented = AskEvalScore.inventedNumbers(in: answer, facts: subject.value.facts)
            if invented.isEmpty {
                return numbersFromFacts.passing(rationale: answer)
            }
            return numbersFromFacts.failing(rationale: invented.joined(separator: ", "))
        }
        Evaluator { _, subject in
            let answer = AskEvalScore.answerParagraph(subject.value.text)
            let count = AskEvalScore.sentenceCount(answer)
            if (1...2).contains(count) {
                return twoSentences.passing(rationale: answer)
            }
            return twoSentences.failing(rationale: "\(count) sentences: \(answer)")
        }
        Evaluator { _, subject in
            if AskGuide.acceptsReply(subject.value.text, facts: subject.value.facts) {
                return kept.passing(rationale: "\(subject.value.text.count) characters")
            }
            return kept.failing(rationale: "Rejected \(subject.value.text.count) characters")
        }
        Evaluator { _, subject in
            if AskEvalScore.hasBackgroundCopy(subject.value.text) {
                return noBackground.failing(rationale: "\(AskEvalScore.sentenceCount(subject.value.text)) sentences")
            }
            return noBackground.passing()
        }
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.group("Answer") { group in
            group.computeMean(of: keyFacts)
            group.computeMean(of: numbersFromFacts)
            group.computeMean(of: twoSentences)
        }
        aggregator.group("Rewrite") { group in
            group.computeMean(of: kept)
            group.computeMean(of: noBackground)
        }
    }
}

/// The next question after one answer. It must pass the chat's follow-up rule, stay under 12 words, and name a plausible next skill.
struct AskFollowUpEvaluation: Evaluation {
    var dataset = ArrayLoader(samples: AskEvalCatalog.followUpSamples)

    let accepted = Metric("Accepted follow-up")
    let plausible = Metric("Plausible skill")
    let brief = Metric("Under 12 words")

    let relevance = ScoreDimension(
        "Relevance",
        description: "Whether the question is a natural next ask about the offered skill, after the question that was just answered. It must not repeat that question or invent a new fact.",
        scale: .numeric([
            4: "A person who just heard the answer would ask this next",
            3: "Related to the car, and about the offered skill",
            2: "About the car, but not a likely next question",
            1: "Unrelated, or it repeats the question that was just answered"
        ])
    )

    func subject(from sample: ModelSample<AskFollowUpLabel>) async throws -> ModelSubject<AskFollowUpLabel> {
        let gold = sample.expected ?? AskFollowUpLabel(
            skillID: "", question: "", answeredSkillID: "", allowedSkillIDs: [], plausibleSkillIDs: [], justAsked: "", spoken: ""
        )
        let choice = try await AskEvalSessions.followUp(AskEvalCatalog.followUpRequest(gold))
        var value = gold
        value.skillID = choice.skillID
        value.question = choice.question
        return ModelSubject(value: value)
    }

    var evaluators: Evaluators {
        Evaluator { _, subject in
            let choice = AskFollowUp(skillID: subject.value.skillID, question: subject.value.question)
            if AskEvalScore.acceptedFollowUp(choice, allowed: subject.value.allowedSkillIDs, after: subject.value.answeredSkillID) {
                return accepted.passing(rationale: "\(subject.value.skillID): \(subject.value.question)")
            }
            return accepted.failing(rationale: "\(subject.value.skillID): \(subject.value.question)")
        }
        Evaluator { _, subject in
            let choice = AskFollowUp(skillID: subject.value.skillID, question: subject.value.question)
            guard AskEvalScore.acceptedFollowUp(choice, allowed: subject.value.allowedSkillIDs, after: subject.value.answeredSkillID) else {
                return plausible.ignore(rationale: "Rejected \(subject.value.skillID)")
            }
            let hit = subject.value.plausibleSkillIDs.contains { AskEvalScore.same($0, subject.value.skillID) }
            if hit {
                return plausible.passing(rationale: subject.value.skillID)
            }
            return plausible.failing(rationale: "Got \(subject.value.skillID)")
        }
        Evaluator { _, subject in
            let words = AskEvalScore.wordCount(subject.value.question)
            if (1...12).contains(words) {
                return brief.passing(rationale: "\(words) words")
            }
            return brief.failing(rationale: "\(words) words")
        }
        ModelJudgeEvaluator(
            judge: SystemLanguageModel.default,
            dimensions: [relevance],
            prompt: ModelJudgePrompt(
                instructions: "You judge the next question a car assistant offers after it has just answered. The offered skill must be different from the skill that just answered. Repeating that skill, or restating the question just asked, scores 1.",
                evaluationTarget: { value in
                    "Offered skill: \(value.skillID)\nOffered question: \(value.question)"
                },
                reference: { _, value in
                    [
                        "Just asked": value.justAsked,
                        "Just answered": value.spoken,
                        "Skill just answered": value.answeredSkillID
                    ]
                }
            )
        )
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.group("Rules") { group in
            group.computeMean(of: accepted)
            group.computeMean(of: plausible)
            group.computeMean(of: brief)
        }
        aggregator.group("Quality") { group in
            group.computeMean(of: relevance.metric)
        }
    }
}

@Suite("Ask evaluations")
struct AskEvaluationTests {
    static let routing = AskRoutingEvaluation()
    static let skills = AskSkillEvaluation()
    static let followUps = AskFollowUpEvaluation()

    static let info = [
        "ModelName": "SystemLanguageModel",
        "Feature": "Ask Garage routing, replies, and follow-ups"
    ]

    @Test("Routing", .enabled(if: AskEvalRun.isOn, "Set TEST_RUNNER_ASKKIT_EVALUATIONS=1 on a simulator with Apple Intelligence"), .evaluates(routing, info: info))
    func evaluateRouting() {
        let result = EvaluationContext.current.result
        print(result.groupedSummary)
        #expect(result.aggregateValue(.mean(of: Self.routing.skillMatch)) >= 0.60, "\(result.groupedSummary)")
        #expect(result.aggregateValue(.mean(of: Self.routing.domainMatch)) >= 0.80)
        #expect(result.aggregateValue(.mean(of: Self.routing.routeCredit)) >= 0.70)
    }

    @Test("Skills", .enabled(if: AskEvalRun.isOn, "Set TEST_RUNNER_ASKKIT_EVALUATIONS=1 on a simulator with Apple Intelligence"), .evaluates(skills, info: info))
    func evaluateSkills() {
        let result = EvaluationContext.current.result
        print(result.groupedSummary)
        #expect(result.aggregateValue(.mean(of: Self.skills.keyFacts)) >= 0.80, "\(result.groupedSummary)")
        #expect(result.aggregateValue(.mean(of: Self.skills.numbersFromFacts)) >= 0.60)
        #expect(result.aggregateValue(.mean(of: Self.skills.twoSentences)) >= 0.50)
        #expect(result.aggregateValue(.mean(of: Self.skills.noBackground)) >= 0.80, "\(result.groupedSummary)")
    }

    @Test("Follow-ups", .enabled(if: AskEvalRun.isOn, "Set TEST_RUNNER_ASKKIT_EVALUATIONS=1 on a simulator with Apple Intelligence"), .evaluates(followUps, info: info))
    func evaluateFollowUps() {
        let result = EvaluationContext.current.result
        print(result.groupedSummary)
        #expect(result.aggregateValue(.mean(of: Self.followUps.accepted)) >= 0.50, "\(result.groupedSummary)")
        #expect(result.aggregateValue(.mean(of: Self.followUps.brief)) >= 0.80)
    }
}

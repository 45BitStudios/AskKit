import AskKit
import Foundation

/// A short skill description the sample apps turn into a card or a reply.
struct SampleSkillSpec {
    var id: String
    var domainID: String
    var title: String
    var summary: String
    var routingNotes: String
    var spoken: String
    var facts: String
    var headline: String
    var detail: String
    var actionTitle: String
    var covered: [String] = []
    var replyOnly: Bool = false
    /// Uses AskKit's card DSL instead of a host-drawn SwiftUI card.
    var generatedCard: Bool = false
    /// Status line while this skill runs, before the reply rewrite.
    var workingTitle: String = ""
}

enum SampleSkill {
    nonisolated static func make(_ spec: SampleSkillSpec) -> AskSkill {
        let line = workingTitle(for: spec)
        if spec.replyOnly {
            return AskSkill(
                id: spec.id,
                domainID: spec.domainID,
                title: spec.title,
                summary: spec.summary,
                routingNotes: spec.routingNotes,
                fulfillment: .reply { _ in
                    AskChatActivity.update(line)
                    return AskReply(
                        text: spec.spoken,
                        spoken: spec.spoken,
                        actions: [AskAction(id: spec.id, title: spec.actionTitle)],
                        facts: spec.facts
                    )
                }
            )
        }
        if spec.generatedCard {
            return AskSkill(
                id: spec.id,
                domainID: spec.domainID,
                title: spec.title,
                summary: spec.summary,
                routingNotes: spec.routingNotes,
                fulfillment: .generated { _ in
                    AskChatActivity.update(line)
                    return AskGeneratedBlueprint(
                        title: spec.title,
                        spoken: spec.spoken,
                        facts: spec.facts,
                        coveredPhrases: spec.covered,
                        actions: [AskAction(id: spec.id, title: spec.actionTitle)],
                        root: AskGeneratedCard.factTree(
                            title: spec.title,
                            value: spec.headline,
                            detail: spec.detail
                        )
                    )
                }
            )
        }
        return AskSkill(
            id: spec.id,
            domainID: spec.domainID,
            title: spec.title,
            summary: spec.summary,
            routingNotes: spec.routingNotes,
            fulfillment: .intent { _ in
                AskChatActivity.update(line)
                return AskIntentCard(
                    title: spec.title,
                    spoken: spec.spoken,
                    coveredPhrases: spec.covered,
                    action: AskAction(id: spec.id, title: spec.actionTitle),
                    facts: spec.facts,
                    view: SampleFactCard(
                        title: spec.title,
                        headline: spec.headline,
                        detail: spec.detail
                    )
                )
            }
        )
    }

    /// The skill id typed alone matches first. Otherwise the first phrase contained in the question wins.
    nonisolated static func route(
        _ utterance: String,
        ids: [String],
        keywords: [(String, [String])]
    ) -> AskRoute? {
        let folded = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !folded.isEmpty else { return nil }
        if let id = ids.first(where: { $0.lowercased() == folded }) {
            return AskRoute(skillID: id)
        }
        for (skillID, phrases) in keywords {
            if phrases.contains(where: { folded.contains($0) }) {
                return AskRoute(skillID: skillID)
            }
        }
        return nil
    }

    nonisolated static func workingTitle(for spec: SampleSkillSpec) -> String {
        let custom = spec.workingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return "Checking \(spec.title.lowercased())"
    }
}

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
}

enum SampleSkill {
    nonisolated static func make(_ spec: SampleSkillSpec) -> AskSkill {
        if spec.replyOnly {
            return AskSkill(
                id: spec.id,
                domainID: spec.domainID,
                title: spec.title,
                summary: spec.summary,
                routingNotes: spec.routingNotes,
                fulfillment: .reply { _ in
                    AskReply(
                        text: spec.spoken,
                        spoken: spec.spoken,
                        actions: [AskAction(id: spec.id, title: spec.actionTitle)],
                        facts: spec.facts
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
                AskIntentCard(
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
}

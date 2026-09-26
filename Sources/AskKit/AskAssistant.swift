import Foundation
import SwiftData

enum AskFollowUp {
    private static let phrases = ["what about", "how about", "also"]

    static func resolve(_ utterance: String, priorUserQuestions: [String]) -> String {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFollowUp(trimmed), let previous = priorUserQuestions.last?.trimmingCharacters(in: .whitespacesAndNewlines), !previous.isEmpty else {
            return trimmed
        }
        return previous + "\n" + trimmed
    }

    static func isFollowUp(_ utterance: String) -> Bool {
        let lower = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return phrases.contains { phrase in
            lower == phrase || lower.hasPrefix(phrase + " ") || lower.hasPrefix(phrase + ",")
        }
    }
}

private struct RoutedTurn {
    var skillID: String?
    var slots: [String: String]
    var usedModel: Bool
}

@MainActor
public struct AskAssistant {
    public let configuration: AskConfiguration
    public let modelContainer: ModelContainer
    private let store: AskStore
    private let model: AskModelClient

    public init(_ configuration: AskConfiguration, model: AskModelClient = .foundation) throws {
        self.configuration = configuration
        let store = try AskStore(persistence: configuration.persistence)
        self.store = store
        self.modelContainer = store.container
        self.model = model
    }

    public func chips() async -> [AskChip] {
        let context = await configuration.context()
        return Array(configuration.chips(context).prefix(3))
    }

    public func handle(utterance: String, priorUserQuestions: [String] = []) async -> AskTurnResult {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = await configuration.context()
        let stored = (try? store.recentUserTexts(assistantName: configuration.assistantName)) ?? []
        let priors = priorUserQuestions.isEmpty ? stored : priorUserQuestions
        let routedUtterance = AskFollowUp.resolve(trimmed, priorUserQuestions: priors)
        try? store.appendUser(assistantName: configuration.assistantName, text: trimmed)
        let routed = await route(utterance: routedUtterance, context: context)
        return await fulfill(routed, utterance: routedUtterance, context: context)
    }

    /// A chip already chose the skill. This does not open a model session.
    public func handle(chip: AskChip) async -> AskTurnResult {
        let context = await configuration.context()
        try? store.appendUser(assistantName: configuration.assistantName, text: chip.title)
        let routed = RoutedTurn(skillID: chip.skillID, slots: chip.slots, usedModel: false)
        return await fulfill(routed, utterance: chip.title, context: context)
    }

    public func transcript() throws -> [AskTranscriptTurn] {
        try store.transcript(assistantName: configuration.assistantName)
    }

    public func clearThread() throws {
        try store.clear(assistantName: configuration.assistantName)
    }

    /// Draws an intent card again from the stored turn. The view is not stored.
    public func intentCard(for turnID: UUID) async -> AskIntentCard? {
        guard let turns = try? transcript(),
              let index = turns.firstIndex(where: { $0.id == turnID }) else {
            return nil
        }
        let turn = turns[index]
        guard turn.role == "assistant",
              let skill = configuration.skill(id: turn.skillID),
              case .intent(let make) = skill.fulfillment else {
            return nil
        }
        let utterance = turns[..<index].last { $0.role == "user" }?.text ?? turn.text
        let snapshot = await configuration.context()
        let invocation = AskInvocation(
            utterance: utterance,
            skillID: skill.id,
            domainID: skill.domainID,
            slots: AskSlots.decode(turn.slotsJSON),
            context: await contextForSkill(skill, fallback: snapshot),
            usedModel: false
        )
        return await make(invocation)
    }

    private func route(utterance: String, context: AskContext) async -> RoutedTurn {
        if let fast = fastRoute(utterance) {
            return await filling(fast, utterance: utterance, context: context, usedModel: false)
        }
        do {
            let domainRequest = AskModelRequest(
                instructions: AskPrompts.domainInstructions(
                    assistantName: configuration.assistantName,
                    domains: configuration.domains
                ),
                prompt: AskPrompts.userPrompt(context: context.promptBlock, utterance: utterance)
            )
            let domainID = try await model.routeDomain(domainRequest)
            guard let domain = configuration.domain(id: domainID) else {
                return fallback(utterance)
            }
            let skills = configuration.skills(in: domain.id)
            let skillRequest = AskModelRequest(
                instructions: AskPrompts.skillInstructions(
                    assistantName: configuration.assistantName,
                    domain: domain,
                    skills: skills
                ),
                prompt: AskPrompts.userPrompt(context: context.promptBlock, utterance: utterance)
            )
            let choice = try await model.routeSkill(skillRequest)
            guard let skill = skills.first(where: { $0.id.compare(choice.skillID, options: .caseInsensitive) == .orderedSame }) else {
                return fallback(utterance)
            }
            let routed = RoutedTurn(skillID: skill.id, slots: choice.slots, usedModel: true)
            return await filling(routed, utterance: utterance, context: context, usedModel: true)
        } catch {
            return fallback(utterance)
        }
    }

    private func fastRoute(_ utterance: String) -> RoutedTurn? {
        guard let route = configuration.fastPath?(utterance), configuration.skill(id: route.skillID) != nil else {
            return nil
        }
        return RoutedTurn(skillID: route.skillID, slots: route.slots, usedModel: false)
    }

    private func fallback(_ utterance: String) -> RoutedTurn {
        if let fast = fastRoute(utterance) {
            return fast
        }
        if configuration.skill(id: "unknown") != nil {
            return RoutedTurn(skillID: "unknown", slots: [:], usedModel: false)
        }
        return RoutedTurn(skillID: nil, slots: [:], usedModel: false)
    }

    private func filling(_ routed: RoutedTurn, utterance: String, context: AskContext, usedModel: Bool) async -> RoutedTurn {
        guard let skillID = routed.skillID, let skill = configuration.skill(id: skillID) else {
            return routed
        }
        guard !AskSlots.hasValues(routed.slots, for: skill.requiredSlots) else {
            return RoutedTurn(skillID: skill.id, slots: routed.slots, usedModel: usedModel)
        }
        let tools = configuration.tools?(skill.domainID) ?? []
        guard AskSessionPolicy.acceptedSkillToolCount(tools.count) != nil else {
            return RoutedTurn(skillID: skill.id, slots: routed.slots, usedModel: usedModel)
        }
        let request = AskModelRequest(
            instructions: AskPrompts.fillInstructions(skill: skill),
            prompt: AskPrompts.userPrompt(context: context.promptBlock, utterance: utterance, slots: routed.slots)
        )
        do {
            let filled = try await model.fillSlots(request, tools)
            return RoutedTurn(
                skillID: skill.id,
                slots: AskSlots.merging(filled, into: routed.slots),
                usedModel: true
            )
        } catch {
            return RoutedTurn(skillID: skill.id, slots: routed.slots, usedModel: usedModel)
        }
    }

    private func contextForSkill(_ skill: AskSkill, fallback: AskContext) async -> AskContext {
        if let contextForSkill = configuration.contextForSkill {
            return await contextForSkill(skill.id, skill.contextKeys)
        }
        return skill.contextKeys.isEmpty ? fallback : fallback.scoped(to: skill.contextKeys)
    }

    private func fulfill(_ routed: RoutedTurn, utterance: String, context: AskContext) async -> AskTurnResult {
        let skill = routed.skillID.flatMap { configuration.skill(id: $0) } ?? configuration.skill(id: "unknown")
        guard let skill else {
            let reply = AskReply(text: "I can't help with that.", spoken: "I can't help with that.")
            try? store.appendAssistant(
                assistantName: configuration.assistantName,
                text: reply.text,
                spoken: reply.spoken,
                skillID: "",
                domainID: "",
                slots: [:],
                omitting: configuration.omittedSlotKeys
            )
            return AskTurnResult(skillID: "", domainID: "", slots: [:], usedModel: routed.usedModel, fulfillment: .reply(reply))
        }
        let invocation = AskInvocation(
            utterance: utterance,
            skillID: skill.id,
            domainID: skill.domainID,
            slots: routed.slots,
            context: await contextForSkill(skill, fallback: context),
            usedModel: routed.usedModel
        )
        switch skill.fulfillment {
        case .reply(let make):
            let reply = await make(invocation)
            try? store.appendAssistant(
                assistantName: configuration.assistantName,
                text: reply.text,
                spoken: reply.spoken,
                skillID: skill.id,
                domainID: skill.domainID,
                slots: routed.slots,
                omitting: configuration.omittedSlotKeys
            )
            return AskTurnResult(
                skillID: skill.id,
                domainID: skill.domainID,
                slots: routed.slots,
                usedModel: routed.usedModel,
                fulfillment: .reply(reply)
            )
        case .intent(let make):
            let card = await make(invocation)
            try? store.appendAssistant(
                assistantName: configuration.assistantName,
                text: card.spoken,
                spoken: card.spoken,
                skillID: skill.id,
                domainID: skill.domainID,
                slots: routed.slots,
                omitting: configuration.omittedSlotKeys
            )
            return AskTurnResult(
                skillID: skill.id,
                domainID: skill.domainID,
                slots: routed.slots,
                usedModel: routed.usedModel,
                fulfillment: .intent(card)
            )
        }
    }
}

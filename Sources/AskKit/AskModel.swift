import Foundation
import FoundationModels

public enum AskSessionPolicy {
    public static let maxToolsPerSession = 5
    /// Router sessions are constructed with no tools.
    public static let routerToolCount = 0

    /// A skill session may carry 1...5 tools. Zero skips the session. More than five is rejected.
    public static func acceptedSkillToolCount(_ count: Int) -> Int? {
        guard (1...maxToolsPerSession).contains(count) else { return nil }
        return count
    }
}

enum AskTranscript {
    static func withoutToolCalls(_ entries: [Transcript.Entry]) -> [Transcript.Entry] {
        entries.filter { entry in
            switch entry {
            case .toolCalls, .toolOutput:
                return false
            default:
                return true
            }
        }
    }
}

@Generable
struct AskDomainChoice {
    @Guide(description: "One domain id copied from the allowed list")
    var domain: String
}

@Generable
struct AskSlotValue {
    @Guide(description: "Slot name")
    var key: String
    @Guide(description: "Slot value heard in the request")
    var value: String
}

@Generable
struct AskSkillChoice {
    @Guide(description: "One skill id copied from the allowed list")
    var skill: String
    var confidence: Double
    @Guide(description: "Slots heard in the request. Leave empty when none were said.")
    var slots: [AskSlotValue]
}

struct AskRoutingProfile: LanguageModelSession.DynamicProfile {
    var instructions: String

    var body: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instructions)
        }
        .toolCallingMode(.disallowed)
        .historyTransform(AskTranscript.withoutToolCalls)
    }
}

struct AskSkillProfile: LanguageModelSession.DynamicProfile {
    var instructions: String
    var tools: [any Tool]

    var body: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instructions)
            tools
        }
        .toolCallingMode(.allowed)
        .historyTransform(AskTranscript.withoutToolCalls)
    }
}

enum AskFoundationSessions {
    static func routeDomain(_ request: AskModelRequest) async throws -> String {
        let session = LanguageModelSession(profile: AskRoutingProfile(instructions: request.instructions))
        let response = try await session.respond(to: request.prompt, generating: AskDomainChoice.self)
        return response.content.domain
    }

    static func routeSkill(_ request: AskModelRequest) async throws -> AskModelSkillChoice {
        let session = LanguageModelSession(profile: AskRoutingProfile(instructions: request.instructions))
        let response = try await session.respond(to: request.prompt, generating: AskSkillChoice.self)
        let slots = Dictionary(response.content.slots.map { ($0.key, $0.value) }, uniquingKeysWith: { _, latest in latest })
        return AskModelSkillChoice(skillID: response.content.skill, slots: slots, confidence: response.content.confidence)
    }

    static func fillSlots(_ request: AskModelRequest, tools: [any Tool]) async throws -> [String: String] {
        let session = LanguageModelSession(
            profile: AskSkillProfile(instructions: request.instructions, tools: tools)
        )
        let response = try await session.respond(to: request.prompt, generating: AskSkillChoice.self)
        return Dictionary(response.content.slots.map { ($0.key, $0.value) }, uniquingKeysWith: { _, latest in latest })
    }
}

enum AskPrompts {
    static func domainInstructions(assistantName: String, domains: [AskDomain]) -> String {
        let lines = domains.map { domain in
            "- \(domain.id): \(domain.summary) \(domain.routingNotes)"
        }.joined(separator: "\n")
        return """
        You are the receptionist for \(assistantName).
        Pick one domain id. Do not answer the question. Do not invent facts.
        Domains:
        \(lines)
        """
    }

    static func skillInstructions(assistantName: String, domain: AskDomain, skills: [AskSkill]) -> String {
        let lines = skills.map { skill in
            let slots = skill.requiredSlots.isEmpty ? "" : " Slots: \(skill.requiredSlots.joined(separator: ", "))."
            return "- \(skill.id): \(skill.summary) \(skill.routingNotes)\(slots)"
        }.joined(separator: "\n")
        return """
        You are the receptionist for \(assistantName).
        Pick one skill id in domain \(domain.id). Do not answer the question. Do not invent facts.
        Allowed:
        \(lines)
        """
    }

    static func fillInstructions(skill: AskSkill) -> String {
        """
        Fill missing slots for \(skill.id). Required: \(skill.requiredSlots.joined(separator: ", ")).
        Use the tools. Do not invent values the tools did not return.
        """
    }

    static func userPrompt(context: String, utterance: String, slots: [String: String] = [:]) -> String {
        let slotLine = slots
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return """
        CONTEXT
        \(context)

        SLOTS
        \(slotLine)

        REQUEST
        \(utterance)
        """
    }
}

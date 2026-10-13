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
    /// What a tool-free structured session may see. Drops tool calls, tool output,
    /// and reasoning. A reasoning signature replayed into a structured generation
    /// throws unsupportedTranscriptContent. Prompts and responses stay, in order.
    static func forRouting(_ entries: [Transcript.Entry]) -> [Transcript.Entry] {
        entries.filter { entry in
            switch entry {
            case .toolCalls, .toolOutput, .reasoning:
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

@Generable
struct AskFollowUpDraft {
    @Guide(description: "One skill id copied from ALLOWED, or none")
    var skill: String
    @Guide(description: "One short question, or empty when skill is none")
    var question: String
}

extension AskCloudReasoning {
    var level: ContextOptions.ReasoningLevel {
        switch self {
        case .light: .light
        case .moderate: .moderate
        case .deep: .deep
        }
    }
}

struct AskCloudSessionOptions: Sendable {
    var reasoningLevel: ContextOptions.ReasoningLevel
    var temperature: Double?
}

enum AskModelAvailability {
    static func onDevice(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "deviceNotEligible"
        case .appleIntelligenceNotEnabled: "appleIntelligenceNotEnabled"
        case .modelNotReady: "modelNotReady"
        @unknown default: "unavailable"
        }
    }

    static func cloud(_ reason: PrivateCloudComputeLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "deviceNotEligible"
        case .systemNotReady: "systemNotReady"
        @unknown default: "unavailable"
        }
    }
}

enum AskComputeRuntime {
    struct Resolved {
        var model: any LanguageModel
        var cloud: AskCloudSessionOptions?
        var maximumResponseTokens: Int?
    }

    /// The model the next session should call. Records the resolved choice on the open trace span.
    static func resolve() async -> Resolved {
        let onDevice = SystemLanguageModel.default
        let cloud = PrivateCloudComputeLanguageModel()
        let online = AskNetwork.isOnline
        let choice = AskComputeChoice.resolved(
            preferred: AskComputeSelection.current,
            onDevice: onDevice.isAvailable,
            cloud: cloud.isAvailable,
            online: online
        )
        AskTrace.attribute("compute", choice.rawValue)
        if case .unavailable(let reason) = onDevice.availability {
            AskTrace.attribute("onDevice", AskModelAvailability.onDevice(reason))
        }
        if !online {
            AskTrace.attribute("privateCloud", "offline")
        } else if case .unavailable(let reason) = cloud.availability {
            AskTrace.attribute("privateCloud", AskModelAvailability.cloud(reason))
        }
        let contextSize: Int
        switch choice {
        case .onDevice:
            contextSize = onDevice.contextSize
        case .privateCloud:
            contextSize = await AskReplyBudget.rememberPrivateCloudContextSize(cloud)
        }
        let maxTokens = AskReplyBudget.generationTokenLimit()
        if let maxTokens {
            AskTrace.attribute("maxTokens", String(maxTokens))
        }
        AskTrace.attribute("contextSize", String(contextSize))
        switch choice {
        case .onDevice:
            return Resolved(model: onDevice, cloud: nil, maximumResponseTokens: maxTokens)
        case .privateCloud:
            let options = AskCloudSettings.current
            AskTrace.attribute("reasoning", options.reasoning.rawValue)
            if let temperature = options.temperature {
                AskTrace.attribute("temperature", String(temperature))
            }
            return Resolved(
                model: cloud,
                cloud: AskCloudSessionOptions(
                    reasoningLevel: options.reasoning.level,
                    temperature: options.temperature
                ),
                maximumResponseTokens: maxTokens
            )
        }
    }
}

enum AskProfileActivity: Sendable {
    case quiet
    case choosing
    case writing
    case specialist(id: String, title: String, workingTitle: String)
}

enum AskProfileHooks {
    static func activate(_ activity: AskProfileActivity) async {
        switch activity {
        case .quiet:
            break
        case .choosing:
            AskTrace.event("activate router")
            await AskChatActivity.show("Looking at the question", phase: .choosing)
        case .writing:
            AskTrace.event("activate writer")
            await AskChatActivity.show("Writing an answer", phase: .writing)
        case .specialist(let id, let title, let workingTitle):
            AskTrace.event("activate \(id)")
            let line = workingTitle.isEmpty ? title : workingTitle
            await AskChatActivity.show(line, detail: title, phase: .choosing)
        }
    }

    static func toolCall(_ activity: AskProfileActivity, toolName: String) async {
        AskTrace.event("tool call \(toolName)")
        guard case .specialist(_, let title, _) = activity else { return }
        let name = title.isEmpty ? "the tool" : title
        await AskChatActivity.show("Reading \(name)", detail: title, phase: .tool)
    }

    static func toolOutput(_ activity: AskProfileActivity, toolName: String) async {
        AskTrace.event("tool output \(toolName)")
        guard case .specialist(_, let title, _) = activity else { return }
        let name = title.isEmpty ? "Tool" : title
        await AskChatActivity.show("\(name) is in", detail: title, phase: .tool)
    }

    static func response(_ activity: AskProfileActivity) async {
        switch activity {
        case .quiet:
            break
        case .choosing:
            AskTrace.event("response router")
        case .writing:
            AskTrace.event("response writer")
        case .specialist(let id, _, _):
            AskTrace.event("response \(id)")
        }
    }

    static func deactivate(_ activity: AskProfileActivity) {
        switch activity {
        case .quiet, .choosing, .writing:
            break
        case .specialist(let id, _, _):
            AskTrace.event("deactivate \(id)")
        }
    }
}

struct AskRoutingProfile: LanguageModelSession.DynamicProfile {
    var instructions: String
    var model: any LanguageModel
    var cloud: AskCloudSessionOptions?
    var maximumResponseTokens: Int?
    var activity: AskProfileActivity = .quiet

    var body: some LanguageModelSession.DynamicProfile {
        let activity = activity
        return LanguageModelSession.Profile {
            Instructions(instructions)
        }
        .model(model)
        .reasoningLevel(cloud?.reasoningLevel)
        .temperature(cloud?.temperature)
        .maximumResponseTokens(maximumResponseTokens)
        .toolCallingMode(.disallowed)
        .historyTransform(AskTranscript.forRouting)
        .transcriptErrorHandlingPolicy(.revertTranscript)
        .onActivate {
            await AskProfileHooks.activate(activity)
        }
        .onResponse { _ in
            await AskProfileHooks.response(activity)
        }
    }
}

struct AskSkillProfile: LanguageModelSession.DynamicProfile {
    var instructions: String
    var tools: [any Tool]
    var model: any LanguageModel
    var cloud: AskCloudSessionOptions?
    var maximumResponseTokens: Int?
    var toolCallingMode: GenerationOptions.ToolCallingMode = .allowed
    var activity: AskProfileActivity = .quiet

    /// Tool sessions keep every entry, including tool output and reasoning.
    /// historyTransform only changes what the model sees. Stripping tool output
    /// makes the next generation fail with "Transcript must end with a .prompt
    /// or .toolOutput entry." preserveTranscript leaves those outputs in place
    /// when a generation throws, so the catch can still read them.

    var body: some LanguageModelSession.DynamicProfile {
        let activity = activity
        return LanguageModelSession.Profile {
            Instructions(instructions)
            tools
        }
        .model(model)
        .reasoningLevel(cloud?.reasoningLevel)
        .temperature(cloud?.temperature)
        .maximumResponseTokens(maximumResponseTokens)
        .toolCallingMode(toolCallingMode)
        .transcriptErrorHandlingPolicy(.preserveTranscript)
        .onActivate {
            await AskProfileHooks.activate(activity)
        }
        .onToolCall { call in
            await AskProfileHooks.toolCall(activity, toolName: call.toolName)
        }
        .onToolOutput { call, _ in
            await AskProfileHooks.toolOutput(activity, toolName: call.toolName)
        }
        .onResponse { _ in
            await AskProfileHooks.response(activity)
        }
        .onDeactivate {
            AskProfileHooks.deactivate(activity)
        }
    }
}

enum AskFoundationSessions {
    /// Each route, reply, and follow-up starts empty. Earlier turns stay in the
    /// CONVERSATION prompt. Replaying them as transcript entries would carry tool
    /// calls and reasoning signatures from one specialist into the next.
    private static func routingSession(instructions: String, activity: AskProfileActivity) async -> LanguageModelSession {
        let resolved = await AskComputeRuntime.resolve()
        return LanguageModelSession(
            profile: AskRoutingProfile(
                instructions: instructions,
                model: resolved.model,
                cloud: resolved.cloud,
                maximumResponseTokens: resolved.maximumResponseTokens,
                activity: activity
            )
        )
    }

    static func routeDomain(_ request: AskModelRequest) async throws -> String {
        let session = await routingSession(instructions: request.instructions, activity: .choosing)
        let response = try await AskTrace.respond(session, label: "routeDomain", to: request.prompt, generating: AskDomainChoice.self)
        return response.content.domain
    }

    static func routeSkill(_ request: AskModelRequest) async throws -> AskModelSkillChoice {
        try await skillChoice(request, label: "routeSkill")
    }

    static func route(_ request: AskModelRequest) async throws -> AskModelSkillChoice {
        try await skillChoice(request, label: "route")
    }

    static func writeReply(_ request: AskModelRequest, tools: [any Tool]) async throws -> AskWrittenReply {
        let facts = request.facts
        let holdsUntilTool = request.requiresToolCall
        let onSnapshot: @Sendable (String) async -> Void = { text in
            await MainActor.run {
                AskReplyPreview.note(text, facts: facts, holdsUntilTool: holdsUntilTool)
            }
        }
        if tools.isEmpty {
            let writer = request.profileID == "writer"
            let session = await routingSession(instructions: request.instructions, activity: writer ? .writing : .quiet)
            let text = try await AskTrace.respondStream(
                session,
                label: writer ? "writer" : "writeReply",
                to: request.prompt,
                images: request.imageURLs,
                attributes: writer ? ["profile": "writer"] : [:],
                onSnapshot: onSnapshot
            )
            return AskWrittenReply(text: text, readings: AskToolTranscript.readings(in: session.transcript))
        }
        let resolved = await AskComputeRuntime.resolve()
        let profileID = request.profileID.isEmpty ? "reply" : request.profileID
        let session = LanguageModelSession(
            profile: AskSkillProfile(
                instructions: request.instructions,
                tools: tools,
                model: resolved.model,
                cloud: resolved.cloud,
                maximumResponseTokens: resolved.maximumResponseTokens,
                // Required mode keeps issuing tool calls and can end with an empty sentence.
                toolCallingMode: .allowed,
                activity: .specialist(
                    id: profileID,
                    title: request.profileTitle,
                    workingTitle: request.workingTitle
                )
            )
        )
        do {
            var attributes = [
                "profile": profileID,
                "tools": tools.map(\.name).joined(separator: ", ")
            ]
            let symbol = request.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !symbol.isEmpty {
                attributes["symbol"] = symbol
            }
            let text = try await AskTrace.respondStream(
                session,
                label: "specialist \(profileID)",
                to: request.prompt,
                images: request.imageURLs,
                attributes: attributes,
                onSnapshot: onSnapshot
            )
            return AskWrittenReply(text: text, readings: AskToolTranscript.readings(in: session.transcript))
        } catch {
            let readings = AskToolTranscript.readings(in: session.transcript)
            guard !readings.isEmpty else { throw error }
            return AskWrittenReply(text: "", readings: readings)
        }
    }

    static func offerFollowUp(_ request: AskModelRequest) async throws -> AskFollowUp {
        let session = await routingSession(instructions: request.instructions, activity: .quiet)
        let response = try await AskTrace.respond(
            session,
            label: "offerFollowUp",
            to: request.prompt,
            generating: AskFollowUpDraft.self
        )
        return AskFollowUp(skillID: response.content.skill, question: response.content.question)
    }

    static func composeCard(_ request: AskModelRequest) async throws -> AskCardNode {
        let session = await routingSession(instructions: request.instructions, activity: .quiet)
        let response = try await AskTrace.respond(
            session,
            label: "composeCard",
            to: request.prompt,
            generating: AskCardNode.self
        )
        return response.content
    }

    private static func skillChoice(_ request: AskModelRequest, label: String) async throws -> AskModelSkillChoice {
        let session = await routingSession(instructions: request.instructions, activity: .choosing)
        let response = try await AskTrace.respond(session, label: label, to: request.prompt, generating: AskSkillChoice.self)
        let slots = Dictionary(response.content.slots.map { ($0.key, $0.value) }, uniquingKeysWith: { _, latest in latest })
        return AskModelSkillChoice(skillID: response.content.skill, slots: slots, confidence: response.content.confidence)
    }

    static func fillSlots(_ request: AskModelRequest, tools: [any Tool]) async throws -> [String: String] {
        let resolved = await AskComputeRuntime.resolve()
        let session = LanguageModelSession(
            profile: AskSkillProfile(
                instructions: request.instructions,
                tools: tools,
                model: resolved.model,
                cloud: resolved.cloud,
                maximumResponseTokens: resolved.maximumResponseTokens
            )
        )
        let response = try await AskTrace.respond(session, label: "fillSlots", to: request.prompt, generating: AskSkillChoice.self)
        return Dictionary(response.content.slots.map { ($0.key, $0.value) }, uniquingKeysWith: { _, latest in latest })
    }
}

enum AskToolTranscript {
    static func readings(in transcript: Transcript) -> [AskAppleReading] {
        var readings: [AskAppleReading] = []
        for entry in transcript {
            guard case .toolOutput(let output) = entry else { continue }
            let text = segments(output.segments)
            let lines = text
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            readings.append(AskAppleReading(name: output.toolName, lines: lines))
        }
        return readings
    }

    private static func segments(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text):
                return text.content
            case .structure(let structure):
                return structure.content.jsonString
            case .attachment:
                return ""
            @unknown default:
                return ""
            }
        }
        .joined(separator: "\n")
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

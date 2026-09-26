import CoreSpotlight
import Foundation
import FoundationModels
import SwiftUI

public struct AskDomain: Sendable, Identifiable, Equatable {
    public var id: String
    public var summary: String
    public var routingNotes: String

    public init(id: String, summary: String, routingNotes: String) {
        self.id = id
        self.summary = summary
        self.routingNotes = routingNotes
    }
}

public struct AskReply: Sendable, Equatable {
    public var text: String
    public var spoken: String
    public var actions: [AskAction]

    public init(text: String, spoken: String, actions: [AskAction] = []) {
        self.text = text
        self.spoken = spoken
        self.actions = actions
    }
}

public struct AskAction: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// The card an existing intent already knows how to draw.
/// Ask shows this view instead of building its own reply.
public struct AskIntentCard {
    public var spoken: String
    public var view: AnyView

    public init(spoken: String, view: AnyView) {
        self.spoken = spoken
        self.view = view
    }

    public init<Content: View>(spoken: String, view: Content) {
        self.spoken = spoken
        self.view = AnyView(view)
    }
}

public enum AskFulfillment {
    /// Ask speaks this reply.
    case reply(@MainActor (AskInvocation) async -> AskReply)
    /// Ask shows the card from an existing intent's loader.
    case intent(@MainActor (AskInvocation) async -> AskIntentCard)
    /// Ask searches the app's Core Spotlight index, then the skill draws what was found.
    case search(AskSearchSkill)
}

public struct AskSkill: Identifiable {
    public var id: String
    public var domainID: String
    public var title: String
    public var summary: String
    public var requiredSlots: [String]
    /// Context keys this skill reads. Empty means the skill receives the full snapshot.
    public var contextKeys: [String]
    public var routingNotes: String
    public var fulfillment: AskFulfillment

    public init(
        id: String,
        domainID: String,
        title: String,
        summary: String,
        requiredSlots: [String] = [],
        contextKeys: [String] = [],
        routingNotes: String,
        fulfillment: AskFulfillment
    ) {
        self.id = id
        self.domainID = domainID
        self.title = title
        self.summary = summary
        self.requiredSlots = requiredSlots
        self.contextKeys = contextKeys
        self.routingNotes = routingNotes
        self.fulfillment = fulfillment
    }
}

public struct AskInvocation: Sendable, Equatable {
    public var utterance: String
    public var skillID: String
    public var domainID: String
    public var slots: [String: String]
    public var context: AskContext
    public var usedModel: Bool

    public init(
        utterance: String,
        skillID: String,
        domainID: String,
        slots: [String: String],
        context: AskContext,
        usedModel: Bool
    ) {
        self.utterance = utterance
        self.skillID = skillID
        self.domainID = domainID
        self.slots = slots
        self.context = context
        self.usedModel = usedModel
    }
}

public struct AskChip: Sendable, Identifiable, Equatable {
    public var id: String
    public var skillID: String
    public var title: String
    public var slots: [String: String]

    public init(id: String, skillID: String, title: String, slots: [String: String] = [:]) {
        self.id = id
        self.skillID = skillID
        self.title = title
        self.slots = slots
    }
}

public struct AskRoute: Sendable, Equatable {
    public var skillID: String
    public var slots: [String: String]

    public init(skillID: String, slots: [String: String] = [:]) {
        self.skillID = skillID
        self.slots = slots
    }
}

public enum AskTurnFulfillment {
    case reply(AskReply)
    case intent(AskIntentCard)
}

public struct AskTurnResult {
    public var skillID: String
    public var domainID: String
    public var slots: [String: String]
    public var usedModel: Bool
    public var fulfillment: AskTurnFulfillment

    public init(
        skillID: String,
        domainID: String,
        slots: [String: String],
        usedModel: Bool,
        fulfillment: AskTurnFulfillment
    ) {
        self.skillID = skillID
        self.domainID = domainID
        self.slots = slots
        self.usedModel = usedModel
        self.fulfillment = fulfillment
    }
}

public struct AskModelRequest: Sendable, Equatable {
    public var instructions: String
    public var prompt: String

    public init(instructions: String, prompt: String) {
        self.instructions = instructions
        self.prompt = prompt
    }
}

public struct AskModelSkillChoice: Sendable, Equatable {
    public var skillID: String
    public var slots: [String: String]
    public var confidence: Double

    public init(skillID: String, slots: [String: String] = [:], confidence: Double = 0) {
        self.skillID = skillID
        self.slots = slots
        self.confidence = confidence
    }
}

/// Routing, slot filling, and search. The default talks to the on-device model.
/// Tests pass a scripted client so they never open a session.
public struct AskModelClient: Sendable {
    public var routeDomain: @Sendable (AskModelRequest) async throws -> String
    public var routeSkill: @Sendable (AskModelRequest) async throws -> AskModelSkillChoice
    public var fillSlots: @Sendable (AskModelRequest, [any Tool]) async throws -> [String: String]
    /// One new session that carries only the search tool.
    public var search: @Sendable (AskModelRequest, SpotlightSearchTool) async throws -> AskSearchResult

    public init(
        routeDomain: @escaping @Sendable (AskModelRequest) async throws -> String,
        routeSkill: @escaping @Sendable (AskModelRequest) async throws -> AskModelSkillChoice,
        fillSlots: @escaping @Sendable (AskModelRequest, [any Tool]) async throws -> [String: String],
        search: @escaping @Sendable (AskModelRequest, SpotlightSearchTool) async throws -> AskSearchResult = AskModelClient.spotlightSearch
    ) {
        self.routeDomain = routeDomain
        self.routeSkill = routeSkill
        self.fillSlots = fillSlots
        self.search = search
    }

    public static let spotlightSearch: @Sendable (AskModelRequest, SpotlightSearchTool) async throws -> AskSearchResult = { request, tool in
        try await AskFoundationSessions.search(request, tool: tool)
    }

    public static var foundation: AskModelClient {
        AskModelClient(
            routeDomain: { request in
                try await AskFoundationSessions.routeDomain(request)
            },
            routeSkill: { request in
                try await AskFoundationSessions.routeSkill(request)
            },
            fillSlots: { request, tools in
                try await AskFoundationSessions.fillSlots(request, tools: tools)
            }
        )
    }
}

public struct AskConfiguration {
    public var assistantName: String
    public var persistence: AskPersistence
    public var domains: [AskDomain]
    public var skills: [AskSkill]
    /// Current state of the person or the app. Called at the start of each turn.
    public var context: @MainActor () async -> AskContext
    /// Optional per-skill snapshot. When nil, the turn snapshot is scoped to the skill's `contextKeys`.
    public var contextForSkill: (@MainActor (_ skillID: String, _ keys: [String]) async -> AskContext)?
    /// Deterministic. Ask never calls the model to pick chips.
    public var chips: @MainActor (AskContext) -> [AskChip]
    public var fastPath: (@MainActor (String) -> AskRoute?)?
    /// Slot keys dropped before a turn is saved. The live handler still receives them.
    public var omittedSlotKeys: Set<String>
    /// Built when a skill session is created. Router sessions never receive these.
    public var tools: (@MainActor (String) -> [any Tool])?

    public init(
        assistantName: String,
        persistence: AskPersistence = .memory,
        domains: [AskDomain],
        skills: [AskSkill],
        context: @escaping @MainActor () async -> AskContext,
        contextForSkill: (@MainActor (_ skillID: String, _ keys: [String]) async -> AskContext)? = nil,
        chips: @escaping @MainActor (AskContext) -> [AskChip],
        fastPath: (@MainActor (String) -> AskRoute?)? = nil,
        omittedSlotKeys: Set<String> = [],
        tools: (@MainActor (String) -> [any Tool])? = nil
    ) {
        self.assistantName = assistantName
        self.persistence = persistence
        self.domains = domains
        self.skills = skills
        self.context = context
        self.contextForSkill = contextForSkill
        self.chips = chips
        self.fastPath = fastPath
        self.omittedSlotKeys = omittedSlotKeys
        self.tools = tools
    }

    public init<Source: AskContextSource>(
        assistantName: String,
        persistence: AskPersistence = .memory,
        domains: [AskDomain],
        skills: [AskSkill],
        source: Source,
        chips: @escaping @MainActor (AskContext) -> [AskChip],
        fastPath: (@MainActor (String) -> AskRoute?)? = nil,
        omittedSlotKeys: Set<String> = [],
        tools: (@MainActor (String) -> [any Tool])? = nil
    ) {
        self.init(
            assistantName: assistantName,
            persistence: persistence,
            domains: domains,
            skills: skills,
            context: { await source.currentContext() },
            contextForSkill: { skillID, keys in
                await source.context(forSkill: skillID, keys: keys)
            },
            chips: chips,
            fastPath: fastPath,
            omittedSlotKeys: omittedSlotKeys,
            tools: tools
        )
    }

    func domain(id: String) -> AskDomain? {
        domains.first { $0.id.compare(id, options: .caseInsensitive) == .orderedSame }
    }

    func skill(id: String) -> AskSkill? {
        skills.first { $0.id.compare(id, options: .caseInsensitive) == .orderedSame }
    }

    func skills(in domainID: String) -> [AskSkill] {
        guard let domain = domain(id: domainID) else { return [] }
        return skills.filter { $0.domainID.compare(domain.id, options: .caseInsensitive) == .orderedSame }
    }
}

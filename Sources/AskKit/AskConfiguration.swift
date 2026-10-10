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
    /// What the reply model may rewrite. The spoken line stays when that model is off or rejects the rewrite.
    public var facts: String

    public init(text: String, spoken: String, actions: [AskAction] = [], facts: String? = nil) {
        self.text = text
        self.spoken = spoken
        self.actions = actions
        self.facts = facts ?? spoken
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
/// Ask shows this view. A bubble is added only for the sentences the card does not already show.
/// The view is not stored.
public struct AskIntentCard {
    /// Trace and accessibility name. Not the button title.
    public var title: String
    /// What a host intent speaks. This can be the full answer.
    public var spoken: String
    /// Bubble candidate. Empty when the card is the whole chat answer.
    public var text: String
    /// What the reply model may rewrite. Defaults to the spoken line.
    public var facts: String
    /// Facts the card already shows. A sentence that contains one is dropped from the bubble.
    public var coveredPhrases: [String]
    /// The card is the whole answer. The chat shows no bubble.
    public var replacesBubble: Bool
    /// Button under the card. The view itself does not own the button.
    public var action: AskAction?
    /// Plain text for the card's Copy and Share actions. The title and spoken line, unless a card replaces it.
    var shareText: String
    public var view: AnyView

    public init(
        title: String = "",
        spoken: String,
        text: String? = nil,
        coveredPhrases: [String] = [],
        replacesBubble: Bool = false,
        action: AskAction? = nil,
        facts: String? = nil,
        view: AnyView
    ) {
        self.title = title
        self.spoken = spoken
        self.text = text ?? spoken
        self.facts = facts ?? spoken
        self.coveredPhrases = coveredPhrases
        self.replacesBubble = replacesBubble
        self.action = action
        self.shareText = AskCardShareText.make(title: title, spoken: spoken)
        self.view = view
    }

    public init<Content: View>(
        title: String = "",
        spoken: String,
        text: String? = nil,
        coveredPhrases: [String] = [],
        replacesBubble: Bool = false,
        action: AskAction? = nil,
        facts: String? = nil,
        view: Content
    ) {
        self.title = title
        self.spoken = spoken
        self.text = text ?? spoken
        self.facts = facts ?? spoken
        self.coveredPhrases = coveredPhrases
        self.replacesBubble = replacesBubble
        self.action = action
        self.shareText = AskCardShareText.make(title: title, spoken: spoken)
        self.view = AnyView(view)
    }
}

/// Words placed on the pasteboard and in the share sheet for a card.
enum AskCardShareText {
    static func make(title: String, spoken: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return line }
        if line.isEmpty { return name }
        if line.range(of: name, options: .caseInsensitive) != nil { return line }
        return "\(name)\n\(line)"
    }
}

public enum AskFulfillment {
    /// Ask speaks this reply.
    case reply(@MainActor (AskInvocation) async -> AskReply)
    /// Ask shows the card from an existing intent's loader.
    case intent(@MainActor (AskInvocation) async -> AskIntentCard)
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
    /// A question the chat can offer under this answer. Nil when the turn has more than one page.
    public var followUp: AskFollowUp?
    /// Every answer in this turn. The chat pages these when there is more than one.
    /// `fulfillment` stays the first page so a host that reads one answer still can.
    public var pages: [AskPage]
    /// The stored assistant turn. The shortcut snippet reloads this turn's cards.
    public var id: UUID

    public init(
        skillID: String,
        domainID: String,
        slots: [String: String],
        usedModel: Bool,
        fulfillment: AskTurnFulfillment,
        followUp: AskFollowUp? = nil,
        pages: [AskPage] = [],
        id: UUID = UUID()
    ) {
        self.skillID = skillID
        self.domainID = domainID
        self.slots = slots
        self.usedModel = usedModel
        self.fulfillment = fulfillment
        self.followUp = followUp
        self.pages = pages
        self.id = id
    }
}

public struct AskModelRequest: Sendable, Equatable {
    public var instructions: String
    public var prompt: String
    /// Skill facts for a reply rewrite. Empty for every other request.
    public var facts: String
    /// True when this question needs a tool result. The session stays allowed to answer without calling one, because required mode can call tools until the sentence is empty. A rewrite that needed a tool and did not call one is dropped. Misses stay optional.
    public var requiresToolCall: Bool
    /// Image files copied for this reply. Foundation Models attachments are images.
    public var imageURLs: [URL]
    /// `writer` for a tool-free reply. A specialist id when that profile runs.
    public var profileID: String
    /// Specialist name shown beside the thinking orb. Empty for the writer.
    public var profileTitle: String
    /// Status line while the specialist is active, before its tool runs.
    public var workingTitle: String

    public init(
        instructions: String,
        prompt: String,
        facts: String = "",
        requiresToolCall: Bool = false,
        imageURLs: [URL] = [],
        profileID: String = "",
        profileTitle: String = "",
        workingTitle: String = ""
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.facts = facts
        self.requiresToolCall = requiresToolCall
        self.imageURLs = imageURLs
        self.profileID = profileID
        self.profileTitle = profileTitle
        self.workingTitle = workingTitle
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

/// Routing and slot filling. The default talks to the on-device model.
/// Tests pass a scripted client so they never open a session.
public struct AskModelClient: Sendable {
    public var routeDomain: @Sendable (AskModelRequest) async throws -> String
    public var routeSkill: @Sendable (AskModelRequest) async throws -> AskModelSkillChoice
    public var fillSlots: @Sendable (AskModelRequest, [any Tool]) async throws -> [String: String]
    /// One catalog route. Used when the app supplies an `AskGuide` opening or rules.
    public var route: @Sendable (AskModelRequest) async throws -> AskModelSkillChoice
    /// Rewrites FACTS into the spoken answer. Router sessions and chip taps use this.
    public var writeReply: @Sendable (AskModelRequest) async throws -> String
    /// Offers one next question.
    public var offerFollowUp: @Sendable (AskModelRequest) async throws -> AskFollowUp
    /// Reply rewrite when Apple sources or skill tools are attached. The default ignores the tools.
    public var writeReplyUsing: @Sendable (AskModelRequest, [any Tool]) async throws -> AskWrittenReply

    public init(
        routeDomain: @escaping @Sendable (AskModelRequest) async throws -> String,
        routeSkill: @escaping @Sendable (AskModelRequest) async throws -> AskModelSkillChoice,
        fillSlots: @escaping @Sendable (AskModelRequest, [any Tool]) async throws -> [String: String],
        route: @escaping @Sendable (AskModelRequest) async throws -> AskModelSkillChoice = { _ in
            AskModelSkillChoice(skillID: "")
        },
        writeReply: @escaping @Sendable (AskModelRequest) async throws -> String = { _ in "" },
        offerFollowUp: @escaping @Sendable (AskModelRequest) async throws -> AskFollowUp = { _ in
            AskFollowUp(skillID: "none", question: "")
        },
        writeReplyUsing: (@Sendable (AskModelRequest, [any Tool]) async throws -> AskWrittenReply)? = nil
    ) {
        self.routeDomain = routeDomain
        self.routeSkill = routeSkill
        self.fillSlots = fillSlots
        self.route = route
        self.writeReply = writeReply
        self.offerFollowUp = offerFollowUp
        if let writeReplyUsing {
            self.writeReplyUsing = writeReplyUsing
        } else {
            self.writeReplyUsing = { request, _ in
                AskWrittenReply(text: try await writeReply(request))
            }
        }
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
            },
            route: { request in
                try await AskFoundationSessions.route(request)
            },
            writeReply: { request in
                try await AskFoundationSessions.writeReply(request, tools: []).text
            },
            offerFollowUp: { request in
                try await AskFoundationSessions.offerFollowUp(request)
            },
            writeReplyUsing: { request, tools in
                try await AskFoundationSessions.writeReply(request, tools: tools)
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
    /// Opening, rules, reply instructions, and follow-up instructions. Nil keeps the two routing hops.
    public var guide: AskGuide?
    /// Slot keys dropped before a turn is saved. The live handler still receives them.
    public var omittedSlotKeys: Set<String>
    /// Built for slot fill. On a reply they are their own specialist, in their own session.
    public var tools: (@MainActor (String) -> [any Tool])?
    /// App specialists. A match runs before any Apple specialist, in its own session.
    public var specialists: [AskSpecialist]
    /// Reads the title and summary of an https address in the question. Off until the app sets it.
    public var webMetadata: Bool
    /// Apple sources a reply may use. Empty until the app sets it. Calendar, reminders, and alarms can add.
    public var appleAccess: AskAppleAccess
    /// Replaces the fact card for a reply that used an Apple source.
    /// Return nil to keep the built-in card. The lines are what the tool returned.
    public var appleCard: (@MainActor (_ name: String, _ lines: [String]) -> AskIntentCard?)?

    public init(
        assistantName: String,
        persistence: AskPersistence = .memory,
        domains: [AskDomain],
        skills: [AskSkill],
        context: @escaping @MainActor () async -> AskContext,
        contextForSkill: (@MainActor (_ skillID: String, _ keys: [String]) async -> AskContext)? = nil,
        chips: @escaping @MainActor (AskContext) -> [AskChip],
        fastPath: (@MainActor (String) -> AskRoute?)? = nil,
        guide: AskGuide? = nil,
        omittedSlotKeys: Set<String> = [],
        tools: (@MainActor (String) -> [any Tool])? = nil,
        specialists: [AskSpecialist] = [],
        webMetadata: Bool = false,
        appleAccess: AskAppleAccess = [],
        appleCard: (@MainActor (_ name: String, _ lines: [String]) -> AskIntentCard?)? = nil
    ) {
        self.assistantName = assistantName
        self.persistence = persistence
        self.domains = domains
        self.skills = skills
        self.context = context
        self.contextForSkill = contextForSkill
        self.chips = chips
        self.fastPath = fastPath
        self.guide = guide
        self.omittedSlotKeys = omittedSlotKeys
        self.tools = tools
        self.specialists = specialists
        self.webMetadata = webMetadata
        self.appleAccess = appleAccess
        self.appleCard = appleCard
    }

    public init<Source: AskContextSource>(
        assistantName: String,
        persistence: AskPersistence = .memory,
        domains: [AskDomain],
        skills: [AskSkill],
        source: Source,
        chips: @escaping @MainActor (AskContext) -> [AskChip],
        fastPath: (@MainActor (String) -> AskRoute?)? = nil,
        guide: AskGuide? = nil,
        omittedSlotKeys: Set<String> = [],
        tools: (@MainActor (String) -> [any Tool])? = nil,
        specialists: [AskSpecialist] = [],
        webMetadata: Bool = false,
        appleAccess: AskAppleAccess = [],
        appleCard: (@MainActor (_ name: String, _ lines: [String]) -> AskIntentCard?)? = nil
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
            guide: guide,
            omittedSlotKeys: omittedSlotKeys,
            tools: tools,
            specialists: specialists,
            webMetadata: webMetadata,
            appleAccess: appleAccess,
            appleCard: appleCard
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

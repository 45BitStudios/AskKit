import Foundation
import FoundationModels
import SwiftData

enum AskQuestionJoin {
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

private enum AskBoundary {
    case none
    case catalog
    case outside
    case blocked
}

private struct RoutedTurn {
    var skillID: String?
    var slots: [String: String]
    var usedModel: Bool
    var boundary: AskBoundary = .none
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

    public func handle(
        utterance: String,
        entry: AskTraceEntry = .composer,
        priorUserQuestions: [String] = [],
        images: [URL] = []
    ) async -> AskTurnResult {
        await AskTrace.turn(utterance, entry: entry) {
            if !images.isEmpty {
                AskTrace.attribute("images", "\(images.count)")
            }
            let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = await AskTrace.span("context") {
                await configuration.context()
            }
            let stored = (try? store.recentUserTexts(assistantName: configuration.assistantName)) ?? []
            let priors = priorUserQuestions.isEmpty ? stored : priorUserQuestions
            let pieces = AskPages.pieces(trimmed)
            if pieces.count > 1 {
                try? store.appendUser(assistantName: configuration.assistantName, text: trimmed)
                var routedPieces: [(String, RoutedTurn)] = []
                for piece in pieces {
                    let routed = await route(utterance: piece, context: context, earlier: priors)
                    routedPieces.append((piece, routed))
                }
                let resolved = Set(routedPieces.compactMap { resolvedID($0.1) })
                if resolved.count > 1 || answersEachPhotoQuestion(pieces, images: images) {
                    return await fulfillMany(routedPieces, fullUtterance: trimmed, context: context, images: images)
                }
                let chosen = routedPieces.first { resolvedID($0.1) != nil }?.1 ?? routedPieces[0].1
                return await fulfill(chosen, utterance: trimmed, context: context, allowsTools: true, images: images)
            }
            let routedUtterance = AskTrace.span("followUp") {
                let resolved = AskQuestionJoin.resolve(trimmed, priorUserQuestions: priors)
                if resolved != trimmed {
                    AskTrace.decision("joined to the previous question")
                    AskTrace.attribute("promptQuestion", resolved)
                }
                return resolved
            }
            try? store.appendUser(assistantName: configuration.assistantName, text: trimmed)
            let routed = await route(utterance: routedUtterance, context: context, earlier: priors)
            return await fulfill(routed, utterance: routedUtterance, context: context, allowsTools: true, images: images)
        }
    }

    /// A chip already chose the skill. This does not open a routing session, and the reply does not receive tools.
    public func handle(chip: AskChip) async -> AskTurnResult {
        await AskTrace.turn(chip.title, entry: .chip) {
            AskTrace.attribute("routedVia", "chip")
            let context = await AskTrace.span("context") {
                await configuration.context()
            }
            try? store.appendUser(assistantName: configuration.assistantName, text: chip.title)
            let routed = RoutedTurn(skillID: chip.skillID, slots: chip.slots, usedModel: false)
            return await fulfill(routed, utterance: chip.title, context: context, allowsTools: false)
        }
    }

    public func transcript() throws -> [AskTranscriptTurn] {
        try store.transcript(assistantName: configuration.assistantName)
    }

    public func clearThread() throws {
        try store.clear(assistantName: configuration.assistantName)
    }

    /// Rebuilds every page for a stored assistant turn. Card views are not stored.
    /// A turn saved before paging returns one page from its text and, when it was a card, that card.
    public func pages(for turnID: UUID) async -> [AskPage] {
        guard let turn = try? store.assistantTurn(id: turnID, assistantName: configuration.assistantName) else {
            return []
        }
        let stored = AskStoredPages.decode(turn.pagesJSON)
        if stored.isEmpty {
            let card = await intentCard(for: turnID)
            return [
                AskPage(
                    id: turn.id,
                    text: turn.text,
                    spoken: turn.spoken,
                    skillID: turn.skillID,
                    domainID: turn.domainID,
                    slots: AskSlots.decode(turn.slotsJSON),
                    card: card
                )
            ]
        }
        var pages: [AskPage] = []
        for item in stored {
            let card = await restoredCard(item)
            let actions = card == nil
                ? item.actions.map { AskAction(id: $0.id, title: $0.title) }
                : []
            let reading = item.appleName.isEmpty
                ? nil
                : AskAppleReading(name: item.appleName, lines: item.appleLines)
            pages.append(
                AskPage(
                    id: item.id,
                    question: item.question,
                    text: item.text,
                    spoken: item.spoken,
                    skillID: item.skillID,
                    domainID: item.domainID,
                    slots: AskSlots.decode(item.slotsJSON),
                    card: card,
                    actions: actions,
                    appleReading: reading
                )
            )
        }
        return pages
    }

    /// Draws an intent card again from the stored turn. The view is not stored.
    public func intentCard(for turnID: UUID) async -> AskIntentCard? {
        guard let turns = try? transcript(),
              let index = turns.firstIndex(where: { $0.id == turnID }) else {
            return nil
        }
        let turn = turns[index]
        guard turn.role == "assistant" else { return nil }
        if turn.skillID == AskCapabilities.skillID {
            return AskCapabilities.card(
                spoken: turn.spoken.isEmpty ? turn.text : turn.spoken,
                domains: configuration.domains,
                skills: configuration.skills
            )
        }
        guard let skill = configuration.skill(id: turn.skillID),
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

    private func route(utterance: String, context: AskContext, earlier: [String]) async -> RoutedTurn {
        if AskCapabilities.isQuestion(utterance) {
            AskTrace.attribute("routedVia", "capabilities")
            AskTrace.decision("capabilities")
            return RoutedTurn(skillID: AskCapabilities.skillID, slots: [:], usedModel: false, boundary: .catalog)
        }
        if let fast = fastRoute(utterance) {
            AskTrace.attribute("routedVia", "fastPath")
            AskTrace.decision("fast path")
            return await filling(fast, utterance: utterance, context: context, usedModel: false)
        }
        if let guide = configuration.guide, guide.routesWithCatalog {
            return await catalogRoute(guide, utterance: utterance, context: context, earlier: earlier)
        }
        do {
            let domainRequest = AskModelRequest(
                instructions: AskPrompts.domainInstructions(
                    assistantName: configuration.assistantName,
                    domains: configuration.domains
                ),
                prompt: AskPrompts.userPrompt(context: context.promptBlock, utterance: utterance)
            )
            let domainID = try await AskTrace.span("routeDomain") {
                let id = try await model.routeDomain(domainRequest)
                AskTrace.attribute("domain", id)
                AskTrace.result(id)
                return id
            }
            guard let domain = configuration.domain(id: domainID) else {
                AskTrace.decision("domain miss")
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
            let choice = try await AskTrace.span("routeSkill") {
                let choice = try await model.routeSkill(skillRequest)
                AskTrace.attribute("skill", choice.skillID)
                AskTrace.result(choice.skillID)
                return choice
            }
            guard let skill = skills.first(where: { $0.id.compare(choice.skillID, options: .caseInsensitive) == .orderedSame }) else {
                AskTrace.decision("skill miss")
                return fallback(utterance)
            }
            AskTrace.attribute("routedVia", "model")
            let routed = RoutedTurn(skillID: skill.id, slots: choice.slots, usedModel: true)
            return await filling(routed, utterance: utterance, context: context, usedModel: true)
        } catch {
            return blockedOrFallback(error, utterance: utterance)
        }
    }

    private func catalogRoute(
        _ guide: AskGuide,
        utterance: String,
        context: AskContext,
        earlier: [String]
    ) async -> RoutedTurn {
        let request = AskModelRequest(
            instructions: guide.routeInstructions(domains: configuration.domains, skills: configuration.skills),
            prompt: guide.routePrompt(context: context.promptBlock, earlier: earlier, request: utterance)
        )
        do {
            let choice = try await AskTrace.span("route") {
                let choice = try await model.route(request)
                AskTrace.attribute("skill", choice.skillID)
                AskTrace.result(choice.skillID)
                return choice
            }
            guard let skill = configuration.skill(id: choice.skillID) else {
                AskTrace.decision("skill miss")
                return fallback(utterance)
            }
            AskTrace.attribute("domain", skill.domainID)
            AskTrace.attribute("routedVia", "model")
            let routed = RoutedTurn(skillID: skill.id, slots: choice.slots, usedModel: true)
            return await filling(routed, utterance: utterance, context: context, usedModel: true)
        } catch {
            return blockedOrFallback(error, utterance: utterance)
        }
    }

    private func blockedOrFallback(_ error: Error, utterance: String) -> RoutedTurn {
        if AskModelSafety.isBlocked(error) {
            AskTrace.attribute("routedVia", "guardrail")
            AskTrace.decision("guardrail")
            return RoutedTurn(skillID: AskCapabilities.skillID, slots: [:], usedModel: false, boundary: .blocked)
        }
        if let notice = AskModelSafety.notice(error) {
            AskTrace.attribute("modelFailure", notice.decision)
            AskTrace.decision(notice.decision)
        } else {
            AskTrace.decision("route failed")
        }
        return fallback(utterance)
    }

    private func fastRoute(_ utterance: String) -> RoutedTurn? {
        guard let route = configuration.fastPath?(utterance), configuration.skill(id: route.skillID) != nil else {
            return nil
        }
        return RoutedTurn(skillID: route.skillID, slots: route.slots, usedModel: false)
    }

    private func fallback(_ utterance: String) -> RoutedTurn {
        if let fast = fastRoute(utterance) {
            AskTrace.attribute("routedVia", "fastPath")
            AskTrace.decision("fast path")
            return fast
        }
        AskTrace.attribute("routedVia", "fallback")
        AskTrace.decision("fallback")
        if configuration.skill(id: "unknown") != nil {
            return RoutedTurn(skillID: "unknown", slots: [:], usedModel: false)
        }
        return RoutedTurn(skillID: nil, slots: [:], usedModel: false)
    }

    private func filling(_ routed: RoutedTurn, utterance: String, context: AskContext, usedModel: Bool) async -> RoutedTurn {
        guard let skillID = routed.skillID, let skill = configuration.skill(id: skillID) else {
            return routed
        }
        guard !skill.requiredSlots.isEmpty else {
            return RoutedTurn(skillID: skill.id, slots: routed.slots, usedModel: usedModel)
        }
        guard !AskSlots.hasValues(routed.slots, for: skill.requiredSlots) else {
            AskTrace.decision("slots already filled")
            return RoutedTurn(skillID: skill.id, slots: routed.slots, usedModel: usedModel)
        }
        let tools = configuration.tools?(skill.domainID) ?? []
        guard AskSessionPolicy.acceptedSkillToolCount(tools.count) != nil else {
            AskTrace.decision("tool count outside 1...5")
            return RoutedTurn(skillID: skill.id, slots: routed.slots, usedModel: usedModel)
        }
        let request = AskModelRequest(
            instructions: AskPrompts.fillInstructions(skill: skill),
            prompt: AskPrompts.userPrompt(context: context.promptBlock, utterance: utterance, slots: routed.slots)
        )
        return await AskTrace.span("fillSlots") {
            do {
                let filled = try await model.fillSlots(request, tools)
                return RoutedTurn(
                    skillID: skill.id,
                    slots: AskSlots.merging(filled, into: routed.slots),
                    usedModel: true
                )
            } catch {
                AskTrace.decision(AskModelSafety.failure(error) ?? "slot fill failed")
                return RoutedTurn(skillID: skill.id, slots: routed.slots, usedModel: usedModel)
            }
        }
    }

    private func contextForSkill(_ skill: AskSkill, fallback: AskContext) async -> AskContext {
        if let contextForSkill = configuration.contextForSkill {
            return await contextForSkill(skill.id, skill.contextKeys)
        }
        return skill.contextKeys.isEmpty ? fallback : fallback.scoped(to: skill.contextKeys)
    }

    private func resolvedID(_ routed: RoutedTurn) -> String? {
        switch routed.boundary {
        case .catalog, .blocked, .outside:
            return AskCapabilities.skillID
        case .none:
            break
        }
        guard let id = routed.skillID, configuration.skill(id: id) != nil else { return nil }
        return configuration.skill(id: id)?.id ?? id
    }

    private struct BuiltPage {
        var page: AskPage
        var usedModel: Bool
        var fulfillment: AskTurnFulfillment
        /// Later cards from the same answer. Their text stays empty so the bubble is not repeated.
        var more: [AskPage] = []
    }

    private func fulfill(
        _ routed: RoutedTurn,
        utterance: String,
        context: AskContext,
        allowsTools: Bool,
        images: [URL] = []
    ) async -> AskTurnResult {
        await AskTrace.span("fulfill") {
            let built = await buildPage(
                routed,
                utterance: utterance,
                excluding: utterance,
                context: context,
                allowsTools: allowsTools,
                images: images
            )
            return await commit([built], followUpQuestion: utterance, context: context)
        }
    }

    private func fulfillMany(
        _ parts: [(String, RoutedTurn)],
        fullUtterance: String,
        context: AskContext,
        images: [URL] = []
    ) async -> AskTurnResult {
        await AskTrace.span("fulfill") {
            var built: [BuiltPage] = []
            for (piece, routed) in parts {
                built.append(await buildPage(
                    routed,
                    utterance: piece,
                    excluding: fullUtterance,
                    context: context,
                    allowsTools: true,
                    images: images
                ))
            }
            return await commit(built, followUpQuestion: nil, context: context)
        }
    }

    private func buildPage(
        _ routed: RoutedTurn,
        utterance: String,
        excluding: String,
        context: AskContext,
        allowsTools: Bool,
        images: [URL] = []
    ) async -> BuiltPage {
        if routed.boundary != .none {
            return capabilityPage(routed.boundary, question: utterance, context: context)
        }
        let skill = routed.skillID.flatMap { configuration.skill(id: $0) } ?? configuration.skill(id: "unknown")
        guard let skill else {
            if allowsTools, let built = await appleMissPage(
                utterance: utterance,
                excluding: excluding,
                context: context,
                images: images
            ) {
                return built
            }
            return capabilityPage(.outside, question: utterance, context: context)
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
            var reply = await make(invocation)
            var usedModel = routed.usedModel
            let draft = await rewrite(
                reply.facts,
                question: utterance,
                excluding: excluding,
                skill: skill,
                context: context,
                allowsTools: allowsTools,
                images: images
            )
            if let written = draft.text {
                reply.text = written
                reply.spoken = AskGuide.plainSpeech(written)
                usedModel = true
            }
            let pages = laidOutPages(
                question: utterance,
                text: reply.text,
                spoken: reply.spoken,
                skillID: skill.id,
                domainID: skill.domainID,
                slots: routed.slots,
                actions: reply.actions,
                readings: draft.readings
            )
            return BuiltPage(
                page: pages[0],
                usedModel: usedModel,
                fulfillment: .reply(reply),
                more: Array(pages.dropFirst())
            )
        case .intent(let make):
            var card = await make(invocation)
            var usedModel = routed.usedModel
            let draft = await rewrite(
                card.facts,
                question: utterance,
                excluding: excluding,
                skill: skill,
                context: context,
                allowsTools: allowsTools,
                images: images
            )
            if let written = draft.text {
                card.text = written
                card.spoken = AskGuide.plainSpeech(written)
                usedModel = true
            }
            let pages = laidOutPages(
                question: utterance,
                text: card.text,
                spoken: card.spoken,
                skillID: skill.id,
                domainID: skill.domainID,
                slots: routed.slots,
                actions: [],
                readings: draft.readings,
                skillCard: card
            )
            return BuiltPage(
                page: pages[0],
                usedModel: usedModel,
                fulfillment: .intent(pages[0].card ?? card),
                more: Array(pages.dropFirst())
            )
        }
    }

    /// The speech stays on the first page. Each Apple source after that is another card, with no second bubble.
    private func laidOutPages(
        question: String,
        text: String,
        spoken: String,
        skillID: String,
        domainID: String,
        slots: [String: String],
        actions: [AskAction],
        readings: [AskAppleReading],
        skillCard: AskIntentCard? = nil
    ) -> [AskPage] {
        let sources = AskAppleCards.sources(readings)
        let showsCoordinates = AskLocationPin.asks(question)
        func fact(_ reading: AskAppleReading) -> AskIntentCard {
            AskAppleCards.make(
                reading,
                spoken: spoken,
                showsCoordinates: showsCoordinates,
                playedBy: configuration.assistantName,
                custom: configuration.appleCard
            )
        }
        if let skillCard {
            let head = sources.first
            let primary = AskAppleCards.under(
                skillCard,
                reading: head,
                showsCoordinates: showsCoordinates,
                playedBy: configuration.assistantName,
                custom: configuration.appleCard
            )
            let bubble = AskCardTranscript.bubble(primary.text, card: primary) ?? ""
            var pages = [
                AskPage(
                    question: question,
                    text: bubble,
                    spoken: primary.spoken,
                    skillID: skillID,
                    domainID: domainID,
                    slots: slots,
                    card: primary,
                    appleReading: head
                )
            ]
            for reading in sources.dropFirst() {
                pages.append(
                    AskPage(
                        question: question,
                        text: "",
                        spoken: "",
                        skillID: skillID,
                        domainID: domainID,
                        slots: slots,
                        card: fact(reading),
                        appleReading: reading
                    )
                )
            }
            return pages
        }
        guard !sources.isEmpty else {
            return [
                AskPage(
                    question: question,
                    text: text,
                    spoken: spoken,
                    skillID: skillID,
                    domainID: domainID,
                    slots: slots,
                    actions: actions
                )
            ]
        }
        return sources.enumerated().map { index, reading in
            let leading = index == 0
            return AskPage(
                question: question,
                text: leading ? text : "",
                spoken: leading ? spoken : "",
                skillID: skillID,
                domainID: domainID,
                slots: slots,
                card: fact(reading),
                appleReading: reading
            )
        }
    }

    /// The question stays in the thread. No assistant row is saved.
    private func cancelledTurn() -> AskTurnResult {
        AskTrace.decision("cancelled")
        return AskTurnResult(
            skillID: "",
            domainID: "",
            slots: [:],
            usedModel: false,
            fulfillment: .reply(AskReply(text: "", spoken: "")),
            pages: []
        )
    }

    private func commit(
        _ built: [BuiltPage],
        followUpQuestion: String?,
        context: AskContext
    ) async -> AskTurnResult {
        if Task.isCancelled {
            return cancelledTurn()
        }
        let rows = built.isEmpty ? [capabilityPage(.outside, question: "", context: context)] : built
        let first = rows[0]
        let pages = rows.flatMap { [$0.page] + $0.more }
        var usedModel = rows.contains { $0.usedModel }
        AskTrace.attribute("skill", first.page.skillID)
        if !first.page.domainID.isEmpty {
            AskTrace.attribute("domain", first.page.domainID)
        }
        recordSlots(first.page.slots)
        if pages.count > 1 {
            AskTrace.attribute("pageCount", "\(pages.count)")
            AskTrace.decision("\(pages.count) pages")
        }
        let shownText = pages.compactMap { page -> String? in
            if !page.text.isEmpty { return page.text }
            if page.card == nil, !page.spoken.isEmpty { return page.spoken }
            return nil
        }.joined(separator: "\n\n")
        let shownCards = pages.compactMap { $0.card?.title }.filter { !$0.isEmpty }.joined(separator: ", ")
        AskTrace.shown(shownText, cards: shownCards)
        #if DEBUG
        let cardBodies = pages.compactMap(\.card).filter { !$0.title.isEmpty }.map(\.shareText)
        if let encoded = AskTracePoster.encodeBodies(cardBodies) {
            AskTrace.attribute("shownCardBodies", encoded)
        }
        #endif
        let storedText = pages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        let spoken = pages.map(\.spoken).filter { !$0.isEmpty }.joined(separator: "\n\n")
        AskChatActivity.clearStream()
        if Task.isCancelled {
            return cancelledTurn()
        }
        let savedID = try? store.appendAssistant(
            assistantName: configuration.assistantName,
            text: storedText,
            spoken: spoken,
            skillID: first.page.skillID,
            domainID: first.page.domainID,
            slots: first.page.slots,
            omitting: configuration.omittedSlotKeys,
            pagesJSON: AskStoredPages.encode(pages, omitting: configuration.omittedSlotKeys)
        )
        var followUp: AskFollowUp?
        if pages.count == 1, let followUpQuestion, let skill = configuration.skill(id: first.page.skillID) {
            followUp = await offerFollowUp(after: skill, question: followUpQuestion, context: context)
            if followUp != nil { usedModel = true }
        }
        return AskTurnResult(
            skillID: first.page.skillID,
            domainID: first.page.domainID,
            slots: first.page.slots,
            usedModel: usedModel,
            fulfillment: first.fulfillment,
            followUp: followUp,
            pages: pages,
            id: savedID ?? UUID()
        )
    }

    private struct ReplyWrite {
        var text: String?
        var readings: [AskAppleReading]

        static let none = ReplyWrite(text: nil, readings: [])
    }

    private enum SpecialistWrite {
        case skipped
        case produced(ReplyWrite)
    }

    private struct ReplyProfile {
        var id: String
        var title: String
        var workingTitle: String
        var toolNote: String

        static let writer = ReplyProfile(id: "writer", title: "", workingTitle: "", toolNote: "")
    }

    /// The catalog missed and an `unknown` skill is not registered.
    /// A question that names a source runs that specialist. No match keeps the capabilities card.
    private func appleMissPage(
        utterance: String,
        excluding: String,
        context: AskContext,
        images: [URL] = []
    ) async -> BuiltPage? {
        guard let guide = configuration.guide, guide.writesReply else { return nil }
        let produced: ReplyWrite
        switch await specialistWrite(
            facts: AskAppleCopy.missFacts,
            question: utterance,
            excluding: excluding,
            skillID: AskAppleCopy.missSkillID,
            domainID: "",
            domainTitle: "",
            context: context,
            allowsTools: true,
            images: images,
            guide: guide
        ) {
        case .skipped:
            return nil
        case .produced(let draft):
            produced = draft
        }
        let sources = AskAppleCards.sources(produced.readings)
        guard let reading = sources.first else { return nil }
        let spoken = produced.text ?? AskLocationPin.labels(in: reading.lines).joined(separator: "\n")
        guard !spoken.isEmpty else { return nil }
        AskTrace.decision("apple tools")
        let reply = AskReply(text: spoken, spoken: spoken, facts: AskAppleCopy.missFacts)
        let pages = laidOutPages(
            question: utterance,
            text: spoken,
            spoken: spoken,
            skillID: AskAppleCopy.missSkillID,
            domainID: "",
            slots: [:],
            actions: [],
            readings: produced.readings
        )
        return BuiltPage(page: pages[0], usedModel: true, fulfillment: .reply(reply), more: Array(pages.dropFirst()))
    }

    private func rewrite(
        _ facts: String,
        question: String,
        excluding: String,
        skill: AskSkill,
        context: AskContext,
        allowsTools: Bool,
        images: [URL] = []
    ) async -> ReplyWrite {
        guard let guide = configuration.guide, guide.writesReply else { return .none }
        if let placed = await photoPlace(question: question, images: images) {
            AskTrace.decision("photo place")
            if let text = placed.text { AskTrace.result(text) }
            return placed
        }
        if let detail = photoDetail(question: question, images: images) {
            AskTrace.decision("photo file")
            if let text = detail.text { AskTrace.result(text) }
            return detail
        }
        let domain = configuration.domain(id: skill.domainID)
        switch await specialistWrite(
            facts: facts,
            question: question,
            excluding: excluding,
            skillID: skill.id,
            domainID: skill.domainID,
            domainTitle: domain?.summary ?? skill.domainID,
            context: context,
            allowsTools: allowsTools,
            images: images,
            guide: guide
        ) {
        case .skipped:
            return .none
        case .produced(let draft):
            return draft
        }
    }

    /// One session per matching specialist. The writer runs when none match.
    private func specialistWrite(
        facts: String,
        question: String,
        excluding: String,
        skillID: String,
        domainID: String,
        domainTitle: String,
        context: AskContext,
        allowsTools: Bool,
        images: [URL],
        guide: AskGuide
    ) async -> SpecialistWrite {
        let needsTool = AskAppleCopy.questionNeedsATool(question)
        let domainTools: [any Tool]
        if allowsTools, needsTool, !domainID.isEmpty {
            domainTools = configuration.tools?(domainID) ?? []
        } else {
            domainTools = []
        }
        var hosts: [AskSpecialistChoice] = []
        if allowsTools {
            if configuration.webMetadata, AskWebMetadata.url(in: question) != nil {
                hosts.append(AskSpecialistChoice(
                    id: AskWebMetadata.specialistID,
                    title: "Web",
                    workingTitle: "Reading the page",
                    origin: .host
                ))
            }
            hosts += configuration.specialists.filter { $0.matches(question) }.map { specialist in
                AskSpecialistChoice(
                    id: specialist.id,
                    title: specialist.title,
                    workingTitle: specialist.workingTitle,
                    origin: .host
                )
            }
        }
        let apple = AskAppleSelection.active(
            allowed: configuration.appleAccess,
            for: configuration.assistantName
        )
        let decision = AskTurnSpecialists.decide(
            question: question,
            skillID: skillID,
            facts: facts,
            allowsTools: allowsTools,
            hosts: hosts,
            domainToolCount: domainTools.count,
            domainID: domainID,
            domainTitle: domainTitle,
            apple: apple
        )
        if decision.capped {
            AskTrace.decision("specialist cap")
        }
        if decision.refusedToolCount {
            AskTrace.decision("tool count outside 1...5")
        }
        if decision.leavesMiss {
            return .skipped
        }
        if decision.usesWriter || decision.choices.isEmpty {
            guard decision.usesWriter else { return .skipped }
            if allowsTools, let closed = AskTurnSpecialists.closedSentence(question: question, access: apple) {
                AskTrace.decision("source off")
                return .produced(ReplyWrite(text: closed, readings: []))
            }
            let hadCandidates = !hosts.isEmpty || !domainTools.isEmpty || !apple.isEmpty
            if allowsTools, hadCandidates {
                AskTrace.decision("no tool needed")
            }
            let written = await writeAnswer(
                facts,
                question: question,
                excluding: excluding,
                skillID: skillID,
                context: context,
                tools: [],
                guide: guide,
                images: images,
                profile: .writer
            )
            return .produced(written)
        }
        var texts: [String] = []
        var readings: [AskAppleReading] = []
        var ran: [String] = []
        for choice in decision.choices {
            let asked = choice.origin == .apple
                ? AskSpecialistClause.question(for: choice.id, in: question)
                : question
            let tools = tools(for: choice, domainTools: domainTools, question: asked)
            guard AskSessionPolicy.acceptedSkillToolCount(tools.count) != nil else {
                AskTrace.decision("tool count outside 1...5")
                continue
            }
            if !ran.isEmpty {
                AskChatActivity.clearStream()
            }
            let written = await writeAnswer(
                facts,
                question: question,
                excluding: excluding,
                skillID: skillID,
                context: context,
                tools: tools,
                guide: guide,
                images: images,
                profile: ReplyProfile(
                    id: choice.id,
                    title: choice.title,
                    workingTitle: choice.workingTitle,
                    toolNote: toolNote(for: choice)
                ),
                promptQuestion: asked
            )
            ran.append(choice.id)
            if let text = written.text {
                texts.append(text)
            }
            readings = mergedSpecialistReadings(readings, written.readings)
        }
        guard !ran.isEmpty else { return .skipped }
        AskTrace.attribute("specialists", ran.joined(separator: ", "))
        return .produced(ReplyWrite(text: joinedReply(texts), readings: readings))
    }

    private func tools(for choice: AskSpecialistChoice, domainTools: [any Tool], question: String) -> [any Tool] {
        switch choice.origin {
        case .host:
            if choice.id == AskWebMetadata.specialistID {
                return [AskWebMetadataTool(toolLedger: AskToolLedger())]
            }
            return configuration.specialists.first { $0.id == choice.id }?.tools().map { tool in
                AskPhotosTool.stamped(tool, question: question)
            } ?? []
        case .domain:
            return domainTools
        case .apple:
            guard let source = AskAppleSource.catalog.first(where: { $0.name == choice.id }) else { return [] }
            return AskAppleTools.make(source.access, question: question)
        }
    }

    private func toolNote(for choice: AskSpecialistChoice) -> String {
        switch choice.origin {
        case .host:
            if choice.id == AskWebMetadata.specialistID {
                return AskWebMetadata.note
            }
            return configuration.specialists.first { $0.id == choice.id }?.instructions ?? ""
        case .domain:
            return AskAppleSpecialistNotes.domain
        case .apple:
            return AskAppleSpecialistNotes.note(for: choice.id)
        }
    }

    private func joinedReply(_ texts: [String]) -> String? {
        var unique: [String] = []
        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !unique.contains(trimmed) else { continue }
            unique.append(trimmed)
        }
        return unique.isEmpty ? nil : unique.joined(separator: " ")
    }

    private func mergedSpecialistReadings(_ current: [AskAppleReading], _ next: [AskAppleReading]) -> [AskAppleReading] {
        var merged = current
        for reading in next {
            if let index = merged.firstIndex(where: { $0.name == reading.name }) {
                for line in reading.lines where !merged[index].lines.contains(line) {
                    merged[index].lines.append(line)
                }
            } else {
                merged.append(reading)
            }
        }
        return merged
    }

    private func writeAnswer(
        _ facts: String,
        question: String,
        excluding: String,
        skillID: String,
        context: AskContext,
        tools: [any Tool],
        guide: AskGuide,
        images: [URL] = [],
        profile: ReplyProfile = .writer,
        promptQuestion: String? = nil
    ) async -> ReplyWrite {
        let sessionTools = tools
        let mustCall = AskAppleCopy.replyMustCallTool(
            facts: facts,
            skillID: skillID,
            toolCount: sessionTools.count
        )
        if let placed = await photoPlace(question: question, images: images) {
            AskTrace.decision("photo place")
            if let text = placed.text { AskTrace.result(text) }
            return placed
        }
        if let detail = photoDetail(question: question, images: images) {
            AskTrace.decision("photo file")
            if let text = detail.text { AskTrace.result(text) }
            return detail
        }
        let photoFacts = AskImageFacts.block(images)
        let rich = AskMarkdownSelection.isOn
        var instructions = guide.resolvedReplyInstructions(rich: rich)
        if !sessionTools.isEmpty {
            let note = profile.toolNote.isEmpty ? AskAppleCopy.replyRule : profile.toolNote
            instructions = note + "\n\n" + instructions
        }
        let toolNames = Set(sessionTools.map(\.name))
        let lookupPlaces = facts.contains(AskAppleCopy.toolOnlySentence)
        var prompt = guide.replyPrompt(
            question: promptQuestion ?? question,
            skillID: skillID,
            facts: AskImageFacts.merging(facts, photoFacts: photoFacts),
            sections: context.sections,
            conversation: earlierConversation(guide, excluding: excluding)
        )
        if !images.isEmpty {
            let noun = images.count == 1 ? "image is" : "images are"
            prompt += "\n\nThe attached \(noun) part of this question. Answer from what it shows."
            if !photoFacts.isEmpty {
                prompt += " State a photo fact only when the question asks about the picture's time, place, or camera."
            }
        }
        let request = AskModelRequest(
            instructions: instructions,
            prompt: prompt,
            facts: facts,
            requiresToolCall: mustCall,
            imageURLs: images,
            profileID: profile.id,
            profileTitle: profile.title,
            workingTitle: profile.workingTitle
        )
        let written: AskWrittenReply
        do {
            let spanName = sessionTools.isEmpty ? "writer" : "specialist \(profile.id)"
            let draft = try await AskTrace.span(spanName) {
                AskTrace.attribute("profile", profile.id)
                let draft: AskWrittenReply
                if sessionTools.isEmpty {
                    draft = AskWrittenReply(text: try await model.writeReply(request))
                } else {
                    AskTrace.attribute("tools", "\(sessionTools.count)")
                    draft = try await model.writeReplyUsing(request, sessionTools)
                }
                let readings = mergedReadings(draft.readings, sessionTools)
                let written = AskWrittenReply(text: draft.text, readings: readings)
                AskTrace.result(written.text)
                if let apple = AskAppleCards.first(written.readings) {
                    AskTrace.attribute("apple", apple.name)
                }
                return written
            }
            written = draft
        } catch {
            let ledged = AskAppleTools.readings(in: sessionTools)
            if !ledged.isEmpty {
                AskTrace.decision("tool loop stopped")
                written = AskWrittenReply(text: "", readings: ledged)
            } else if let notice = AskModelSafety.notice(error), !notice.spoken.isEmpty {
                AskTrace.decision(notice.decision)
                return ReplyWrite(text: notice.spoken, readings: [])
            } else if AskModelSafety.keepsToolRead(error), !toolNames.isEmpty {
                AskTrace.decision(AskModelSafety.failure(error) ?? "schema")
                written = AskWrittenReply(text: "", readings: [])
            } else {
                AskTrace.decision(AskModelSafety.failure(error) ?? "reply write failed")
                return .none
            }
        }
        let repaired = await AskAppleRepair.apply(
            question: question,
            readings: written.readings,
            toolNames: toolNames,
            lookupPlaces: lookupPlaces
        )
        return settled(
            text: written.text,
            readings: repaired.readings,
            didChange: repaired.didChange,
            facts: facts,
            question: question,
            mustCall: mustCall,
            photoFacts: photoFacts
        )
    }

    private func settled(
        text raw: String,
        readings: [AskAppleReading],
        didChange: Bool,
        facts: String,
        question: String,
        mustCall: Bool,
        photoFacts: String
    ) -> ReplyWrite {
        let checked = AskAppleFacts.appending(facts, readings: readings)
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if didChange, let spoken = AskAppleCopy.sentence(from: readings), AskGuide.acceptsReply(spoken, facts: checked) {
            text = spoken
        } else if text.isEmpty, let fallback = AskAppleCopy.sentence(from: readings) {
            text = fallback
            AskTrace.decision("answered from tools")
        }
        // A photo that already states a time or place can answer when no tool ran.
        if readings.isEmpty, photoFacts.isEmpty, mustCall {
            AskTrace.decision("tool not used")
            return ReplyWrite(text: nil, readings: [])
        }
        text = AskLocationPin.adjust(text, question: question, readings: readings)
        text = AskReminderItem.speech(text, readings: readings, question: question)
        text = AskAlarmLine.speech(text, readings: readings, question: question)
        text = AskContactLine.speech(text, question: question, readings: readings)
        text = AskLocationPin.nearbySpeech(text, question: question, readings: readings)
        text = AskHealthCatalog.weekSpeech(text, question: question, readings: readings)
        let rich = AskMarkdownSelection.isOn
        text = AskGuide.keptAnswer(text, rich: rich)
        guard AskGuide.acceptsReply(text, facts: checked, rich: rich) else {
            AskTrace.decision("reply rejected")
            return ReplyWrite(text: nil, readings: readings)
        }
        return ReplyWrite(text: text, readings: readings)
    }

    /// Where the picture was taken comes from the file, not the device location tool.
    private func photoPlace(question: String, images: [URL]) async -> ReplyWrite? {
        guard AskImageFacts.asksWhereTaken(question) else { return nil }
        let shots = AskImageFacts.snapshots(images)
        guard !shots.isEmpty else { return nil }
        var spoken: [AskImageFacts.Snapshot] = []
        var lines: [String] = []
        for shot in shots {
            guard let latitude = shot.latitude, let longitude = shot.longitude else {
                spoken.append(shot)
                continue
            }
            let line = await AskPhotoLocation.pin(latitude: latitude, longitude: longitude)
            lines.append(line)
            let label = AskLocationPin.parse(line).label
            let place = label == AskPhotoLocation.unnamed ? (shot.place ?? label) : label
            spoken.append(AskImageFacts.Snapshot(
                date: shot.date,
                place: place,
                latitude: latitude,
                longitude: longitude
            ))
        }
        guard let text = AskImageFacts.whereTakenSentence(spoken) else { return nil }
        let readings = lines.isEmpty ? [] : [AskAppleReading(name: "location", lines: lines)]
        return ReplyWrite(text: text, readings: readings)
    }

    /// Megapixels, ppi, and the camera come from the file. The model was repeating the previous line.
    private func photoDetail(question: String, images: [URL]) -> ReplyWrite? {
        let shots = AskImageFacts.snapshots(images)
        guard !shots.isEmpty else { return nil }
        if AskImageFacts.asksPixels(question), let text = AskImageFacts.pixelSentence(shots, includesPPI: AskImageFacts.asksPPI(question)) {
            return ReplyWrite(text: text, readings: [])
        }
        if AskImageFacts.asksCamera(question), let text = AskImageFacts.cameraSentence(shots) {
            return ReplyWrite(text: text, readings: [])
        }
        if AskImageFacts.asksDate(question), let text = AskImageFacts.dateSentence(shots) {
            return ReplyWrite(text: text, readings: [])
        }
        return nil
    }

    /// Same skill, but each part asks a different thing about the attached picture.
    private func answersEachPhotoQuestion(_ pieces: [String], images: [URL]) -> Bool {
        guard AskImageFacts.distinctQuestions(pieces, hasPhotos: !images.isEmpty) else { return false }
        return !AskImageFacts.snapshots(images).isEmpty
    }

    private func mergedReadings(_ transcript: [AskAppleReading], _ tools: [any Tool]) -> [AskAppleReading] {
        let ledged = AskAppleTools.readings(in: tools)
        if transcript.isEmpty { return ledged }
        if ledged.isEmpty { return transcript }
        return ledged.count >= transcript.count ? ledged : transcript
    }

    private func offerFollowUp(after skill: AskSkill, question: String, context: AskContext) async -> AskFollowUp? {
        guard let guide = configuration.guide, guide.offersFollowUp else { return nil }
        let allowed = configuration.skills
            .map(\.id)
            .filter { $0.caseInsensitiveCompare(skill.id) != .orderedSame }
        guard !allowed.isEmpty else { return nil }
        let request = AskModelRequest(
            instructions: guide.resolvedFollowUpInstructions,
            prompt: guide.followUpPrompt(
                question: question,
                skillID: skill.id,
                allowed: allowed,
                sections: context.sections,
                conversation: transcriptLines(guide)
            )
        )
        do {
            let choice = try await AskTrace.span("offerFollowUp") {
                let choice = try await model.offerFollowUp(request)
                AskTrace.result(choice.question)
                return choice
            }
            guard let offer = AskGuide.acceptedFollowUp(choice, allowed: allowed, after: skill.id) else {
                AskTrace.decision("follow-up rejected")
                return nil
            }
            AskTrace.attribute("followUp", offer.question)
            return offer
        } catch {
            AskTrace.decision(AskModelSafety.failure(error) ?? "follow-up failed")
            return nil
        }
    }

    /// A bubble plus the capabilities card. No rewrite and no follow-up model call.
    private func capabilityPage(_ boundary: AskBoundary, question: String, context: AskContext) -> BuiltPage {
        let examples = AskCapabilities.examples(
            chips: configuration.chips(context),
            skills: configuration.skills
        )
        let spoken: String
        switch boundary {
        case .catalog:
            spoken = AskCapabilities.offer(examples)
        case .blocked:
            spoken = AskCapabilities.blocked(examples)
        case .outside, .none:
            spoken = AskCapabilities.outside(examples)
        }
        let card = AskCapabilities.card(spoken: spoken, domains: configuration.domains, skills: configuration.skills)
        let bubble = AskCardTranscript.bubble(card.text, card: card) ?? ""
        let page = AskPage(
            question: question,
            text: bubble,
            spoken: card.spoken,
            skillID: AskCapabilities.skillID,
            domainID: "",
            slots: [:],
            card: card
        )
        return BuiltPage(page: page, usedModel: false, fulfillment: .intent(card))
    }

    private func restoredCard(_ item: AskStoredPage) async -> AskIntentCard? {
        guard item.hasCard else { return nil }
        if item.skillID == AskCapabilities.skillID {
            return AskCapabilities.card(
                spoken: item.spoken.isEmpty ? item.text : item.spoken,
                domains: configuration.domains,
                skills: configuration.skills
            )
        }
        let reading = item.appleName.isEmpty
            ? nil
            : AskAppleReading(name: item.appleName, lines: item.appleLines)
        guard let skill = configuration.skill(id: item.skillID),
              case .intent(let make) = skill.fulfillment else {
            guard let reading else { return nil }
            let spoken = item.spoken.isEmpty ? item.text : item.spoken
            return AskAppleCards.make(
                reading,
                spoken: spoken,
                showsCoordinates: AskLocationPin.asks(item.question),
                playedBy: configuration.assistantName,
                custom: configuration.appleCard
            )
        }
        let snapshot = await configuration.context()
        let invocation = AskInvocation(
            utterance: item.question,
            skillID: skill.id,
            domainID: skill.domainID,
            slots: AskSlots.decode(item.slotsJSON),
            context: await contextForSkill(skill, fallback: snapshot),
            usedModel: false
        )
        let card = await make(invocation)
        return AskAppleCards.under(
            card,
            reading: reading,
            showsCoordinates: AskLocationPin.asks(item.question),
            playedBy: configuration.assistantName,
            custom: configuration.appleCard
        )
    }

    /// Turns already saved, without the question this reply is about to answer.
    private func earlierConversation(_ guide: AskGuide, excluding utterance: String) -> String {
        var turns = (try? store.transcript(assistantName: configuration.assistantName)) ?? []
        if let last = turns.last, last.role == "user", last.text == utterance {
            turns.removeLast()
        }
        return guide.conversation(turns: turns.map { ($0.role, $0.spoken.isEmpty ? $0.text : $0.spoken) }, assistantName: configuration.assistantName)
    }

    private func transcriptLines(_ guide: AskGuide) -> String {
        let turns = (try? store.transcript(assistantName: configuration.assistantName)) ?? []
        return guide.conversation(
            turns: turns.map { ($0.role, $0.spoken.isEmpty ? $0.text : $0.spoken) },
            assistantName: configuration.assistantName
        )
    }

    private func recordSlots(_ slots: [String: String]) {
        let visible = slots.filter { !configuration.omittedSlotKeys.contains($0.key) && !$0.value.isEmpty }
        guard !visible.isEmpty else { return }
        let text = visible.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        AskTrace.attribute("slots", text)
    }
}

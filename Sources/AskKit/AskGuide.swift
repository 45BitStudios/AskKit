import Foundation

/// Lines added to a built-in prompt, or a full replacement for it.
///
/// A string appends after the built-in text. `.replace` uses only the string you pass.
/// `.replace("")` turns that block off.
public struct AskGuideText: Sendable, Equatable, ExpressibleByStringLiteral {
    public var text: String
    public var replacesDefault: Bool

    public init(text: String, replacesDefault: Bool) {
        self.text = text
        self.replacesDefault = replacesDefault
    }

    public init(stringLiteral value: String) {
        self.init(text: value, replacesDefault: false)
    }

    public static func append(_ text: String) -> AskGuideText {
        AskGuideText(text: text, replacesDefault: false)
    }

    public static func replace(_ text: String) -> AskGuideText {
        AskGuideText(text: text, replacesDefault: true)
    }

    func resolved(default base: String) -> String {
        let extra = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let builtin = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if replacesDefault { return extra }
        if extra.isEmpty { return builtin }
        if builtin.isEmpty { return extra }
        return builtin + "\n" + extra
    }
}

/// The lines around the catalog AskKit generates.
///
/// Each block starts from a built-in best-practice prompt. Pass a string to append app lines.
/// Pass `.replace` to use only the app's lines.
/// Route instructions are the opening, then `CAPABILITIES`, then `RULES`.
/// A reply prompt is `QUESTION`, `SKILL`, `FACTS`, the app's named sections, and `CONVERSATION`.
/// A follow-up prompt adds `JUST ASKED`, `SKILL JUST ANSWERED`, and `ALLOWED`.
public struct AskGuide: Sendable, Equatable {
    public static let defaultRouteOpening = """
    You route a request to one skill id.
    Most requests ask one thing: return that one skill id from CAPABILITIES.
    Do not return a domain name.
    Two parts of the same question are still one skill.
    """

    public static let defaultRouteRules = """
    Return only a skill id copied from CAPABILITIES.
    Do not invent facts. CONTEXT is not a request.
    EARLIER, when present, lists earlier questions. Use it only to understand words such as this, that, or it. Route only REQUEST.
    """

    public static let defaultReplyInstructions = """
    Answer out loud in one or two short sentences.
    Rewrite FACTS in plain English. Do not invent facts that are not in FACTS.
    Sections after FACTS are background. Do not copy a fact from them that FACTS do not state.
    Stop after those sentences. Do not write a second paragraph.
    The chat bubble renders light Markdown. Use **bold** for song titles, album titles, people, places, and short status words when that helps scan the line. Use *italics* for an album title when the same sentence already bolds a song. Do not use headings, lists, links, or code.
    CONVERSATION is earlier in this chat. Use it to understand this, that, and there. Do not repeat an earlier answer.
    Do not use key=value, labels, or equals signs.
    Do not mention that the answer is generated.
    """

    public static let defaultFollowUpInstructions = """
    Offer the one next question this person is most likely to ask.
    skill is one id copied from ALLOWED, or none when nothing else would help.
    question is one short question under 12 words about that skill.
    Do not offer the skill that just answered.
    Do not invent facts. Do not use key=value or equals signs.
    """

    /// Lines before `CAPABILITIES`. A string appends to `defaultRouteOpening`.
    public var routeOpening: AskGuideText
    /// Lines under `RULES`. A string appends to `defaultRouteRules`.
    public var routeRules: AskGuideText
    /// How the model turns FACTS into the spoken answer. A string appends to `defaultReplyInstructions`.
    public var replyInstructions: AskGuideText
    /// How the model offers one next question. A string appends to `defaultFollowUpInstructions`.
    public var followUpInstructions: AskGuideText
    /// Label for the person in `CONVERSATION`.
    public var personLabel: String

    public init(
        routeOpening: AskGuideText = "",
        routeRules: AskGuideText = "",
        replyInstructions: AskGuideText = "",
        followUpInstructions: AskGuideText = "",
        personLabel: String = "person"
    ) {
        self.routeOpening = routeOpening
        self.routeRules = routeRules
        self.replyInstructions = replyInstructions
        self.followUpInstructions = followUpInstructions
        self.personLabel = personLabel
    }

    public var resolvedRouteOpening: String {
        routeOpening.resolved(default: Self.defaultRouteOpening)
    }

    public var resolvedRouteRules: String {
        routeRules.resolved(default: Self.defaultRouteRules)
    }

    public var resolvedReplyInstructions: String {
        replyInstructions.resolved(default: Self.defaultReplyInstructions)
    }

    public var resolvedFollowUpInstructions: String {
        followUpInstructions.resolved(default: Self.defaultFollowUpInstructions)
    }

    /// One catalog route replaces the domain hop and the skill hop.
    public var routesWithCatalog: Bool {
        !resolvedRouteOpening.isEmpty || !resolvedRouteRules.isEmpty
    }

    public var writesReply: Bool {
        !resolvedReplyInstructions.isEmpty
    }

    public var offersFollowUp: Bool {
        !resolvedFollowUpInstructions.isEmpty
    }

    public func routeInstructions(domains: [AskDomain], skills: [AskSkill]) -> String {
        var blocks: [String] = []
        if !resolvedRouteOpening.isEmpty { blocks.append(resolvedRouteOpening) }
        blocks.append("CAPABILITIES\n\(Self.capabilities(domains: domains, skills: skills))")
        if !resolvedRouteRules.isEmpty { blocks.append("RULES\n\(resolvedRouteRules)") }
        return blocks.joined(separator: "\n\n")
    }

    public func routePrompt(context: String, earlier: [String], request: String) -> String {
        var blocks = ["CONTEXT\n\(context)"]
        let prior = earlier
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !prior.isEmpty {
            blocks.append("EARLIER\n\(prior.joined(separator: "\n"))")
        }
        blocks.append("REQUEST\n\(request)")
        return blocks.joined(separator: "\n\n")
    }

    public func replyPrompt(
        question: String,
        skillID: String,
        facts: String,
        sections: [AskPromptSection],
        conversation: String
    ) -> String {
        var blocks = [
            "QUESTION\n\(question)",
            "SKILL\n\(skillID)",
            "FACTS\n\(Self.filled(facts))"
        ]
        blocks.append(contentsOf: Self.sectionBlocks(sections))
        if !conversation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append("CONVERSATION\n\(conversation)")
        }
        return blocks.joined(separator: "\n\n")
    }

    public func followUpPrompt(
        question: String,
        skillID: String,
        allowed: [String],
        sections: [AskPromptSection],
        conversation: String
    ) -> String {
        var blocks: [String] = []
        if !conversation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append("CONVERSATION\n\(conversation)")
        }
        blocks.append("JUST ASKED\n\(question)")
        blocks.append("SKILL JUST ANSWERED\n\(skillID)")
        blocks.append("ALLOWED\n\(allowed.joined(separator: ", "))")
        blocks.append(contentsOf: Self.sectionBlocks(sections))
        return blocks.joined(separator: "\n\n")
    }

    /// Each pair is a role (`user` or anything else) and the line that role said.
    public func conversation(turns: [(String, String)], assistantName: String) -> String {
        let person = personLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let speaker = person.isEmpty ? "person" : person
        return turns.suffix(8).compactMap { turn in
            let text = turn.1.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let label = turn.0 == "user" ? speaker : assistantName
            return "\(label): \(text)"
        }.joined(separator: "\n")
    }

    /// The spoken line. A blank line starts a background dump the prompt says not to copy.
    public static func spokenAnswer(_ written: String) -> String {
        let trimmed = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #"\n[ \t]*\n"#, options: .regularExpression) else { return trimmed }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Words without Markdown markers, for speech, Siri, and copy.
    ///
    /// Bubbles keep the Markdown. This drops only the inline syntax the bubble can draw.
    public static func plainSpeech(_ written: String) -> String {
        let trimmed = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: trimmed, options: options) else { return trimmed }
        return String(attributed.characters)
    }

    /// A rewrite that echoes `key=value` when FACTS did not is discarded.
    /// Only the paragraph before a blank line is kept, matching the streaming preview.
    public static func acceptsReply(_ written: String, facts: String) -> Bool {
        let trimmed = spokenAnswer(written)
        guard !trimmed.isEmpty, trimmed.count <= 600 else { return false }
        if trimmed.contains("="), !facts.contains("=") { return false }
        return true
    }

    /// Keeps a follow-up only when the skill is allowed and the question is short.
    public static func acceptedFollowUp(_ choice: AskFollowUp, allowed: [String], after skillID: String) -> AskFollowUp? {
        let token = choice.skillID.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = choice.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.caseInsensitiveCompare("none") != .orderedSame else { return nil }
        guard token.caseInsensitiveCompare(skillID) != .orderedSame else { return nil }
        guard allowed.contains(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) else { return nil }
        guard !question.isEmpty, question.count <= 140, question.caseInsensitiveCompare("none") != .orderedSame else {
            return nil
        }
        guard !question.contains("=") else { return nil }
        let skill = allowed.first { $0.caseInsensitiveCompare(token) == .orderedSame } ?? token
        return AskFollowUp(skillID: skill, question: question)
    }

    /// `domain: skill (summary), skill (summary)` in domain order, then skill order.
    public static func capabilities(domains: [AskDomain], skills: [AskSkill]) -> String {
        domains.compactMap { domain in
            let line = skills
                .filter { $0.domainID.compare(domain.id, options: .caseInsensitive) == .orderedSame }
                .map { "\($0.id) (\($0.summary))" }
                .joined(separator: ", ")
            guard !line.isEmpty else { return nil }
            return "\(domain.id): \(line)"
        }.joined(separator: "\n")
    }

    private static func sectionBlocks(_ sections: [AskPromptSection]) -> [String] {
        sections.compactMap { section in
            let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = section.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !text.isEmpty else { return nil }
            return "\(title)\n\(text)"
        }
    }

    private static func filled(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "none" : trimmed
    }
}

/// The next question the chat can offer after an answer.
public struct AskFollowUp: Sendable, Equatable {
    public var skillID: String
    public var question: String

    public init(skillID: String, question: String) {
        self.skillID = skillID
        self.question = question
    }
}

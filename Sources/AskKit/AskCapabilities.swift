import Foundation
#if ASK_FOUNDATION_MODELS
import FoundationModels
#endif
import SwiftUI

/// One skill a person can ask about, grouped under its domain.
public struct AskCapability: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// Skills that share a domain, in the order the app registered them.
public struct AskCapabilityGroup: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var items: [AskCapability]

    public init(id: String, title: String, items: [AskCapability]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// Answers "what can I do?" from the app's chips and skills, and the line used when a question is out of bounds.
public enum AskCapabilities {
    /// Stored on the transcript turn. Not a skill the router can pick.
    public static let skillID = "ask.capabilities"

    /// The whole question is asking what this assistant can do.
    /// "What can I do about the battery?" is a real request and returns false.
    public static func isQuestion(_ utterance: String) -> Bool {
        let folded = normalized(utterance)
        return questions.contains(folded)
    }

    /// Two phrases the bubble can name. Chips come first. They are already questions.
    public static func examples(chips: [AskChip], skills: [AskSkill]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ raw: String) {
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.lowercased()
            guard !title.isEmpty, seen.insert(key).inserted else { return }
            result.append(title)
        }
        for chip in chips { add(chip.title) }
        for skill in offered(skills) { add(skill.title) }
        return Array(result.prefix(2))
    }

    /// "You can ask me questions like Charge status or Range and I can help with that."
    public static func offer(_ examples: [String]) -> String {
        switch examples.count {
        case 0:
            return "You can ask me what this app is set up to answer, and I can help with that."
        case 1:
            return "You can ask me questions like \(examples[0]) and I can help with that."
        default:
            return "You can ask me questions like \(examples[0]) or \(examples[1]) and I can help with that."
        }
    }

    /// No skill matched. Names two things that do work.
    public static func outside(_ examples: [String]) -> String {
        let lead = "I can't help with that."
        guard !examples.isEmpty else { return lead }
        return lead + " " + offer(examples)
    }

    /// Apple's line for input the on-device model refuses, then two questions that do work.
    /// The person's words are not included.
    public static func blocked(_ examples: [String]) -> String {
        let lead = "Sorry, this feature isn't designed to handle that kind of input."
        guard !examples.isEmpty else { return lead }
        return lead + " " + offer(examples)
    }

    public static func groups(domains: [AskDomain], skills: [AskSkill]) -> [AskCapabilityGroup] {
        let offered = offered(skills)
        var grouped: [AskCapabilityGroup] = []
        var used = Set<String>()
        for domain in domains {
            let items = offered.filter { $0.domainID.caseInsensitiveCompare(domain.id) == .orderedSame }
            guard !items.isEmpty else { continue }
            used.insert(domain.id.lowercased())
            grouped.append(AskCapabilityGroup(
                id: domain.id,
                title: domain.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? domain.id : domain.summary,
                items: items.map(capability)
            ))
        }
        let leftovers = offered.filter { !used.contains($0.domainID.lowercased()) }
        let domainIDs = leftovers.map(\.domainID).reduce(into: [String]()) { ids, id in
            if !ids.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
                ids.append(id)
            }
        }
        for id in domainIDs {
            let items = leftovers.filter { $0.domainID.caseInsensitiveCompare(id) == .orderedSame }
            grouped.append(AskCapabilityGroup(id: id, title: id, items: items.map(capability)))
        }
        return grouped
    }

    @MainActor
    public static func card(spoken: String, domains: [AskDomain], skills: [AskSkill]) -> AskIntentCard {
        let grouped = groups(domains: domains, skills: skills)
        var card = AskIntentCard(
            title: "I can help with",
            spoken: spoken,
            facts: spoken,
            content: .builtIn(.capabilities(grouped))
        )
        card.shareText = shareLines(groups: grouped)
        card.expands = true
        return card
    }

    /// The lines drawn on the capabilities card, for Copy and Share.
    static func shareLines(groups: [AskCapabilityGroup]) -> String {
        var lines = ["I can help with"]
        for group in groups {
            let heading = group.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty { lines.append(heading) }
            for item in group.items {
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { lines.append(title) }
                let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if !detail.isEmpty { lines.append(detail) }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func capability(_ skill: AskSkill) -> AskCapability {
        AskCapability(id: skill.id, title: skill.title, detail: skill.summary)
    }

    /// `unknown` is a host fallback, not something to advertise.
    private static func offered(_ skills: [AskSkill]) -> [AskSkill] {
        skills.filter { $0.id.caseInsensitiveCompare("unknown") != .orderedSame }
    }

    private static func normalized(_ utterance: String) -> String {
        let pieces = utterance
            .lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var words = pieces
        if let last = words.last, last == "please" || last == "thanks" {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    private static let questions: Set<String> = [
        "what can i do",
        "what can i do here",
        "what can you do",
        "what can you do here",
        "what can you help with",
        "what can you help me with",
        "what can you help me do",
        "what are you able to do",
        "what do you do",
        "what can i ask",
        "what can i ask you",
        "what can i ask about",
        "what are your capabilities",
        "what are you capable of",
        "how can you help",
        "how can you help me",
        "what else can you do",
        "what else can i do",
        "show me what you can do",
        "what do you know how to do",
        "what are my options",
        "what can this do",
        "what can this app do"
    ]
}

enum AskModelSafety {
    struct Notice: Equatable {
        var decision: String
        /// Empty when the person should keep the skill line. The debug text stays in the trace.
        var spoken: String
    }

    static let contextWindow = "That question is too long for one answer."
    static let rateLimit = "Try that again in a moment."
    static let timeout = "That took too long. Try it again."
    static let language = "I can't answer in that language."
    static let cloudNetwork = "Private Cloud Compute couldn't connect. Try again."
    static let cloudQuota = "Private Cloud Compute is at its limit. Try again later."
    static let cloudUnavailable = "Private Cloud Compute isn't available right now."
    static let modelAssets = "The on-device model isn't ready."

    /// Apple's on-device guardrail or a model refusal. Other failures are ordinary errors.
    static func isBlocked(_ error: Error) -> Bool {
#if ASK_FOUNDATION_MODELS
        if let modelError = error as? LanguageModelError {
            switch modelError {
            case .guardrailViolation, .refusal:
                return true
            default:
                return false
            }
        }
        if let legacy = error as? LanguageModelSession.GenerationError {
            switch legacy {
            case .guardrailViolation, .refusal:
                return true
            default:
                return false
            }
        }
#endif
        return false
    }

    /// A trace decision for a model failure. Guardrail stays "guardrail".
    static func failure(_ error: Error) -> String? {
        if isBlocked(error) { return "guardrail" }
        return notice(error)?.decision
    }

    /// A sentence for a failure the person can act on. Schema and guide mismatches keep the skill line unless repair can read the specialist's source.
    static func notice(_ error: Error) -> Notice? {
        if error is AskModelUnavailable {
            return Notice(decision: "no model", spoken: "")
        }
#if ASK_FOUNDATION_MODELS
        if let modelError = error as? LanguageModelError {
            switch modelError {
            case .contextSizeExceeded:
                return Notice(decision: "context window", spoken: contextWindow)
            case .rateLimited:
                return Notice(decision: "rate limit", spoken: rateLimit)
            case .timeout:
                return Notice(decision: "timeout", spoken: timeout)
            case .unsupportedLanguageOrLocale:
                return Notice(decision: "language", spoken: language)
            case .unsupportedGenerationGuide:
                return Notice(decision: "unsupported guide", spoken: "")
            case .guardrailViolation, .refusal, .unsupportedCapability, .unsupportedTranscriptContent:
                return nil
            @unknown default:
                return nil
            }
        }
        if let cloud = error as? PrivateCloudComputeLanguageModel.Error {
            switch cloud {
            case .networkFailure:
                return Notice(decision: "cloud network", spoken: cloudNetwork)
            case .quotaLimitReached:
                return Notice(decision: "cloud quota", spoken: cloudQuota)
            case .serviceUnavailable:
                return Notice(decision: "cloud unavailable", spoken: cloudUnavailable)
            @unknown default:
                return nil
            }
        }
        if error is GeneratedContent.ParsingError {
            return Notice(decision: "schema", spoken: "")
        }
        if error is GenerationSchema.SchemaError {
            return Notice(decision: "schema", spoken: "")
        }
        if let assets = error as? SystemLanguageModel.Error {
            switch assets {
            case .assetsUnavailable:
                return Notice(decision: "model assets", spoken: modelAssets)
            @unknown default:
                return nil
            }
        }
        if let session = error as? LanguageModelSession.Error {
            switch session {
            case .concurrentRequests:
                return Notice(decision: "busy", spoken: rateLimit)
            case .transcriptMutationWhileResponding:
                return Notice(decision: "transcript", spoken: "")
            @unknown default:
                return nil
            }
        }
        if let legacy = error as? LanguageModelSession.GenerationError {
            switch legacy {
            case .exceededContextWindowSize:
                return Notice(decision: "context window", spoken: contextWindow)
            case .rateLimited:
                return Notice(decision: "rate limit", spoken: rateLimit)
            case .unsupportedLanguageOrLocale:
                return Notice(decision: "language", spoken: language)
            case .unsupportedGuide:
                return Notice(decision: "unsupported guide", spoken: "")
            case .decodingFailure:
                return Notice(decision: "schema", spoken: "")
            case .assetsUnavailable:
                return Notice(decision: "model assets", spoken: modelAssets)
            case .concurrentRequests:
                return Notice(decision: "busy", spoken: rateLimit)
            case .guardrailViolation, .refusal:
                return nil
            @unknown default:
                return nil
            }
        }
#endif
        return nil
    }

    /// The model emitted a tool call that does not match this specialist. The question can still be read.
    static func keepsToolRead(_ error: Error) -> Bool {
        notice(error)?.decision == "schema"
    }
}

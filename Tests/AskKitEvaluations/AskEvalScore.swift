import Foundation
@testable import AskKit

/// Scores a route, a spoken rewrite, and a follow-up against the rules the chat already enforces.
enum AskEvalScore {
    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    /// 1 when the skill matches, 0.5 when only the domain matches, otherwise 0.
    /// A reply that names the domain id itself still earns the half, because the area was right and no skill would run.
    static func routeCredit(gotSkill: String, gotDomain: String, expectedSkill: String, expectedDomain: String) -> Double {
        if same(gotSkill, expectedSkill) { return 1 }
        if !gotDomain.isEmpty, same(gotDomain, expectedDomain) { return 0.5 }
        return 0
    }

    /// The skill's domain, or the token itself when the model returned a domain id.
    static func resolvedDomain(of token: String, skills: [(id: String, domainID: String)], domains: [String]) -> String {
        if let skill = skills.first(where: { same($0.id, token) }) { return skill.domainID }
        return domains.first { same($0, token) } ?? ""
    }

    static func states(_ text: String, phrases: [String]) -> Bool {
        let folded = text.lowercased()
        return phrases.allSatisfy { folded.contains($0.lowercased()) }
    }

    /// Number tokens in the reply that FACTS do not contain as the same token.
    /// `2` is not covered by `214`, and `18,420` stays one token.
    static func inventedNumbers(in text: String, facts: String) -> [String] {
        let allowed = Set(numberTokens(in: facts))
        return numberTokens(in: text).filter { !allowed.contains($0) }
    }

    static func numberTokens(in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?"#) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    /// The spoken answer. A blank line starts the garage background the prompt says not to copy.
    static func answerParagraph(_ text: String) -> String {
        AskGuide.spokenAnswer(text)
    }

    static func hasBackgroundCopy(_ text: String) -> Bool {
        text.range(of: #"\n[ \t]*\n"#, options: .regularExpression) != nil
    }

    /// Spoken sentences. Decimals and `a.m.` / `p.m.` do not count as breaks.
    static func sentenceCount(_ text: String) -> Int {
        var masked = text
        masked = masked.replacingOccurrences(of: "a.m.", with: "am", options: .caseInsensitive)
        masked = masked.replacingOccurrences(of: "p.m.", with: "pm", options: .caseInsensitive)
        if let expression = try? NSRegularExpression(pattern: #"\d+[.,]\d+"#) {
            let range = NSRange(masked.startIndex..., in: masked)
            masked = expression.stringByReplacingMatches(in: masked, range: range, withTemplate: "0")
        }
        return masked
            .split { character in "?!.".contains(character) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace }.count
    }

    static func acceptedFollowUp(_ choice: AskFollowUp, allowed: [String], after skillID: String) -> Bool {
        AskGuide.acceptedFollowUp(choice, allowed: allowed, after: skillID) != nil
    }
}

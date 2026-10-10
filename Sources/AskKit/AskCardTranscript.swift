import Foundation

/// How a chat bubble sits next to a card.
/// The card view stays the app's. This only decides which sentences are still worth showing above it.
public enum AskCardTranscript {
    /// The bubble to show beside `card`, or nil when the card stands alone.
    ///
    /// A covered phrase (at least 3 characters, compared in lowercase) drops the sentence that contains it.
    /// "I can open", "I can show", and "I'll open" drop when the card has a button.
    /// If that removes every sentence, the original text stays, so the card is not the only reply.
    /// A reply that is only a navigation line stays hidden.
    /// `replacesBubble` hides the bubble. Leave a fact out of `coveredPhrases` when the sentence should stay.
    public static func bubble(_ text: String, card: AskIntentCard) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if card.replacesBubble { return nil }
        let phrases = card.coveredPhrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 3 }
        let hasAction = card.action != nil
        let sentences = Self.sentences(in: trimmed)
        let kept = sentences.filter { sentence in
            let lower = sentence.lowercased()
            if phrases.contains(where: { lower.contains($0) }) { return false }
            if hasAction, isNavigation(lower) { return false }
            return true
        }
        let joined = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
        let hasAnswer = sentences.contains { sentence in
            let lower = sentence.lowercased()
            if hasAction, isNavigation(lower) { return false }
            return true
        }
        return hasAnswer ? trimmed : nil
    }

    static func isNavigation(_ lower: String) -> Bool {
        lower.contains("i can open")
            || lower.contains("i can show")
            || lower.contains("i'll open")
            || lower.contains("i’ll open")
    }

    /// Splits on `.` `!` `?` and newlines. Periods inside `a.m.` and `p.m.` stay in the sentence.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)
            let boundary = character == "\n" || character == "!" || character == "?"
                || (character == "." && endsSentence(characters, period: index))
            if boundary {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
            index += 1
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private static func endsSentence(_ characters: [Character], period index: Int) -> Bool {
        if isMeridiemInternalDot(characters, index: index) { return false }
        if isMeridiemClosingDot(characters, index: index) {
            return nextSentenceStarts(characters, after: index)
        }
        return true
    }

    private static func isMeridiemInternalDot(_ characters: [Character], index: Int) -> Bool {
        guard index > 0, index + 1 < characters.count else { return false }
        let before = String(characters[index - 1]).lowercased()
        let after = String(characters[index + 1]).lowercased()
        return (before == "a" || before == "p") && after == "m"
    }

    private static func isMeridiemClosingDot(_ characters: [Character], index: Int) -> Bool {
        guard index >= 3 else { return false }
        let letter = String(characters[index - 1]).lowercased()
        return letter == "m"
            && characters[index - 2] == "."
            && (String(characters[index - 3]).lowercased() == "a" || String(characters[index - 3]).lowercased() == "p")
    }

    private static func nextSentenceStarts(_ characters: [Character], after index: Int) -> Bool {
        var next = index + 1
        while next < characters.count, characters[next] == " " { next += 1 }
        guard next < characters.count else { return true }
        return characters[next].isUppercase
    }
}

import Foundation

/// Prior generated-card facts passed into a later compose prompt.
/// The block is bounded so a long thread cannot grow the prompt without limit.
public enum AskGeneratedContext {
    /// Characters of prior facts included in the next compose prompt.
    public static let factLimit = 1_200
    /// How many earlier cards can contribute. Older cards are dropped first.
    public static let cardLimit = 6

    /// One card's title and facts, ready to join with the others.
    public static func block(title: String, facts: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = facts.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return body }
        if body.isEmpty { return name }
        if body.range(of: name, options: .caseInsensitive) != nil { return body }
        return "\(name)\n\(body)"
    }

    /// Newest cards that fit in `limit` characters, oldest first in the result.
    /// A card that cannot fit whole is dropped. When nothing else fits, the newest card is truncated.
    public static func bounded(
        _ facts: [String],
        limit: Int = factLimit,
        cards: Int = cardLimit
    ) -> String {
        let cleaned = facts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard limit > 0, cards > 0, !cleaned.isEmpty else { return "" }
        let recent = Array(cleaned.suffix(max(cards, 0)))
        var kept: [String] = []
        var used = 0
        for block in recent.reversed() {
            let gap = kept.isEmpty ? 0 : 2
            if used + gap + block.count <= limit {
                kept.append(block)
                used += gap + block.count
                continue
            }
            if kept.isEmpty {
                kept.append(String(block.prefix(limit)))
            }
            break
        }
        return kept.reversed().joined(separator: "\n\n")
    }
}

/// Generated cards kept in one thread. A follow-up appends. It does not replace the earlier cards.
@MainActor
public struct AskGeneratedThread {
    public struct Entry: Identifiable {
        public var id: UUID
        public var question: String
        public var card: AskComposedCard

        public init(id: UUID = UUID(), question: String, card: AskComposedCard) {
            self.id = id
            self.question = question
            self.card = card
        }

        /// Title and facts from this card, for the next compose prompt.
        public var factsBlock: String {
            AskGeneratedContext.block(title: card.card.title, facts: card.card.facts)
        }
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    /// Facts from the cards already in the thread, bounded for the next prompt.
    public var priorFacts: String {
        AskGeneratedContext.bounded(entries.map(\.factsBlock))
    }

    public mutating func append(question: String, card: AskComposedCard) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.append(Entry(question: trimmed.isEmpty ? card.card.title : trimmed, card: card))
    }
}

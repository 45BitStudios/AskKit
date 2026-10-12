import Foundation

/// One answer inside a turn.
/// The chat shows `text` in its own bubble, then `card`, then that card's button.
/// Several pages swipe sideways. The card view is not stored.
public struct AskPage: Identifiable {
    public var id: UUID
    /// The part of the person's message this page answers.
    public var question: String
    /// Bubble text. Empty when the card is the whole answer.
    public var text: String
    public var spoken: String
    public var skillID: String
    public var domainID: String
    public var slots: [String: String]
    public var card: AskIntentCard?
    /// Buttons for a reply that has no card.
    public var actions: [AskAction]
    /// The Apple source this reply read, when the fact card came from that read.
    public var appleReading: AskAppleReading?

    public init(
        id: UUID = UUID(),
        question: String = "",
        text: String,
        spoken: String,
        skillID: String,
        domainID: String,
        slots: [String: String] = [:],
        card: AskIntentCard? = nil,
        actions: [AskAction] = [],
        appleReading: AskAppleReading? = nil
    ) {
        self.id = id
        self.question = question
        self.text = text
        self.spoken = spoken
        self.skillID = skillID
        self.domainID = domainID
        self.slots = slots
        self.card = card
        self.actions = actions
        self.appleReading = appleReading
    }
}

/// Splits one message into at most three questions.
/// A whole capabilities question stays one piece. A trailing `?` does not create an empty piece.
enum AskPages {
    static let maximum = 3

    static func pieces(_ utterance: String) -> [String] {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if AskCapabilities.isQuestion(trimmed) { return [trimmed] }
        let parts = split(trimmed)
        guard parts.count > 1 else { return [trimmed] }
        return Array(parts.prefix(maximum))
    }

    private static func split(_ utterance: String) -> [String] {
        guard let separator = try? NSRegularExpression(
            pattern: #"\s*(?:[?;!])\s*|,?\s+(?:and also|and then|also|plus|and)\s+"#,
            options: [.caseInsensitive]
        ) else {
            return [utterance]
        }
        let range = NSRange(utterance.startIndex..., in: utterance)
        var raw: [String] = []
        var start = utterance.startIndex
        for match in separator.matches(in: utterance, range: range) {
            guard let matched = Range(match.range, in: utterance) else { continue }
            raw.append(String(utterance[start..<matched.lowerBound]))
            start = matched.upperBound
        }
        raw.append(String(utterance[start...]))
        return raw.compactMap(clean)
    }

    private static func clean(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let leading = try? NSRegularExpression(
            pattern: #"^(?:and also|and then|also|plus|and)\s+"#,
            options: [.caseInsensitive]
        ),
           let match = leading.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            text = String(text[range.upperBound...])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard text.count >= 2 else { return nil }
        return text
    }
}

struct AskStoredAction: Codable {
    var id: String
    var title: String
}

struct AskStoredPage: Codable {
    var id: UUID
    var question: String
    var text: String
    var spoken: String
    var skillID: String
    var domainID: String
    var slotsJSON: String
    var hasCard: Bool
    var actions: [AskStoredAction]
    /// Empty when this page did not read an Apple source.
    var appleName: String
    var appleLines: [String]
    /// JSON for a generative card DSL tree. Empty when the card is host-drawn.
    var cardJSON: String
    /// Title for a generative card rebuild.
    var cardTitle: String

    private enum CodingKeys: String, CodingKey {
        case id, question, text, spoken, skillID, domainID, slotsJSON, hasCard, actions, appleName, appleLines
        case cardJSON, cardTitle
    }

    init(
        id: UUID,
        question: String,
        text: String,
        spoken: String,
        skillID: String,
        domainID: String,
        slotsJSON: String,
        hasCard: Bool,
        actions: [AskStoredAction],
        appleName: String = "",
        appleLines: [String] = [],
        cardJSON: String = "",
        cardTitle: String = ""
    ) {
        self.id = id
        self.question = question
        self.text = text
        self.spoken = spoken
        self.skillID = skillID
        self.domainID = domainID
        self.slotsJSON = slotsJSON
        self.hasCard = hasCard
        self.actions = actions
        self.appleName = appleName
        self.appleLines = appleLines
        self.cardJSON = cardJSON
        self.cardTitle = cardTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        question = try container.decode(String.self, forKey: .question)
        text = try container.decode(String.self, forKey: .text)
        spoken = try container.decode(String.self, forKey: .spoken)
        skillID = try container.decode(String.self, forKey: .skillID)
        domainID = try container.decode(String.self, forKey: .domainID)
        slotsJSON = try container.decode(String.self, forKey: .slotsJSON)
        hasCard = try container.decode(Bool.self, forKey: .hasCard)
        actions = try container.decode([AskStoredAction].self, forKey: .actions)
        appleName = try container.decodeIfPresent(String.self, forKey: .appleName) ?? ""
        appleLines = try container.decodeIfPresent([String].self, forKey: .appleLines) ?? []
        cardJSON = try container.decodeIfPresent(String.self, forKey: .cardJSON) ?? ""
        cardTitle = try container.decodeIfPresent(String.self, forKey: .cardTitle) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(question, forKey: .question)
        try container.encode(text, forKey: .text)
        try container.encode(spoken, forKey: .spoken)
        try container.encode(skillID, forKey: .skillID)
        try container.encode(domainID, forKey: .domainID)
        try container.encode(slotsJSON, forKey: .slotsJSON)
        try container.encode(hasCard, forKey: .hasCard)
        try container.encode(actions, forKey: .actions)
        try container.encode(appleName, forKey: .appleName)
        try container.encode(appleLines, forKey: .appleLines)
        try container.encode(cardJSON, forKey: .cardJSON)
        try container.encode(cardTitle, forKey: .cardTitle)
    }
}

enum AskStoredPages {
    static func encode(_ pages: [AskPage], omitting keys: Set<String>) -> String {
        let stored = pages.map { page in
            var cardActions = page.actions.map { AskStoredAction(id: $0.id, title: $0.title) }
            if let action = page.card?.action,
               !cardActions.contains(where: { $0.id.caseInsensitiveCompare(action.id) == .orderedSame }) {
                cardActions.insert(AskStoredAction(id: action.id, title: action.title), at: 0)
            }
            return AskStoredPage(
                id: page.id,
                question: page.question,
                text: page.text,
                spoken: page.spoken,
                skillID: page.skillID,
                domainID: page.domainID,
                slotsJSON: AskSlots.json(page.slots, omitting: keys),
                hasCard: page.card != nil,
                actions: cardActions,
                appleName: page.appleReading?.name ?? "",
                appleLines: page.appleReading?.lines ?? [],
                cardJSON: page.card?.generatedRoot.map(AskGeneratedCard.encode) ?? "",
                cardTitle: page.card?.title ?? ""
            )
        }
        guard let data = try? JSONEncoder().encode(stored),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    static func decode(_ json: String) -> [AskStoredPage] {
        guard let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode([AskStoredPage].self, from: data) else {
            return []
        }
        return stored
    }

    /// Pages the chat can draw before card views are rebuilt. Ids match the stored pages.
    static func display(
        json: String,
        fallbackID: UUID,
        fallbackText: String,
        fallbackSpoken: String,
        skillID: String,
        domainID: String,
        slotsJSON: String
    ) -> [AskPage] {
        let stored = decode(json)
        if stored.isEmpty {
            return [
                AskPage(
                    id: fallbackID,
                    text: fallbackText,
                    spoken: fallbackSpoken,
                    skillID: skillID,
                    domainID: domainID,
                    slots: AskSlots.decode(slotsJSON)
                )
            ]
        }
        return stored.map { item in
            AskPage(
                id: item.id,
                question: item.question,
                text: item.text,
                spoken: item.spoken,
                skillID: item.skillID,
                domainID: item.domainID,
                slots: AskSlots.decode(item.slotsJSON),
                actions: item.actions.map { AskAction(id: $0.id, title: $0.title) }
            )
        }
    }
}

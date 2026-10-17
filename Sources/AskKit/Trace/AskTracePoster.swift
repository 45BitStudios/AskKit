#if DEBUG
import Foundation

package struct AskTracePosterCard: Equatable {
    package var title: String
    package var body: String
}

package struct AskTracePosterContent: Equatable {
    package var question: String
    package var answer: String
    package var cards: [AskTracePosterCard]
}

/// A picture of what the turn showed: the question, the answer, and each card's words.
package enum AskTracePoster {
    static let bodyLimit = 2_000
    package static let width: CGFloat = 390

    package static func content(for turn: AskTraceTurn) -> AskTracePosterContent {
        let titles = titles(in: turn)
        let recorded = recordedBodies(in: turn)
        let answer = first("shownAnswer", in: turn) ?? "It was not recorded."
        return AskTracePosterContent(
            question: turn.question,
            answer: answer,
            cards: cards(titles: titles, bodies: recorded, tools: tools(in: turn), answer: answer)
        )
    }

    /// JSON array of each card's share text, in the same order as `shownCards`. Nil when every body is blank.
    static func encodeBodies(_ bodies: [String]) -> String? {
        let trimmed = bodies.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.contains(where: { !$0.isEmpty }) else { return nil }
        guard let data = try? JSONEncoder().encode(trimmed), let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private static func cards(titles: [String], bodies: [String]?, tools: [ToolFact], answer: String) -> [AskTracePosterCard] {
        if let bodies, bodies.count == titles.count {
            let recorded = zip(titles, bodies).map { title, body in
                AskTracePosterCard(title: title, body: clipped(displayBody(title: title, share: body)))
            }
            return preferTools(recorded, tools: tools, answer: answer)
        }
        guard !titles.isEmpty else { return [] }
        var unused = tools
        var cards: [AskTracePosterCard] = []
        for title in titles {
            if let index = unused.firstIndex(where: { matches(title, $0.name) }) {
                let tool = unused.remove(at: index)
                cards.append(AskTracePosterCard(title: title, body: clipped(tool.body)))
            } else {
                cards.append(AskTracePosterCard(title: title, body: ""))
            }
        }
        let open = cards.indices.filter { cards[$0].body.isEmpty }
        if !open.isEmpty, open.count == unused.count {
            for (slot, tool) in zip(open, unused) {
                cards[slot].body = clipped(tool.body)
            }
            unused.removeAll()
        }
        for tool in unused {
            cards.append(AskTracePosterCard(title: tool.name, body: clipped(tool.body)))
        }
        return cards
    }

    /// A recorded body that is only the spoken answer is the bubble again. The tool line is the card.
    private static func preferTools(_ cards: [AskTracePosterCard], tools: [ToolFact], answer: String) -> [AskTracePosterCard] {
        guard !tools.isEmpty else { return cards }
        var unused = tools
        var cards = cards
        for index in cards.indices {
            let body = cards[index].body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.isEmpty || folded(body) == folded(answer) else { continue }
            let replacement: String?
            if cards.count == 1, unused.count == 1 {
                replacement = unused.removeFirst().body
            } else if let match = unused.firstIndex(where: { matches(cards[index].title, $0.name) }) {
                replacement = unused.remove(at: match).body
            } else {
                replacement = nil
            }
            if let replacement {
                let words = readable(replacement)
                if !words.isEmpty { cards[index].body = clipped(words) }
            }
        }
        return cards
    }

    private static func readable(_ toolBody: String) -> String {
        toolBody
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if let item = AskMusicLine.item(from: text) {
                    return [item.artist, item.detail, item.extra].filter { !$0.isEmpty }.joined(separator: "\n")
                }
                if let day = AskWeatherLine.day(from: text) {
                    return [day.condition, "High \(day.high)", "Low \(day.low)", day.rain.isEmpty ? "" : "Rain \(day.rain)"]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                }
                if text.hasPrefix("Hour:") { return text }
                if text.hasPrefix("Place:") { return "" }
                return text
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func displayBody(title: String, share: String) -> String {
        let share = share.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if share.isEmpty || share.caseInsensitiveCompare(title) == .orderedSame { return "" }
        let prefix = title + "\n"
        if share.lowercased().hasPrefix(prefix.lowercased()) {
            return String(share.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return share
    }

    private static func clipped(_ text: String) -> String {
        guard text.count > bodyLimit else { return text }
        let end = text.index(text.startIndex, offsetBy: bodyLimit)
        return String(text[..<end]) + "…"
    }

    private struct ToolFact {
        var name: String
        var body: String
    }

    private static func tools(in turn: AskTraceTurn) -> [ToolFact] {
        turn.spans.compactMap { span in
            guard span.kind == .tool else { return nil }
            guard let result = span.result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty else { return nil }
            let name = toolName(span.name)
            guard !name.isEmpty else { return nil }
            return ToolFact(name: name, body: result)
        }
    }

    private static func toolName(_ spanName: String) -> String {
        if spanName.lowercased().hasPrefix("tool ") {
            return String(spanName.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return spanName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ title: String, _ name: String) -> Bool {
        let title = folded(title)
        let name = folded(name)
        guard !title.isEmpty, !name.isEmpty else { return false }
        return title == name || title.contains(name) || name.contains(title)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func titles(in turn: AskTraceTurn) -> [String] {
        guard let raw = first("shownCards", in: turn) else { return [] }
        return raw.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func recordedBodies(in turn: AskTraceTurn) -> [String]? {
        guard let raw = first("shownCardBodies", in: turn), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private static func first(_ key: String, in turn: AskTraceTurn) -> String? {
        for span in turn.spans {
            for attribute in span.attributes where attribute.key == key {
                let trimmed = attribute.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
#endif

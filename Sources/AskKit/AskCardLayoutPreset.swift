import Foundation

/// A focused layout for one kind of card. The notes steer composition through the existing LAYOUT block.
///
/// Presets do not add primitives. A blueprint id wins, then the card specialist's id, then inference
/// when the blueprint has no layout notes. Skill notes are kept and appended after the preset.
public struct AskCardLayoutPreset: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// One line for the toolkit.
    public var summary: String
    /// LAYOUT text. Uses only the kinds the renderer already draws.
    public var layoutNotes: String
    var hints: [AskCardLayoutHint]

    public static func == (lhs: AskCardLayoutPreset, rhs: AskCardLayoutPreset) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.summary == rhs.summary
            && lhs.layoutNotes == rhs.layoutNotes
            && lhs.hints == rhs.hints
    }

    public static let weather = AskCardLayoutPreset(
        id: "weather",
        title: "Weather",
        summary: "Temperature, high and low, and the hours.",
        layoutNotes: """
        Weather. Use a hero symbol for the condition, then an eyebrow, then one stat for the temperature. \
        Badge says Weather. High and low are figure nodes in one hstack, not more stats. \
        Each hour is a mini symbol above a figure.
        """,
        hints: [
            AskCardLayoutHint(needle: "weather", weight: 2),
            AskCardLayoutHint(needle: "forecast", weight: 2),
            AskCardLayoutHint(needle: "°", weight: 1, literal: true),
            AskCardLayoutHint(needle: "degrees", weight: 1),
            AskCardLayoutHint(needle: "cloudy", weight: 1),
            AskCardLayoutHint(needle: "rain", weight: 1),
            AskCardLayoutHint(needle: "humidity", weight: 1),
            AskCardLayoutHint(needle: "temperature", weight: 1)
        ]
    )

    public static let schedule = AskCardLayoutPreset(
        id: "schedule",
        title: "Schedule",
        summary: "A day or a count, then one row per event.",
        layoutNotes: """
        Schedule. Use a plate, then an eyebrow for the day, then one stat. Badge names the calendar. \
        Each event is a mini symbol beside a row. The event title is the row text and the time is the detail.
        """,
        hints: [
            AskCardLayoutHint(needle: "agenda", weight: 2),
            AskCardLayoutHint(needle: "calendar", weight: 2),
            AskCardLayoutHint(needle: "schedule", weight: 2),
            AskCardLayoutHint(needle: "a.m.", weight: 1, literal: true),
            AskCardLayoutHint(needle: "p.m.", weight: 1, literal: true),
            AskCardLayoutHint(needle: " am", weight: 1, literal: true),
            AskCardLayoutHint(needle: " pm", weight: 1, literal: true),
            AskCardLayoutHint(needle: "event", weight: 1),
            AskCardLayoutHint(needle: "kick-off", weight: 1)
        ]
    )

    public static let health = AskCardLayoutPreset(
        id: "health",
        title: "Health summary",
        summary: "One metric, then the peer numbers.",
        layoutNotes: """
        Health summary. Use a plate for the metric, then an eyebrow for the period, then one stat for the main number. \
        Badge names the metric. Peer numbers are figure nodes in one hstack, each with a mini symbol above. \
        Do not add a chart or a second stat.
        """,
        hints: [
            AskCardLayoutHint(needle: "steps", weight: 2),
            AskCardLayoutHint(needle: "heart rate", weight: 2, literal: true),
            AskCardLayoutHint(needle: "sleep", weight: 2),
            AskCardLayoutHint(needle: "workout", weight: 2),
            AskCardLayoutHint(needle: "heart", weight: 1),
            AskCardLayoutHint(needle: "exercise", weight: 1),
            AskCardLayoutHint(needle: "flights", weight: 1),
            AskCardLayoutHint(needle: "bpm", weight: 1),
            AskCardLayoutHint(needle: "health", weight: 1)
        ]
    )

    public static let comparison = AskCardLayoutPreset(
        id: "comparison",
        title: "Comparison",
        summary: "Peer values side by side.",
        layoutNotes: """
        Comparison. One eyebrow, then the peer values as figure nodes in one hstack. \
        Each figure's detail is the short label. Do not add a second stat. A mini symbol may sit above each figure.
        """,
        hints: [
            AskCardLayoutHint(needle: " vs ", weight: 2, literal: true),
            AskCardLayoutHint(needle: "versus", weight: 2),
            AskCardLayoutHint(needle: "compared", weight: 2),
            AskCardLayoutHint(needle: "comparison", weight: 2)
        ]
    )

    public static let singleStat = AskCardLayoutPreset(
        id: "stat",
        title: "Single stat",
        summary: "One number and an optional line.",
        layoutNotes: """
        Single stat. One plate or hero symbol, then an eyebrow, then one stat. Badge names the domain. \
        At most one text line under the stat. No figures and no rows.
        """,
        hints: []
    )

    public static let all: [AskCardLayoutPreset] = [
        weather, schedule, health, comparison, singleStat
    ]

    /// Domain presets that can win inference. Single stat is the thin-facts fallback.
    private static let domains: [AskCardLayoutPreset] = [
        weather, schedule, health, comparison
    ]

    public static func named(_ id: String) -> AskCardLayoutPreset? {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return all.first { $0.id == key }
    }

    /// Picks a preset from the title, facts, and spoken line.
    /// A domain needs a score of 2, and a tie returns nil. One to three fact lines with no domain hint use single stat.
    public static func infer(title: String, facts: String, spoken: String) -> AskCardLayoutPreset? {
        let haystack = [title, facts, spoken]
            .joined(separator: "\n")
            .lowercased()
        let scored = domains.map { (preset: $0, score: score($0, in: haystack)) }
        let best = scored.map(\.score).max() ?? 0
        if best >= 2 {
            let leaders = scored.filter { $0.score == best }
            return leaders.count == 1 ? leaders[0].preset : nil
        }
        guard scored.allSatisfy({ $0.score == 0 }) else { return nil }
        let lines = facts
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard (1...3).contains(lines.count) else { return nil }
        return .singleStat
    }

    /// Blueprint id, then the specialist id, then inference when the blueprint left layout notes empty.
    public static func resolved(
        title: String,
        facts: String,
        spoken: String,
        layoutNotes: String,
        layoutPresetID: String,
        specialistPresetID: String = ""
    ) -> AskCardLayoutPreset? {
        if let chosen = named(layoutPresetID) { return chosen }
        if let chosen = named(specialistPresetID) { return chosen }
        let host = layoutNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty else { return nil }
        return infer(title: title, facts: facts, spoken: spoken)
    }

    /// Preset notes, then the host's notes when they add something the preset does not already say.
    public static func notes(from preset: AskCardLayoutPreset?, layoutNotes: String) -> String {
        let host = layoutNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let preset else { return host }
        if host.isEmpty { return preset.layoutNotes }
        if host == preset.layoutNotes || host.hasPrefix(preset.layoutNotes) { return host }
        return preset.layoutNotes + "\n" + host
    }

    private static func score(_ preset: AskCardLayoutPreset, in haystack: String) -> Int {
        preset.hints.reduce(0) { partial, hint in
            partial + (matches(hint, in: haystack) ? hint.weight : 0)
        }
    }

    private static func matches(_ hint: AskCardLayoutHint, in haystack: String) -> Bool {
        if hint.literal { return haystack.contains(hint.needle) }
        var rest = haystack[...]
        while let range = rest.range(of: hint.needle) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == haystack.endIndex
                || !haystack[range.upperBound].isLetter
            if beforeOK && afterOK { return true }
            rest = haystack[range.upperBound...]
        }
        return false
    }
}

struct AskCardLayoutHint: Sendable, Equatable {
    var needle: String
    var weight: Int
    /// Substring match. Off for a whole word, so "heart" does not hit "hearty" and "steps" does not hit "footsteps".
    var literal: Bool = false
}

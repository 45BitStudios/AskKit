import Foundation
#if ASK_FOUNDATION_MODELS
import FoundationModels
#endif
import SwiftUI

/// One node in AskKit's card layout DSL.
/// The model emits a shallow tree of these; ``AskGeneratedCardView`` maps them to SwiftUI.
/// This is not SwiftUI source — kinds are a closed set the renderer understands.
/// The model fills ``AskCardNodeDraft``, which has the same fields.
public struct AskCardNode: Sendable, Equatable, Codable {
    /// Raw value of an ``AskCardNodeKind``. Meaning, prompt text, and sanitizer rules live on ``AskCardPrimitive``.
    public var kind: String
    /// Primary text. Empty for pure layout nodes.
    public var text: String
    /// Secondary text for `stat`, `figure`, and `row`. Empty otherwise.
    public var detail: String
    /// Action id copied from ALLOWED when kind is `action`. Empty otherwise.
    public var actionID: String
    /// Child nodes. Prefer shallow trees. Empty for leaves.
    public var children: [AskCardNode]
    /// Where this node's facts came from. Empty when the node has no attribution.
    /// Older card JSON omits this field and still decodes.
    public var sources: [AskCardSource]

    public init(
        kind: String,
        text: String = "",
        detail: String = "",
        actionID: String = "",
        children: [AskCardNode] = [],
        sources: [AskCardSource] = []
    ) {
        self.kind = kind
        self.text = text
        self.detail = detail
        self.actionID = actionID
        self.children = children
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case detail
        case actionID
        case children
        case sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        actionID = try container.decodeIfPresent(String.self, forKey: .actionID) ?? ""
        children = try container.decodeIfPresent([AskCardNode].self, forKey: .children) ?? []
        sources = try container.decodeIfPresent([AskCardSource].self, forKey: .sources) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(detail, forKey: .detail)
        try container.encode(actionID, forKey: .actionID)
        try container.encode(children, forKey: .children)
        if !sources.isEmpty {
            try container.encode(sources, forKey: .sources)
        }
    }
}

#if ASK_FOUNDATION_MODELS
/// What the model generates for one ``AskCardNode``. Kept apart so the node itself builds where Foundation Models does not.
/// `@Guide` needs a string literal. The words are ``AskCardPrimitive``'s draft guides. A test fails when they drift.
@Generable
struct AskCardNodeDraft {
    @Guide(description: "One of: vstack, hstack, text, stat, figure, quote, eyebrow, badge, plate, symbol, divider, spacer, row, action")
    var kind: String
    @Guide(description: "Primary text. Empty for layout, divider, and spacer nodes.")
    var text: String
    @Guide(description: "Secondary text for stat, figure, or row. Empty otherwise.")
    var detail: String
    @Guide(description: "Action id copied from ALLOWED when kind is action. Empty otherwise.")
    var actionID: String
    @Guide(description: "Child nodes. Prefer at most two levels. Empty for leaves.")
    var children: [AskCardNodeDraft]

    var node: AskCardNode {
        AskCardNode(kind: kind, text: text, detail: detail, actionID: actionID, children: children.map(\.node))
    }
}
#endif

/// Closed layout kinds the renderer accepts.
public enum AskCardNodeKind: String, Sendable, CaseIterable {
    case vstack
    case hstack
    case text
    case stat
    case figure
    case quote
    case eyebrow
    case badge
    case plate
    case symbol
    case divider
    case spacer
    case row
    case action

    public static func parse(_ raw: String) -> AskCardNodeKind? {
        AskCardNodeKind(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// Layout profile for generative cards.
///
/// Separate from ``AskSpecialist``: no tools, no question matching, and it does not count toward
/// the three reply specialists on a turn. AskKit ships built-in CARD DSL instructions. An app
/// appends or replaces those with its own layout rules, the same way ``AskGuide`` customizes replies.
public struct AskCardSpecialist: Sendable, Equatable {
    public var id: String
    public var title: String
    public var symbolName: String
    /// Status line while the compose session is active.
    public var workingTitle: String
    /// App layout rules. A string appends after AskKit's built-in CARD DSL instructions.
    /// `.replace` uses only the app's text for that block.
    public var instructions: AskGuideText
    /// ``AskCardLayoutPreset`` id used when a blueprint does not name one. Empty leaves inference to the blueprint.
    public var layoutPresetID: String

    public init(
        id: String = "ask.card",
        title: String = "Card layout",
        symbolName: String = "rectangle.3.group",
        workingTitle: String = "Laying out the card",
        instructions: AskGuideText = .append(""),
        layoutPresetID: String = ""
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.workingTitle = workingTitle
        self.instructions = instructions
        self.layoutPresetID = layoutPresetID
    }

    /// AskKit defaults with no app lines.
    public static let `default` = AskCardSpecialist()
}

/// Where a generative card's tree came from.
public enum AskCardLayoutSource: String, Sendable, Equatable {
    /// The skill passed a finished tree. The model was not asked.
    case skill = "from the skill"
    /// The model composed the tree from the facts.
    case model = "from the model"
    /// Compose failed, so the fact layout was used.
    case facts = "from the facts"

    /// Story line for this source.
    public var sentence: String {
        switch self {
        case .skill: "The card layout came from the skill."
        case .model: "The model composed the card layout."
        case .facts: "The fact layout was used for the card."
        }
    }
}

/// A card laid out from a blueprint, plus which path produced the tree.
@MainActor
public struct AskComposedCard {
    public var card: AskIntentCard
    public var layout: AskCardLayoutSource

    public init(card: AskIntentCard, layout: AskCardLayoutSource) {
        self.card = card
        self.layout = layout
    }
}

/// Facts and chrome a `.generated` skill hands AskKit before layout composition.
public struct AskGeneratedBlueprint: Sendable {
    public var title: String
    public var spoken: String
    public var text: String?
    public var facts: String
    public var coveredPhrases: [String]
    /// Actions the DSL may reference by id. Unknown action ids are dropped.
    public var actions: [AskAction]
    /// Optional prebuilt tree. When nil, AskKit asks the model, then falls back to a fact card.
    public var root: AskCardNode?
    /// When true the chat card can zoom to full screen.
    public var expands: Bool
    /// Extra layout rules for this skill only. Appended after the card specialist instructions.
    public var layoutNotes: String
    /// Where the facts came from. Copied onto the composed tree and shown as "Source: …".
    public var sources: [AskCardSource]
    /// ``AskCardLayoutPreset`` id for this card. Empty infers a preset when `layoutNotes` is also empty.
    public var layoutPresetID: String

    public init(
        title: String,
        spoken: String,
        text: String? = nil,
        facts: String? = nil,
        coveredPhrases: [String] = [],
        actions: [AskAction] = [],
        root: AskCardNode? = nil,
        expands: Bool = true,
        layoutNotes: String = "",
        sources: [AskCardSource] = [],
        layoutPresetID: String = ""
    ) {
        self.title = title
        self.spoken = spoken
        self.text = text
        self.facts = facts ?? spoken
        self.coveredPhrases = coveredPhrases
        self.actions = actions
        self.root = root
        self.expands = expands
        self.layoutNotes = layoutNotes
        self.sources = sources
        self.layoutPresetID = layoutPresetID
    }
}

/// Builds, sanitizes, and wraps generative card trees.
public enum AskGeneratedCard {
    public static let maxDepth = 3
    public static let maxNodes = 24
    /// Text and detail are cut here. A model can emit a paragraph into one leaf.
    public static let maxTextLength = 500
    /// Decode refuses a payload larger than this before it walks the tree.
    public static let maxEncodedLength = 48_000
    /// Decode keeps a few levels past ``maxDepth`` so sanitize can drop them. Deeper input is cut, not recursed.
    package static let maxParseDepth = maxDepth + 5
    package static let maxParseNodes = 256

    /// Prompt block describing the card DSL for a compose session. Built from ``AskCardPrimitive``.
    public static var libraryPrompt: String {
        AskCardPrimitive.libraryPrompt
    }

    public static func composeInstructions(
        specialist: AskCardSpecialist = .default,
        allowedActions: [AskAction],
        layoutNotes: String = ""
    ) -> String {
        let allowed: String
        if allowedActions.isEmpty {
            allowed = "(none)"
        } else {
            allowed = allowedActions.map { "\($0.id)=\($0.title)" }.joined(separator: ", ")
        }
        let layout = specialist.instructions.resolved(default: libraryPrompt)
        let notes = layoutNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        var blocks = [
            "You compose an AskKit card layout.",
            layout,
            "ALLOWED\n\(allowed)"
        ]
        if !notes.isEmpty {
            blocks.append("LAYOUT\n\(notes)")
        }
        return blocks.joined(separator: "\n")
    }

    public static func composePrompt(
        facts: String,
        title: String,
        spoken: String,
        priorFacts: String = ""
    ) -> String {
        let prior = priorFacts.trimmingCharacters(in: .whitespacesAndNewlines)
        if prior.isEmpty {
            return """
            TITLE
            \(title)

            SPOKEN
            \(spoken)

            FACTS
            \(facts)
            """
        }
        return """
        TITLE
        \(title)

        SPOKEN
        \(spoken)

        PRIOR FACTS
        \(prior)

        FACTS
        \(facts)
        """
    }

    /// Title / value / detail fact card as a DSL tree. Same shape as ``AskAppleFactCard``.
    public static func factTree(title: String, value: String, detail: String) -> AskCardNode {
        var headlineChildren: [AskCardNode] = [
            AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: value)
        ]
        let badge = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !badge.isEmpty {
            headlineChildren.append(AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: badge))
        }
        var children: [AskCardNode] = [
            AskCardNode(kind: AskCardNodeKind.hstack.rawValue, children: headlineChildren)
        ]
        let secondary = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondary.isEmpty {
            children.append(AskCardNode(kind: AskCardNodeKind.text.rawValue, text: secondary))
        }
        return AskCardNode(kind: AskCardNodeKind.vstack.rawValue, children: children)
    }

    /// Falls back when the model fails or returns an empty tree.
    public static func fallbackTree(title: String, facts: String, spoken: String) -> AskCardNode {
        let lines = facts
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let value = lines.first
            ?? spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = lines.dropFirst().joined(separator: "\n")
        return factTree(
            title: title,
            value: value.isEmpty ? "Nothing to show." : value,
            detail: detail
        )
    }

    /// Drops unknown kinds, caps depth and node count, and keeps only allowed actions.
    public static func sanitize(_ root: AskCardNode, allowedActionIDs: Set<String> = []) -> AskCardNode? {
        var count = 0
        var symbolCount = 0
        var plateCount = 0
        guard let node = sanitize(
            root,
            depth: 0,
            count: &count,
            symbolCount: &symbolCount,
            plateCount: &plateCount,
            allowedActionIDs: allowedActionIDs
        ) else {
            return nil
        }
        return node
    }

    /// Action ids referenced by `action` nodes, in tree order, matched to allowed actions.
    public static func actions(in root: AskCardNode, allowed: [AskAction]) -> [AskAction] {
        let byID = Dictionary(uniqueKeysWithValues: allowed.map { ($0.id.lowercased(), $0) })
        var seen = Set<String>()
        var matched: [AskAction] = []
        walk(root) { node in
            guard AskCardNodeKind.parse(node.kind) == .action else { return }
            let id = node.actionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, let action = byID[id.lowercased()], !seen.contains(action.id.lowercased()) else {
                return
            }
            seen.insert(action.id.lowercased())
            if node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matched.append(action)
            } else {
                matched.append(AskAction(id: action.id, title: node.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return matched
    }

    /// Indented kind lines for a tree, so a toolkit can show how the card was built.
    public static func outline(_ root: AskCardNode) -> String {
        outlineLines(root, depth: 0).joined(separator: "\n")
    }

    /// Plain text for Copy / Share.
    public static func shareText(in root: AskCardNode) -> String {
        var lines: [String] = []
        walk(root) { node in
            guard let kind = AskCardNodeKind.parse(node.kind) else { return }
            switch kind {
            case .text, .stat, .badge, .quote, .eyebrow:
                let line = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { lines.append(line) }
                let detail = node.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if kind == .stat, !detail.isEmpty { lines.append(detail) }
            case .figure:
                let value = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let caption = node.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if !caption.isEmpty, !value.isEmpty {
                    lines.append("\(caption): \(value)")
                } else if !value.isEmpty {
                    lines.append(value)
                }
            case .row:
                let label = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = node.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, !value.isEmpty {
                    lines.append("\(label): \(value)")
                } else if !label.isEmpty {
                    lines.append(label)
                } else if !value.isEmpty {
                    lines.append(value)
                }
            case .action:
                let title = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { lines.append(title) }
            case .plate, .symbol, .vstack, .hstack, .divider, .spacer:
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// "Source: …" for the footer and for Copy / Share. Links are included when `includingLinks` is true.
    public static func sourceLine(_ sources: [AskCardSource], includingLinks: Bool = true) -> String {
        let parts = sources.map { source -> String in
            let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard includingLinks, let url = source.url else { return name }
            return "\(name) (\(url.absoluteString))"
        }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }
        return "Source: \(parts.joined(separator: ", "))"
    }

    /// Sources in tree order, first occurrence of each id, capped at ``AskCardSource/footerLimit``.
    /// Each node's list is sanitized again so a link that is not http or https cannot reach the footer.
    public static func sources(in root: AskCardNode) -> [AskCardSource] {
        var seen = Set<String>()
        var found: [AskCardSource] = []
        walk(root) { node in
            for source in AskCardSource.sanitized(node.sources) where seen.insert(source.id).inserted {
                found.append(source)
            }
        }
        return Array(found.prefix(AskCardSource.footerLimit))
    }

    public static func encode(_ root: AskCardNode) -> String {
        guard let data = try? JSONEncoder().encode(root),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    public static func decode(_ json: String) -> AskCardNode? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxEncodedLength else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        // A hand walk, not JSONDecoder. Missing fields become empty, and a deep chain stops at maxParseDepth
        // instead of recursing for every wrapper a saved transcript might contain.
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var budget = maxParseNodes
        return node(parsing: object, depth: 0, budget: &budget)
    }

    /// Wraps a tree in ``AskIntentCard``. Action nodes become the card button; they are not drawn inside the view.
    @MainActor
    public static func card(
        title: String,
        spoken: String,
        text: String? = nil,
        coveredPhrases: [String] = [],
        facts: String? = nil,
        allowedActions: [AskAction] = [],
        root: AskCardNode,
        expands: Bool = true,
        sources: [AskCardSource] = []
    ) -> AskIntentCard {
        let allowedIDs = Set(allowedActions.map { $0.id.lowercased() })
        let laidOut = sanitize(root, allowedActionIDs: allowedIDs)
            ?? fallbackTree(title: title, facts: facts ?? spoken, spoken: spoken)
        let tree = attaching(sources, to: laidOut)
        let matched = actions(in: tree, allowed: allowedActions)
        let display = strippingActions(tree)
        var card = AskIntentCard(
            title: title,
            spoken: spoken,
            text: text,
            coveredPhrases: coveredPhrases,
            action: matched.first ?? allowedActions.first,
            facts: facts,
            generatedRoot: tree,
            content: .builtIn(.generated(root: display, title: title))
        )
        card.shareText = {
            let fromTree = shareText(in: display)
            let body = fromTree.isEmpty
                ? AskCardShareText.make(title: title, spoken: spoken)
                : fromTree
            let attribution = sourceLine(AskGeneratedCard.sources(in: display))
            guard !attribution.isEmpty else { return body }
            if body.isEmpty { return attribution }
            return "\(body)\n\(attribution)"
        }()
        card.expands = expands
        return card
    }

    /// Builds a card from a blueprint. Uses `root` when present; otherwise `composed`, then the fact fallback.
    @MainActor
    public static func card(
        from blueprint: AskGeneratedBlueprint,
        composed: AskCardNode? = nil
    ) -> AskIntentCard {
        let allowedIDs = Set(blueprint.actions.map { $0.id.lowercased() })
        let chosen = blueprint.root.flatMap { sanitize($0, allowedActionIDs: allowedIDs) }
            ?? composed.flatMap { sanitize($0, allowedActionIDs: allowedIDs) }
            ?? fallbackTree(title: blueprint.title, facts: blueprint.facts, spoken: blueprint.spoken)
        return card(
            title: blueprint.title,
            spoken: blueprint.spoken,
            text: blueprint.text,
            coveredPhrases: blueprint.coveredPhrases,
            facts: blueprint.facts,
            allowedActions: blueprint.actions,
            root: chosen,
            expands: blueprint.expands,
            sources: blueprint.sources
        )
    }

    /// Keeps sources already on the tree, then adds blueprint sources that are not already there.
    static func attaching(_ sources: [AskCardSource], to root: AskCardNode) -> AskCardNode {
        let extra = AskCardSource.sanitized(sources)
        guard !extra.isEmpty else { return root }
        var copy = root
        var combined = AskCardSource.sanitized(copy.sources)
        var seen = Set(combined.map(\.id))
        for source in extra where seen.insert(source.id).inserted {
            combined.append(source)
        }
        copy.sources = Array(combined.prefix(AskCardSource.maximum))
        return copy
    }

    private static func sanitize(
        _ node: AskCardNode,
        depth: Int,
        count: inout Int,
        symbolCount: inout Int,
        plateCount: inout Int,
        allowedActionIDs: Set<String>
    ) -> AskCardNode? {
        guard depth <= maxDepth, count < maxNodes else { return nil }
        guard let kind = AskCardNodeKind.parse(node.kind) else { return nil }
        let rule = AskCardPrimitive.definition(for: kind)
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionID = node.actionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.requiresAllowedAction {
            guard !actionID.isEmpty, allowedActionIDs.contains(actionID.lowercased()) else { return nil }
        }
        if let image = rule.image {
            let used = image.slot == .symbol ? symbolCount : plateCount
            guard used < image.maximum, AskCardSymbol.systemName(for: text) != nil else { return nil }
            if image.slot == .symbol {
                symbolCount += 1
            } else {
                plateCount += 1
            }
        }
        // A blank leaf still spends a slot. Rolling the count back would keep more nodes than before.
        count += 1
        var copy = node
        copy.kind = kind.rawValue
        // The catalog decides which fields survive. Clamping is the length and control-character cap.
        copy.text = rule.text.stored(clamped(node.text))
        copy.detail = rule.detail.stored(clamped(node.detail))
        copy.actionID = rule.actionID.stored(actionID)
        copy.sources = AskCardSource.sanitized(node.sources)
        switch rule.children {
        case .required:
            copy.children = node.children.compactMap {
                sanitize(
                    $0,
                    depth: depth + 1,
                    count: &count,
                    symbolCount: &symbolCount,
                    plateCount: &plateCount,
                    allowedActionIDs: allowedActionIDs
                )
            }
            if copy.children.isEmpty { return nil }
        case .forbidden:
            copy.children = []
        }
        if rule.requiresTextOrDetail {
            if copy.text.isEmpty, copy.detail.isEmpty { return nil }
        } else if rule.text == .required, copy.text.isEmpty {
            return nil
        }
        return copy
    }

    private static func strippingActions(_ node: AskCardNode) -> AskCardNode {
        guard let kind = AskCardNodeKind.parse(node.kind) else { return node }
        var copy = node
        if kind == .vstack || kind == .hstack {
            copy.children = node.children.compactMap { child -> AskCardNode? in
                if AskCardNodeKind.parse(child.kind) == .action { return nil }
                return strippingActions(child)
            }
            if copy.children.isEmpty {
                // A stack of only actions used to become a stat of one space, which read as a blank value.
                return AskCardNode(kind: AskCardNodeKind.spacer.rawValue, sources: copy.sources)
            }
        }
        return copy
    }

    private static func outlineLines(_ node: AskCardNode, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        let kind = AskCardNodeKind.parse(node.kind)?.rawValue ?? node.kind
        var label = kind
        let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = node.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { label += " · \(text)" }
        if !detail.isEmpty { label += " · \(detail)" }
        if AskCardNodeKind.parse(node.kind) == .action {
            let id = node.actionID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { label += " · \(id)" }
        }
        var lines = ["\(indent)\(label)"]
        for source in node.sources {
            let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            lines.append("\(indent)  source · \(name)")
        }
        for child in node.children {
            lines.append(contentsOf: outlineLines(child, depth: depth + 1))
        }
        return lines
    }

    /// Static layouts for the Cards gallery. The toolkit scenarios describe the same shapes in words.
    package static let gallerySamples: [(title: String, root: AskCardNode)] = [
        ("Next drive", nextDriveSample),
        ("Agenda", agendaSample),
        ("Forecast", forecastSample),
        ("Steps", stepsSample),
        ("Reminders", remindersSample),
        ("Now playing", nowPlayingSample),
        ("Note", noteSample)
    ]

    static let nextDriveSample = AskCardNode(
        kind: AskCardNodeKind.vstack.rawValue,
        sources: [AskCardSource(name: "Calendar")],
        children: [
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    plate("car.fill"),
                    AskCardNode(
                        kind: AskCardNodeKind.vstack.rawValue,
                        children: [
                            eyebrow("Next drive"),
                            AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: "5 p.m."),
                            AskCardNode(kind: AskCardNodeKind.text.rawValue, text: "From the calendar"),
                            AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: "Trip")
                        ]
                    )
                ]
            ),
            AskCardNode(kind: AskCardNodeKind.row.rawValue, text: "Range", detail: "210 mi")
        ]
    )

    static let agendaSample = AskCardNode(
        kind: AskCardNodeKind.vstack.rawValue,
        sources: [AskCardSource(name: "Calendar")],
        children: [
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    plate("calendar"),
                    AskCardNode(
                        kind: AskCardNodeKind.vstack.rawValue,
                        children: [
                            eyebrow("Friday"),
                            AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: "27"),
                            AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: "Calendar")
                        ]
                    )
                ]
            ),
            event("Kick-off", "11:00 AM"),
            event("Lunch", "12:00 PM"),
            event("Pack", "1:00 PM")
        ]
    )

    static let forecastSample = AskCardNode(
        kind: AskCardNodeKind.vstack.rawValue,
        sources: [AskCardSource(name: "Weather", url: URL(string: "https://weather.example/today"))],
        children: [
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    symbol("cloud.sun.fill"),
                    AskCardNode(
                        kind: AskCardNodeKind.vstack.rawValue,
                        children: [
                            eyebrow("Partly cloudy"),
                            AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: "72°")
                        ]
                    ),
                    AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: "Weather")
                ]
            ),
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    AskCardNode(kind: AskCardNodeKind.figure.rawValue, text: "78°", detail: "High"),
                    AskCardNode(kind: AskCardNodeKind.figure.rawValue, text: "61°", detail: "Low")
                ]
            ),
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    hour("sun.max.fill", "70°", "9 AM"),
                    hour("sun.max.fill", "74°", "12 PM"),
                    hour("cloud.sun.fill", "76°", "3 PM"),
                    hour("moon.stars.fill", "71°", "6 PM")
                ]
            )
        ]
    )

    static let stepsSample = AskCardNode(
        kind: AskCardNodeKind.vstack.rawValue,
        sources: [AskCardSource(name: "Health")],
        children: [
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    plate("figure.walk"),
                    AskCardNode(
                        kind: AskCardNodeKind.vstack.rawValue,
                        children: [
                            eyebrow("Today"),
                            AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: "8,420"),
                            AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: "Steps")
                        ]
                    )
                ]
            ),
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    hour("figure.walk", "3.2 mi", "Distance"),
                    hour("figure.stairs", "12", "Flights"),
                    hour("flame.fill", "24 min", "Exercise")
                ]
            )
        ]
    )

    static let remindersSample = AskCardNode(
        kind: AskCardNodeKind.vstack.rawValue,
        children: [
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    plate("checklist"),
                    AskCardNode(
                        kind: AskCardNodeKind.vstack.rawValue,
                        children: [
                            eyebrow("Open"),
                            AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: "3"),
                            AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: "Reminders")
                        ]
                    )
                ]
            ),
            event("Buy milk", "Today", mark: "circle"),
            event("Call the shop", "Tomorrow", mark: "circle"),
            event("Pack the bag", "Friday", mark: "checkmark.circle")
        ]
    )

    static let nowPlayingSample = AskCardNode(
        kind: AskCardNodeKind.hstack.rawValue,
        children: [
            plate("music.note"),
            AskCardNode(
                kind: AskCardNodeKind.vstack.rawValue,
                children: [
                    eyebrow("Now playing"),
                    AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: "Anti-Hero"),
                    AskCardNode(kind: AskCardNodeKind.text.rawValue, text: "Taylor Swift"),
                    AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: "Now playing")
                ]
            )
        ]
    )

    static let noteSample = AskCardNode(
        kind: AskCardNodeKind.vstack.rawValue,
        children: [
            AskCardNode(
                kind: AskCardNodeKind.hstack.rawValue,
                children: [
                    plate("moon.stars.fill"),
                    AskCardNode(kind: AskCardNodeKind.badge.rawValue, text: "Note")
                ]
            ),
            AskCardNode(
                kind: AskCardNodeKind.quote.rawValue,
                text: "I give myself permission to do what is right for me."
            )
        ]
    )

    private static func plate(_ name: String) -> AskCardNode {
        AskCardNode(kind: AskCardNodeKind.plate.rawValue, text: name)
    }

    private static func eyebrow(_ text: String) -> AskCardNode {
        AskCardNode(kind: AskCardNodeKind.eyebrow.rawValue, text: text)
    }

    private static func symbol(_ name: String, mini: Bool = false) -> AskCardNode {
        AskCardNode(kind: AskCardNodeKind.symbol.rawValue, text: name, detail: mini ? "mini" : "")
    }

    private static func hour(_ name: String, _ value: String, _ caption: String) -> AskCardNode {
        AskCardNode(
            kind: AskCardNodeKind.vstack.rawValue,
            children: [
                symbol(name, mini: true),
                AskCardNode(kind: AskCardNodeKind.figure.rawValue, text: value, detail: caption)
            ]
        )
    }

    private static func event(_ label: String, _ value: String, mark: String = "clock.fill") -> AskCardNode {
        AskCardNode(
            kind: AskCardNodeKind.hstack.rawValue,
            children: [
                symbol(mark, mini: true),
                AskCardNode(kind: AskCardNodeKind.row.rawValue, text: label, detail: value)
            ]
        )
    }

    /// Trims, drops control characters and bidi overrides, then caps the length.
    /// Newlines stay. Emoji joiners stay, so a glyph is not split.
    static func clamped(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var scalars = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars where isKeptScalar(scalar) {
            scalars.append(scalar)
        }
        let text = String(scalars)
        guard text.count > maxTextLength else { return text }
        return String(text.prefix(maxTextLength))
    }

    private static func isKeptScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\n" || scalar == "\t" { return true }
        if CharacterSet.controlCharacters.contains(scalar) { return false }
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069:
            return false
        default:
            return true
        }
    }

    private static func node(parsing object: Any, depth: Int, budget: inout Int) -> AskCardNode? {
        guard depth <= maxParseDepth, budget > 0 else { return nil }
        guard let dictionary = object as? [String: Any] else { return nil }
        budget -= 1
        func field(_ key: String) -> String {
            dictionary[key] as? String ?? ""
        }
        var children: [AskCardNode] = []
        if depth < maxParseDepth, let rawChildren = dictionary["children"] as? [Any] {
            for child in rawChildren {
                guard budget > 0 else { break }
                if let parsed = node(parsing: child, depth: depth + 1, budget: &budget) {
                    children.append(parsed)
                }
            }
        }
        return AskCardNode(
            kind: field("kind"),
            text: field("text"),
            detail: field("detail"),
            actionID: field("actionID"),
            children: children
        )
    }

    private static func walk(_ node: AskCardNode, visit: (AskCardNode) -> Void) {
        visit(node)
        for child in node.children {
            walk(child, visit: visit)
        }
    }
}

/// Spoken labels for a generated card. The renderer uses these so VoiceOver hears the value and its caption together.
public enum AskGeneratedCardAccessibility {
    public static func stat(text: String, detail: String) -> String {
        joined(text, detail, separator: ", ")
    }

    public static func figure(text: String, detail: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if caption.isEmpty { return value }
        if value.isEmpty { return caption }
        return "\(caption): \(value)"
    }

    public static func row(text: String, detail: String) -> String {
        joined(text, detail, separator: ", ")
    }

    /// Badge text when the tree has one. Otherwise the card title, or "Card".
    public static func badge(_ text: String, title: String) -> String {
        let badge = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !badge.isEmpty { return badge }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Card" : name
    }

    /// The button under the card. An empty title still has a name.
    public static func action(_ title: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Action" : name
    }

    private static func joined(_ text: String, _ detail: String, separator: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return caption }
        if caption.isEmpty { return value }
        return value + separator + caption
    }
}

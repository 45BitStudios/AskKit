import Foundation
import FoundationModels
import SwiftUI

/// One node in AskKit's card layout DSL.
/// The model emits a shallow tree of these; ``AskGeneratedCardView`` maps them to SwiftUI.
/// This is not SwiftUI source — kinds are a closed set the renderer understands.
@Generable
public struct AskCardNode: Sendable, Equatable, Codable {
    /// One of: `vstack`, `hstack`, `text`, `stat`, `badge`, `divider`, `spacer`, `row`, `action`.
    @Guide(description: "One of: vstack, hstack, text, stat, badge, divider, spacer, row, action")
    public var kind: String
    /// Primary text. Empty for pure layout nodes.
    @Guide(description: "Primary text. Empty for layout, divider, and spacer nodes.")
    public var text: String
    /// Secondary text for `stat` and `row`. Empty otherwise.
    @Guide(description: "Secondary text for stat or row. Empty otherwise.")
    public var detail: String
    /// Action id copied from ALLOWED when kind is `action`. Empty otherwise.
    @Guide(description: "Action id copied from ALLOWED when kind is action. Empty otherwise.")
    public var actionID: String
    /// Child nodes. Prefer shallow trees. Empty for leaves.
    @Guide(description: "Child nodes. Prefer at most two levels. Empty for leaves.")
    public var children: [AskCardNode]

    public init(
        kind: String,
        text: String = "",
        detail: String = "",
        actionID: String = "",
        children: [AskCardNode] = []
    ) {
        self.kind = kind
        self.text = text
        self.detail = detail
        self.actionID = actionID
        self.children = children
    }
}

/// Closed layout kinds the renderer accepts.
public enum AskCardNodeKind: String, Sendable, CaseIterable {
    case vstack
    case hstack
    case text
    case stat
    case badge
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

    public init(
        id: String = "ask.card",
        title: String = "Card layout",
        symbolName: String = "rectangle.3.group",
        workingTitle: String = "Laying out the card",
        instructions: AskGuideText = .append("")
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.workingTitle = workingTitle
        self.instructions = instructions
    }

    /// AskKit defaults with no app lines.
    public static let `default` = AskCardSpecialist()
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

    public init(
        title: String,
        spoken: String,
        text: String? = nil,
        facts: String? = nil,
        coveredPhrases: [String] = [],
        actions: [AskAction] = [],
        root: AskCardNode? = nil,
        expands: Bool = true,
        layoutNotes: String = ""
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
    }
}

/// Builds, sanitizes, and wraps generative card trees.
public enum AskGeneratedCard {
    public static let maxDepth = 3
    public static let maxNodes = 24

    /// Prompt block describing the card DSL for a compose session.
    public static var libraryPrompt: String {
        """
        CARD DSL
        Compose one root AskCardNode tree from FACTS only. Do not invent numbers or names.
        Kinds:
        - vstack / hstack: layout. Put content in children.
        - text: primary line in text.
        - stat: large value in text, optional caption in detail.
        - badge: short label in text.
        - divider / spacer: no text.
        - row: label in text, value in detail.
        - action: actionID copied from ALLOWED, title in text. At most one action.
        Rules:
        - Root is usually a vstack.
        - Prefer a shallow tree (at most two levels of children).
        - Leave unused fields empty.
        - If FACTS are thin, use one stat and one text line.
        """
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

    public static func composePrompt(facts: String, title: String, spoken: String) -> String {
        """
        TITLE
        \(title)

        SPOKEN
        \(spoken)

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
        guard let node = sanitize(root, depth: 0, count: &count, allowedActionIDs: allowedActionIDs) else {
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

    /// Plain text for Copy / Share.
    public static func shareText(in root: AskCardNode) -> String {
        var lines: [String] = []
        walk(root) { node in
            guard let kind = AskCardNodeKind.parse(node.kind) else { return }
            switch kind {
            case .text, .stat, .badge:
                let line = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { lines.append(line) }
                let detail = node.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if kind == .stat, !detail.isEmpty { lines.append(detail) }
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
            case .vstack, .hstack, .divider, .spacer:
                break
            }
        }
        return lines.joined(separator: "\n")
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
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AskCardNode.self, from: data)
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
        expands: Bool = true
    ) -> AskIntentCard {
        let allowedIDs = Set(allowedActions.map { $0.id.lowercased() })
        let tree = sanitize(root, allowedActionIDs: allowedIDs)
            ?? fallbackTree(title: title, facts: facts ?? spoken, spoken: spoken)
        let matched = actions(in: tree, allowed: allowedActions)
        let display = strippingActions(tree)
        var card = AskIntentCard(
            title: title,
            spoken: spoken,
            text: text,
            coveredPhrases: coveredPhrases,
            action: matched.first,
            facts: facts,
            generatedRoot: tree,
            view: AskGeneratedCardView(root: display, title: title)
        )
        card.shareText = {
            let fromTree = shareText(in: display)
            if fromTree.isEmpty {
                return AskCardShareText.make(title: title, spoken: spoken)
            }
            return fromTree
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
            expands: blueprint.expands
        )
    }

    private static func sanitize(
        _ node: AskCardNode,
        depth: Int,
        count: inout Int,
        allowedActionIDs: Set<String>
    ) -> AskCardNode? {
        guard depth <= maxDepth, count < maxNodes else { return nil }
        guard let kind = AskCardNodeKind.parse(node.kind) else { return nil }
        if kind == .action {
            let id = node.actionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, allowedActionIDs.contains(id.lowercased()) else { return nil }
        }
        count += 1
        var copy = node
        copy.kind = kind.rawValue
        copy.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.detail = node.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.actionID = node.actionID.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .vstack, .hstack:
            copy.children = node.children.compactMap {
                sanitize($0, depth: depth + 1, count: &count, allowedActionIDs: allowedActionIDs)
            }
            if copy.children.isEmpty { return nil }
        case .text, .stat, .badge:
            if copy.text.isEmpty { return nil }
            copy.children = []
        case .row:
            if copy.text.isEmpty, copy.detail.isEmpty { return nil }
            copy.children = []
        case .divider, .spacer:
            copy.text = ""
            copy.detail = ""
            copy.actionID = ""
            copy.children = []
        case .action:
            copy.children = []
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
                return AskCardNode(kind: AskCardNodeKind.stat.rawValue, text: " ")
            }
        }
        return copy
    }

    private static func walk(_ node: AskCardNode, visit: (AskCardNode) -> Void) {
        visit(node)
        for child in node.children {
            walk(child, visit: visit)
        }
    }
}

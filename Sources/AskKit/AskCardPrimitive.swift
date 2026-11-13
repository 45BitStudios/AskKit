import Foundation

/// How one field is kept on a sanitized node.
///
/// The trimmed string is decided before this runs. `.required` still stores the text.
/// The sanitizer drops the node afterward when that text is empty, and it does so after
/// the node has already spent a slot in the 24-node budget. That matches the previous switch.
public enum AskCardFieldUse: Sendable, Equatable {
    /// Cleared. Layout nodes and chrome that must not carry the field.
    case unused
    /// Trimmed text stays, including empty.
    case kept
    /// Trimmed text stays. An empty value drops the node.
    case required
    /// A symbol scale. Only `mini` stays. Any other detail is cleared. Casing is kept.
    case miniOrEmpty

    func stored(_ trimmed: String) -> String {
        switch self {
        case .unused:
            ""
        case .kept, .required:
            trimmed
        case .miniOrEmpty:
            trimmed.lowercased() == "mini" ? trimmed : ""
        }
    }
}

/// Whether a kind may have child nodes.
public enum AskCardChildren: Sendable, Equatable {
    /// Drop the node when no child survives sanitizing.
    case required
    /// Children are removed. Leaves never keep a nested tree.
    case forbidden
}

/// Which tree-wide image counter a kind spends, and the hard cap.
public struct AskCardImageLimit: Sendable, Equatable {
    public var slot: AskCardImageSlot
    public var maximum: Int

    public init(slot: AskCardImageSlot, maximum: Int) {
        self.slot = slot
        self.maximum = maximum
    }
}

/// The two image counters. A plate and a symbol do not share one.
public enum AskCardImageSlot: Sendable, Equatable {
    case symbol
    case plate
}

/// One card primitive: the prompt line, the fields it may carry, and the sanitizer limits.
///
/// ``AskCardNodeKind`` is the closed set. This catalog is the only place that says what a kind
/// means and which fields survive. ``AskGeneratedCard/libraryPrompt`` and the sanitizer both read it.
/// The renderer keeps its own exhaustive switch. A test fails when a kind is missing from either.
public struct AskCardPrimitive: Sendable, Equatable {
    public var kind: AskCardNodeKind
    /// Words after the kind name in the CARD DSL bullet.
    public var purpose: String
    /// Kinds that share one bullet. Nil means a line of its own.
    /// Peers must use the same purpose. The prompt names them in catalog order.
    public var promptGroup: String?
    public var text: AskCardFieldUse
    public var detail: AskCardFieldUse
    public var actionID: AskCardFieldUse
    public var children: AskCardChildren
    /// SF Symbol cap. Nil for every kind that is not a plate or a symbol.
    /// The prompt still asks for six symbols. Eight are kept so one extra mark does not blank the card.
    public var image: AskCardImageLimit?
    /// The id must be non-empty and present in the host's allowed set. Checked before the node spends a slot.
    public var requiresAllowedAction: Bool
    /// A row survives when either the title or the meta is non-empty.
    public var requiresTextOrDetail: Bool

    public static func definition(for kind: AskCardNodeKind) -> AskCardPrimitive {
        switch kind {
        case .vstack:
            AskCardPrimitive(
                kind: .vstack,
                purpose: "layout. Put content in children.",
                promptGroup: "layout",
                text: .kept,
                detail: .kept,
                actionID: .kept,
                children: .required,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .hstack:
            AskCardPrimitive(
                kind: .hstack,
                purpose: "layout. Put content in children.",
                promptGroup: "layout",
                text: .kept,
                detail: .kept,
                actionID: .kept,
                children: .required,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .text:
            AskCardPrimitive(
                kind: .text,
                purpose: "secondary line in text.",
                promptGroup: nil,
                text: .required,
                detail: .kept,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .stat:
            AskCardPrimitive(
                kind: .stat,
                purpose: "the one large value in text, optional caption in detail.",
                promptGroup: nil,
                text: .required,
                detail: .kept,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .figure:
            AskCardPrimitive(
                kind: .figure,
                purpose: "a peer value in text, short caption in detail. Use beside other figures, not as the hero.",
                promptGroup: nil,
                text: .required,
                detail: .kept,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .quote:
            AskCardPrimitive(
                kind: .quote,
                purpose: "one primary sentence in text when FACTS have no number. Larger than body text.",
                promptGroup: nil,
                text: .required,
                detail: .unused,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .eyebrow:
            AskCardPrimitive(
                kind: .eyebrow,
                purpose: "a short label above the hero, in text. Smaller than the stat.",
                promptGroup: nil,
                text: .required,
                detail: .kept,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .badge:
            AskCardPrimitive(
                kind: .badge,
                purpose: "short label in text.",
                promptGroup: nil,
                text: .required,
                detail: .kept,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .plate:
            AskCardPrimitive(
                kind: .plate,
                purpose: "one rounded image. Put an SF Symbol name in text, such as car.fill or music.note.",
                promptGroup: nil,
                text: .kept,
                detail: .unused,
                actionID: .unused,
                children: .forbidden,
                image: AskCardImageLimit(slot: .plate, maximum: 1),
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .symbol:
            AskCardPrimitive(
                kind: .symbol,
                purpose: "an SF Symbol name in text, such as cloud.sun.fill or clock. Set detail to mini beside a row or above a figure.",
                promptGroup: nil,
                text: .kept,
                detail: .miniOrEmpty,
                actionID: .unused,
                children: .forbidden,
                // Six is the prompt's request. The cap stays at eight so a slightly long tree still draws.
                image: AskCardImageLimit(slot: .symbol, maximum: 8),
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .divider:
            AskCardPrimitive(
                kind: .divider,
                purpose: "no text.",
                promptGroup: "blank",
                text: .unused,
                detail: .unused,
                actionID: .unused,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .spacer:
            AskCardPrimitive(
                kind: .spacer,
                purpose: "no text.",
                promptGroup: "blank",
                text: .unused,
                detail: .unused,
                actionID: .unused,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: false
            )
        case .row:
            AskCardPrimitive(
                kind: .row,
                purpose: "title in text, short meta in detail. For an agenda, the event title is text and the time is detail.",
                promptGroup: nil,
                text: .kept,
                detail: .kept,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: false,
                requiresTextOrDetail: true
            )
        case .action:
            AskCardPrimitive(
                kind: .action,
                purpose: "actionID copied from ALLOWED, title in text. At most one action.",
                promptGroup: nil,
                text: .kept,
                detail: .kept,
                actionID: .kept,
                children: .forbidden,
                image: nil,
                requiresAllowedAction: true,
                requiresTextOrDetail: false
            )
        }
    }

    /// One entry per ``AskCardNodeKind``, in enum order.
    public static var definitions: [AskCardPrimitive] {
        AskCardNodeKind.allCases.map { definition(for: $0) }
    }

    /// Schema line for the kind field. Lists every case, so a new kind changes this string.
    public static var draftKindGuide: String {
        "One of: " + AskCardNodeKind.allCases.map(\.rawValue).joined(separator: ", ")
    }

    public static let draftTextGuide = "Primary text. Empty for layout, divider, and spacer nodes."
    public static let draftDetailGuide = "Secondary text for stat, figure, or row. Empty otherwise."
    public static let draftActionGuide = "Action id copied from ALLOWED when kind is action. Empty otherwise."
    public static let draftChildrenGuide = "Child nodes. Prefer at most two levels. Empty for leaves."

    /// The CARD DSL block. Bullets come from each primitive. The rules are composition guidance,
    /// looser than the sanitizer on purpose: the prompt asks for six symbols and the cap is eight.
    public static var libraryPrompt: String {
        let bullets = kindBullets.joined(separator: "\n")
        let rules = compositionRules.map { "- \($0)" }.joined(separator: "\n")
        return """
        CARD DSL
        Compose one root AskCardNode tree from FACTS only. Do not invent numbers or names.
        Kinds:
        \(bullets)
        Rules:
        \(rules)
        """
    }

    /// Guidance that is not a per-kind field rule. Kept here so the prompt has one author.
    public static let compositionRules: [String] = [
        "Root is usually a vstack.",
        "Open with a plate or a hero symbol, then an eyebrow, then one stat. Put the domain in a badge.",
        "Peer numbers are figure nodes in one hstack, not more stats. A symbol with detail mini can sit above each figure.",
        "A day of events is a stat plus rows. A mini symbol can sit beside each row.",
        "A sentence with no number is a quote next to a plate.",
        "At most one plate and six symbols, taken from FACTS or a known label.",
        "Prefer a shallow tree (at most two levels of children).",
        "Leave unused fields empty.",
        "If FACTS are thin, use a plate, one stat, and one text line."
    ]

    private static var kindBullets: [String] {
        var lines: [String] = []
        var seenGroups = Set<String>()
        for item in definitions {
            if let group = item.promptGroup {
                guard seenGroups.insert(group).inserted else { continue }
                let names = definitions
                    .filter { $0.promptGroup == group }
                    .map(\.kind.rawValue)
                    .joined(separator: " / ")
                lines.append("- \(names): \(item.purpose)")
            } else {
                lines.append("- \(item.kind.rawValue): \(item.purpose)")
            }
        }
        return lines
    }
}

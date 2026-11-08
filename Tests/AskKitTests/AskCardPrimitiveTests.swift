import Foundation
import Testing
@testable import AskKit
#if !os(watchOS)
@testable import AskKitUI
#endif

@Suite("Card primitive catalog")
struct AskCardPrimitiveTests {
    @Test func everyKindHasOneDefinition() {
        let kinds = AskCardPrimitive.definitions.map(\.kind)
        #expect(kinds == Array(AskCardNodeKind.allCases))
        #expect(Set(kinds).count == AskCardNodeKind.allCases.count)
        #expect(AskCardPrimitive.definitions.allSatisfy { !$0.purpose.isEmpty })
    }

    @Test func promptGroupsStayTogetherAndShareAPurpose() {
        let items = AskCardPrimitive.definitions
        var index = 0
        while index < items.count {
            guard let group = items[index].promptGroup else {
                index += 1
                continue
            }
            var end = index
            while end < items.count, items[end].promptGroup == group {
                #expect(items[end].purpose == items[index].purpose)
                end += 1
            }
            let appearsLater = items[end...].contains { $0.promptGroup == group }
            #expect(!appearsLater)
            #expect(end > index + 1)
            index = end
        }
    }

    @Test func libraryPromptMatchesTheHandwrittenDSL() {
        #expect(AskGeneratedCard.libraryPrompt == expectedLibraryPrompt)
        for rule in AskCardPrimitive.definitions {
            #expect(AskGeneratedCard.libraryPrompt.contains(rule.purpose))
            #expect(AskGeneratedCard.libraryPrompt.contains(rule.kind.rawValue))
        }
        #expect(AskGeneratedCard.libraryPrompt.contains("At most one plate and six symbols"))
        #expect(AskCardPrimitive.definition(for: .symbol).image == AskCardImageLimit(slot: .symbol, maximum: 8))
        #expect(AskCardPrimitive.definition(for: .plate).image == AskCardImageLimit(slot: .plate, maximum: 1))
    }

    @Test func draftGuidesListEveryKindAndMatchTheSchemaLiterals() throws {
        let guide = AskCardPrimitive.draftKindGuide
        #expect(guide == "One of: " + AskCardNodeKind.allCases.map(\.rawValue).joined(separator: ", "))
        let source = try sourceText("AskGeneratedCard.swift")
        #expect(source.contains("@Guide(description: \"\(guide)\")"))
        #expect(source.contains("@Guide(description: \"\(AskCardPrimitive.draftTextGuide)\")"))
        #expect(source.contains("@Guide(description: \"\(AskCardPrimitive.draftDetailGuide)\")"))
        #expect(source.contains("@Guide(description: \"\(AskCardPrimitive.draftActionGuide)\")"))
        #expect(source.contains("@Guide(description: \"\(AskCardPrimitive.draftChildrenGuide)\")"))
    }

    #if !os(watchOS)
    @Test func everyKindHasARendererCase() throws {
        let source = try sourceText("AskGeneratedCardView.swift", in: "AskKitUI")
        for kind in AskCardNodeKind.allCases {
            #expect(AskGeneratedCardRender.draws(kind))
            #expect(source.contains("case .\(kind.rawValue):"))
        }
    }
    #endif

    @Test func sanitizerFollowsEachDefinition() throws {
        for rule in AskCardPrimitive.definitions {
            let kept = try #require(AskGeneratedCard.sanitize(valid(rule), allowedActionIDs: ["go"]))
            #expect(kept.kind == rule.kind.rawValue)
            if rule.detail == .unused {
                #expect(kept.detail.isEmpty)
            }
            if rule.text == .unused {
                #expect(kept.text.isEmpty)
            }
            if rule.actionID == .unused {
                #expect(kept.actionID.isEmpty)
            }
            if rule.children == .forbidden {
                #expect(kept.children.isEmpty)
            }
            if rule.detail == .miniOrEmpty {
                let mini = try #require(AskGeneratedCard.sanitize(
                    AskCardNode(kind: rule.kind.rawValue, text: "heart.fill", detail: "Mini")
                ))
                #expect(mini.detail == "Mini")
                let cleared = try #require(AskGeneratedCard.sanitize(
                    AskCardNode(kind: rule.kind.rawValue, text: "heart.fill", detail: "wide")
                ))
                #expect(cleared.detail.isEmpty)
            }
            if rule.text == .required {
                #expect(AskGeneratedCard.sanitize(AskCardNode(kind: rule.kind.rawValue, text: "   ")) == nil)
            }
            if rule.requiresTextOrDetail {
                #expect(AskGeneratedCard.sanitize(AskCardNode(kind: rule.kind.rawValue)) == nil)
                let meta = try #require(AskGeneratedCard.sanitize(
                    AskCardNode(kind: rule.kind.rawValue, detail: "8 a.m.")
                ))
                #expect(meta.detail == "8 a.m.")
            }
            if rule.requiresAllowedAction {
                #expect(AskGeneratedCard.sanitize(
                    AskCardNode(kind: rule.kind.rawValue, text: "Go", actionID: "missing"),
                    allowedActionIDs: ["go"]
                ) == nil)
            }
            if let image = rule.image {
                let name = image.slot == .plate ? "car.fill" : "heart.fill"
                let extra = image.maximum + 1
                let crowded = AskCardNode(
                    kind: "vstack",
                    children: (0..<extra).map { _ in
                        AskCardNode(kind: rule.kind.rawValue, text: name)
                    }
                )
                let sanitized = try #require(AskGeneratedCard.sanitize(crowded))
                #expect(sanitized.children.count == image.maximum)
            }
        }
    }

    @Test func aBlankContainerStillSpendsANodeSlot() throws {
        let texts = (0..<30).map { AskCardNode(kind: "text", text: "\($0)") }
        let root = AskCardNode(kind: "vstack", children: [AskCardNode(kind: "vstack")] + texts)
        let sanitized = try #require(AskGeneratedCard.sanitize(root))
        #expect(sanitized.children.count == 22)
        #expect(sanitized.children.map(\.text) == (0..<22).map { "\($0)" })
    }

    @Test func twoAllowedActionsBothStay() throws {
        let root = AskCardNode(
            kind: "vstack",
            children: [
                AskCardNode(kind: "action", text: "Open", actionID: "open"),
                AskCardNode(kind: "action", text: "Share", actionID: "share")
            ]
        )
        let sanitized = try #require(AskGeneratedCard.sanitize(root, allowedActionIDs: ["open", "share"]))
        #expect(sanitized.children.map(\.actionID) == ["open", "share"])
    }

    private func valid(_ rule: AskCardPrimitive) -> AskCardNode {
        switch rule.kind {
        case .vstack, .hstack:
            AskCardNode(kind: rule.kind.rawValue, children: [AskCardNode(kind: "text", text: "A")])
        case .plate:
            AskCardNode(kind: "plate", text: "car.fill", detail: "nope", actionID: "nope")
        case .symbol:
            AskCardNode(kind: "symbol", text: "heart.fill", detail: "wide", actionID: "nope")
        case .action:
            AskCardNode(kind: "action", text: "Go", actionID: "go")
        case .row:
            AskCardNode(kind: "row", text: "Title", detail: "Meta")
        case .divider, .spacer:
            AskCardNode(kind: rule.kind.rawValue, text: "nope", detail: "nope", actionID: "nope")
        default:
            AskCardNode(kind: rule.kind.rawValue, text: "A", detail: "B", actionID: "kept")
        }
    }

    private func sourceText(_ name: String, in folder: String = "AskKit") throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("Sources")
            .appendingPathComponent(folder)
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// The CARD DSL block as it read before the catalog. The generated prompt has to stay this text.
private let expectedLibraryPrompt = """
CARD DSL
Compose one root AskCardNode tree from FACTS only. Do not invent numbers or names.
Kinds:
- vstack / hstack: layout. Put content in children.
- text: secondary line in text.
- eyebrow: a short label above the hero, in text. Smaller than the stat.
- stat: the one large value in text, optional caption in detail.
- figure: a peer value in text, short caption in detail. Use beside other figures, not as the hero.
- quote: one primary sentence in text when FACTS have no number. Larger than body text.
- badge: short label in text.
- plate: one rounded image. Put an SF Symbol name in text, such as car.fill or music.note.
- symbol: an SF Symbol name in text, such as cloud.sun.fill or clock. Set detail to mini beside a row or above a figure.
- divider / spacer: no text.
- row: title in text, short meta in detail. For an agenda, the event title is text and the time is detail.
- action: actionID copied from ALLOWED, title in text. At most one action.
Rules:
- Root is usually a vstack.
- Open with a plate or a hero symbol, then an eyebrow, then one stat. Put the domain in a badge.
- Peer numbers are figure nodes in one hstack, not more stats. A symbol with detail mini can sit above each figure.
- A day of events is a stat plus rows. A mini symbol can sit beside each row.
- A sentence with no number is a quote next to a plate.
- At most one plate and six symbols, taken from FACTS or a known label.
- Prefer a shallow tree (at most two levels of children).
- Leave unused fields empty.
- If FACTS are thin, use a plate, one stat, and one text line.
"""

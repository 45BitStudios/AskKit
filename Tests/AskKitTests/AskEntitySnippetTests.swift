import Foundation
import os
import Testing
@testable import AskKit

@Suite("Entity snippet cards")
struct AskEntitySnippetTests {
    @Test func aDetailCardKeepsFieldsImageAccentAndThreeActions() {
        let snippet = AskEntitySnippet.detail(
            entityType: "PantryItem",
            entityID: "pasta",
            title: "  Pasta  ",
            subtitle: " Aisle 4 ",
            fields: [
                AskSnippetField(id: "qty", title: "On hand", value: "2 boxes", rank: .primary),
                AskSnippetField(id: "note", title: "Note", value: "Use tonight", symbolName: "note.text", rank: .secondary)
            ],
            symbolName: "fork.knife",
            imageName: "pasta",
            accent: .orange,
            actions: [.favorite(), .remind(), .open(title: "Open")]
        )
        let card = AskSnippetCard.make(from: snippet, density: .standard)

        #expect(snippet.title == "Pasta")
        #expect(snippet.subtitle == "Aisle 4")
        #expect(card.shape == .detail)
        #expect(card.density == .standard)
        #expect(card.entityType == "PantryItem")
        #expect(card.entityID == "pasta")
        #expect(card.primaryFields.map(\.id) == ["qty"])
        #expect(card.secondaryFields.map(\.value) == ["Use tonight"])
        #expect(card.showsImage)
        #expect(card.imageName == "pasta")
        #expect(card.symbolName == "fork.knife")
        #expect(card.accent == .orange)
        #expect(card.showsActions)
        #expect(card.actions.map(\.role) == [.favorite, .remind, .open])
        #expect(card.titleLineLimit == 3)
        #expect(card.bodyLineLimit == 3)
        #expect(card.actionRequests == [
            AskSnippetActionRequest(entityType: "PantryItem", entityID: "pasta", actionID: "favorite", role: .favorite),
            AskSnippetActionRequest(entityType: "PantryItem", entityID: "pasta", actionID: "remind", role: .remind),
            AskSnippetActionRequest(entityType: "PantryItem", entityID: "pasta", actionID: "open", role: .open)
        ])
        #expect(card.accessibilityText == "Pasta\nAisle 4\nOn hand 2 boxes\nNote Use tonight\nFavorite\nRemind\nOpen")
    }

    @Test func extraBlankAndDuplicateActionsAreDropped() {
        let actions = [
            AskSnippetAction(id: "  ", title: "Skip", role: .custom),
            AskSnippetAction(id: "a", title: "   ", role: .custom),
            AskSnippetAction(id: " favorite ", title: " Favorite ", role: .favorite),
            .favorite(title: "Again"),
            AskSnippetAction(id: "remind", title: "Remind", role: .remind),
            AskSnippetAction(id: "open", title: "Open", role: .open),
            AskSnippetAction(id: "fourth", title: "Extra", role: .custom)
        ]
        let snippet = AskEntitySnippet.detail(title: "Pasta", actions: actions)
        #expect(snippet.actions.map(\.id) == ["favorite", "remind", "open"])
        #expect(AskSnippetLimits.actions == 3)
    }

    @Test func makeCapsActionsThatWereAddedAfterInit() {
        var snippet = AskEntitySnippet.detail(entityID: "pasta", title: "Pasta")
        snippet.actions = (0..<4).map { AskSnippetAction(id: "a\($0)", title: "Go", role: .custom) }
        let card = AskSnippetCard.make(from: snippet, density: .standard)
        #expect(card.actions.map(\.id) == ["a0", "a1", "a2"])
    }

    @Test func aCompactDetailHidesTheImageSecondaryLinesAndButtons() {
        let snippet = AskEntitySnippet.detail(
            title: "Pasta",
            subtitle: "Aisle 4",
            fields: [
                AskSnippetField(id: "one", title: "One", value: "1", rank: .primary),
                AskSnippetField(id: "two", title: "Two", value: "2", rank: .primary),
                AskSnippetField(id: "three", title: "Three", value: "3", rank: .primary),
                AskSnippetField(id: "note", title: "Note", value: "Later", rank: .secondary)
            ],
            symbolName: "fork.knife",
            imageName: "pasta",
            actions: [.favorite()]
        )
        let card = AskSnippetCard.make(from: snippet, density: .compact)
        #expect(card.density == .compact)
        #expect(card.primaryFields.map(\.id) == ["one", "two"])
        #expect(card.secondaryFields.isEmpty)
        #expect(!card.showsImage)
        #expect(card.imageName == nil)
        #expect(card.symbolName == "fork.knife")
        #expect(!card.showsActions)
        #expect(card.actionRequests.isEmpty)
        #expect(card.titleLineLimit == 2)
        #expect(card.bodyLineLimit == 1)
        #expect(card.accessibilityText == "Pasta\nAisle 4\nOne 1\nTwo 2")
        #expect(AskSnippetLimits.compactPrimaryFields == 2)
    }

    @Test func aListCardKeepsRowsAndACompactListKeepsTwo() {
        let rows = (1...4).map { AskSnippetRow(id: "s\($0)", title: "Session \($0)", subtitle: "Room \($0)") }
        let snippet = AskEntitySnippet.list(
            entityID: "schedule",
            title: "My Schedule",
            subtitle: "Four talks",
            rows: rows,
            symbolName: "star.fill",
            accent: .pink,
            actions: [.open(id: "calendar", title: "Add to Calendar", symbolName: "calendar.badge.plus")]
        )
        let standard = AskSnippetCard.make(from: snippet, density: .standard)
        #expect(standard.rows.map(\.id) == ["s1", "s2", "s3", "s4"])
        #expect(standard.showsActions)
        #expect(standard.actions.map(\.id) == ["calendar"])
        #expect(standard.actionRequests.first?.role == .open)
        #expect(!standard.showsImage)
        #expect(standard.symbolName == "star.fill")
        #expect(standard.accent == .pink)
        #expect(standard.titleLineLimit == 2)

        let compact = AskSnippetCard.make(from: snippet, density: .compact)
        #expect(compact.rows.map(\.id) == ["s1", "s2"])
        #expect(!compact.showsActions)
        #expect(compact.subtitle == "Four talks")
        #expect(compact.titleLineLimit == 1)
        #expect(AskSnippetLimits.compactListRows == 2)
    }

    @Test func aRowDropsFieldsRowsImagesAndActions() {
        let snippet = AskEntitySnippet(
            shape: .row,
            entityID: "pasta",
            title: " Pasta ",
            subtitle: " Aisle 4 ",
            fields: [AskSnippetField(id: "qty", title: "On hand", value: "2", rank: .primary)],
            rows: [AskSnippetRow(id: "s", title: "Talk")],
            symbolName: "fork.knife",
            imageName: "pasta",
            actions: [.favorite()]
        )
        #expect(snippet.fields.isEmpty)
        #expect(snippet.rows.isEmpty)
        #expect(snippet.actions.isEmpty)
        #expect(snippet.imageName == nil)
        #expect(snippet.symbolName == "fork.knife")

        let card = AskSnippetCard.make(from: snippet, density: .standard)
        #expect(card.shape == .row)
        #expect(card.density == .compact)
        #expect(!card.showsActions)
        #expect(!card.showsImage)
        #expect(card.title == "Pasta")
        #expect(card.subtitle == "Aisle 4")
        #expect(card.titleLineLimit == 1)
        #expect(card.accessibilityText == "Pasta\nAisle 4")
    }

    @Test func eachShapeKeepsOnlyItsOwnPayload() {
        let detail = AskEntitySnippet(
            shape: .detail,
            title: "Session",
            rows: [AskSnippetRow(id: "s", title: "Talk")]
        )
        #expect(detail.rows.isEmpty)

        let list = AskEntitySnippet(
            shape: .list,
            title: "Schedule",
            fields: [AskSnippetField(id: "qty", title: "On hand", value: "2")],
            imageName: "pasta"
        )
        #expect(list.fields.isEmpty)
        #expect(list.imageName == nil)
    }

    @Test func blankFieldsRowsAndSymbolsAreDropped() {
        let snippet = AskEntitySnippet.detail(
            title: "Pasta",
            subtitle: "   ",
            fields: [
                AskSnippetField(id: "empty", title: "On hand", value: "  "),
                AskSnippetField(id: "qty", title: "On hand", value: "2"),
                AskSnippetField(id: "qty", title: "Again", value: "9")
            ],
            symbolName: "  ",
            imageName: " "
        )
        #expect(snippet.subtitle == nil)
        #expect(snippet.fields.map(\.id) == ["qty"])
        #expect(snippet.symbolName == nil)
        #expect(snippet.imageName == nil)
        let card = AskSnippetCard.make(from: snippet, density: .standard)
        #expect(!card.showsImage)
        #expect(card.accessibilityText == "Pasta\nOn hand 2")
    }

    @Test func aFieldWithNoLabelSpeaksTheValue() {
        let snippet = AskEntitySnippet.detail(
            title: "Pasta",
            fields: [AskSnippetField(id: "qty", title: " ", value: "2 boxes")]
        )
        let card = AskSnippetCard.make(from: snippet, density: .standard)
        #expect(card.accessibilityText == "Pasta\n2 boxes")
    }

    @Test func stampFillsBlankIdentifiersAndKeepsOnesTheAppSet() {
        let blank = AskEntitySnippet.detail(title: "Pasta")
        let filled = blank.stamped(entityType: " App.PantryItem ", entityID: " pasta ")
        #expect(filled.entityType == "App.PantryItem")
        #expect(filled.entityID == "pasta")

        let set = AskEntitySnippet.detail(entityType: "Custom", entityID: "42", title: "Pasta")
        let kept = set.stamped(entityType: "Other", entityID: "99")
        #expect(kept.entityType == "Custom")
        #expect(kept.entityID == "42")

        let stillBlank = blank.stamped(entityType: "  ", entityID: " ")
        #expect(stillBlank.entityType.isEmpty)
        #expect(stillBlank.entityID.isEmpty)
    }

    @Test func familiesMapOntoDensity() {
        #expect(AskSnippetFamily(isStandardFamily: true) == .standard)
        #expect(AskSnippetFamily.standard.density == .standard)
        #expect(AskSnippetFamily(isStandardFamily: false) == .other)
        #expect(AskSnippetFamily.other.density == .compact)
    }

    @Test func accentsClampAndUnknownNamesFallBackToIndigo() {
        #expect(AskSnippetAccent.named(" Orange ") == .orange)
        #expect(AskSnippetAccent.named("nope") == .indigo)
        #expect(AskSnippetAccent.indigo.name == "indigo")
        let custom = AskSnippetAccent(red: 0.2, green: 0.3, blue: 0.4, opacity: 0.5)
        #expect(custom.name == "custom")
        let clamped = AskSnippetAccent(red: 2, green: -1, blue: .nan, opacity: .infinity)
        #expect(clamped.red == 1)
        #expect(clamped.green == 0)
        #expect(clamped.blue == 0)
        #expect(clamped.opacity == 1)
    }

    @Test func convenienceActionsUseTheRoleSymbol() {
        #expect(AskSnippetAction.favorite().role == .favorite)
        #expect(AskSnippetAction.remind().resolvedSymbolName == "bell")
        #expect(AskSnippetAction.open(title: "Open").id == "open")
        let bare = AskSnippetAction(id: "go", title: "Go", symbolName: "  ", role: .custom)
        #expect(bare.resolvedSymbolName == "circle")
        #expect(AskSnippetActionRole(intentValue: "remind") == .remind)
        #expect(AskSnippetActionRole(intentValue: "nope") == .custom)
        let request = AskSnippetActionRequest(entityType: " T ", entityID: " 1 ", actionID: " open ", intentRole: "open")
        #expect(request == AskSnippetActionRequest(entityType: "T", entityID: "1", actionID: "open", role: .open))
    }

    @Test func theCenterRunsAndReplacesAHandler() async throws {
        let center = AskSnippetActionCenter()
        let seen = OSAllocatedUnfairLock(initialState: [String]())
        center.register(entityType: " PantryItem ") { request in
            seen.withLock { $0.append(request.actionID) }
        }
        let favorite = AskSnippetActionRequest(entityType: "PantryItem", entityID: "pasta", actionID: "favorite", role: .favorite)
        try await center.perform(favorite)
        center.register(entityType: "PantryItem") { request in
            seen.withLock { $0.append("next-\(request.role.rawValue)") }
        }
        try await center.perform(favorite)
        #expect(seen.withLock { $0 } == ["favorite", "next-favorite"])
    }

    @Test func aMissingHandlerThrowsAndABlankTypeIsNotStored() async {
        let center = AskSnippetActionCenter()
        center.register(entityType: " ") { _ in }
        let missing = AskSnippetActionRequest(entityType: "Missing", entityID: "1", actionID: "open", role: .open)
        await #expect(throws: AskSnippetActionError(entityType: "Missing", actionID: "open")) {
            try await center.perform(missing)
        }
        center.register(entityType: "PantryItem") { _ in }
        center.remove(entityType: " PantryItem ")
        await #expect(throws: AskSnippetActionError(entityType: "PantryItem", actionID: "favorite")) {
            try await center.perform(
                AskSnippetActionRequest(entityType: "PantryItem", entityID: "pasta", actionID: "favorite", role: .favorite)
            )
        }
    }

    @Test func theCenterForwardsTheHandlerError() async {
        let center = AskSnippetActionCenter()
        center.register(entityType: "PantryItem") { _ in
            throw SampleSnippetFailure.failed
        }
        await #expect(throws: SampleSnippetFailure.failed) {
            try await center.perform(
                AskSnippetActionRequest(entityType: "PantryItem", entityID: "pasta", actionID: "remind", role: .remind)
            )
        }
        center.removeAll()
        await #expect(throws: AskSnippetActionError.self) {
            try await center.perform(
                AskSnippetActionRequest(entityType: "PantryItem", entityID: "pasta", actionID: "remind", role: .remind)
            )
        }
    }
}

private enum SampleSnippetFailure: Error, Equatable {
    case failed
}

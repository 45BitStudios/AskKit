#if ASK_ENTITY_SNIPPETS && canImport(AppIntents) && !os(watchOS)
import AppIntents
import AskKit
import Testing
@testable import AskKitIntents

/// Compiles only where `SnippetRepresentableEntity` exists.
/// The conformance supplies the descriptor and inherits `snippet` from `AskSnippetEntity`.
@available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *)
public struct FixturePantryEntity: AppEntity, AskSnippetEntity, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pantry Item")
    public static let defaultQuery = FixturePantryQuery()

    public var id: String
    public var name: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public static func askEntitySnippet(for entity: Self) -> AskEntitySnippet {
        .detail(title: entity.name, subtitle: "On the shelf", symbolName: "fork.knife", actions: [.favorite()])
    }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *)
public struct FixturePantryQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [FixturePantryEntity.ID]) async throws -> [FixturePantryEntity] {
        identifiers.map { FixturePantryEntity(id: $0, name: $0) }
    }

    public func suggestedEntities() async throws -> [FixturePantryEntity] {
        []
    }
}

@Suite("Entity snippet bridge")
struct AskEntitySnippetBridgeTests {
    @Test func theBridgeStampsTheTypeNameAndIdentifier() {
        guard #available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *) else {
            return
        }
        verifyTheBridgeStampsTheTypeNameAndIdentifier()
    }

    /// Swift Testing rejects `@available` on `@Suite` and `@Test`. The 27.3 types stay on the fixture.
    @available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *)
    private func verifyTheBridgeStampsTheTypeNameAndIdentifier() {
        let entity = FixturePantryEntity(id: "pasta", name: "Pasta")
        let standard = FixturePantryEntity.card(for: entity, isStandardFamily: true)
        #expect(standard.entityID == "pasta")
        #expect(standard.entityType == FixturePantryEntity.askSnippetTypeName)
        #expect(standard.title == "Pasta")
        #expect(standard.subtitle == "On the shelf")
        #expect(standard.symbolName == "fork.knife")
        #expect(standard.showsActions)
        #expect(standard.density == .standard)

        let compact = FixturePantryEntity.card(for: entity, isStandardFamily: false)
        #expect(compact.density == .compact)
        #expect(!compact.showsActions)

        let preset = AskEntitySnippet.detail(entityType: "Shelf", entityID: "kept", title: entity.name)
        let card = AskSnippetCard.make(
            from: preset.stamped(
                entityType: FixturePantryEntity.askSnippetTypeName,
                entityID: String(describing: entity.id)
            ),
            density: .standard
        )
        #expect(card.entityType == "Shelf")
        #expect(card.entityID == "kept")
    }
}
#endif

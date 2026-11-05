#if ASK_ENTITY_SNIPPETS && canImport(AppIntents) && !os(watchOS)
import AppIntents
import AskKit
import SwiftUI

// Entity cards (iOS 27.3 / macOS 27.3 / Mac Catalyst 27.3 / tvOS 27.3 / visionOS 27.3).
// Public DocC:
//   SnippetRepresentableEntity.snippet returns some EntitySnippetContent<Self>
//   CardSnippet(supportedFamilies:) archives the view in the closure
// The 27.3 symbol graph requires:
//   associatedtype Body: EntitySnippetContent where Self == Self.Body.Entity
// `some EntitySnippetContent` does not fix Body.Entity to Self, so the witness
// is `some EntitySnippetContent<Self>`.
// `CardSnippetFamily` is a struct. Compare it with `==`.
// The closure only reads the entity. Buttons call AskSnippetButtonIntent or
// AskSnippetOpenIntent, and the system archives the card again after they return.
// watchOS does not compile this file. AskKitUI is already left out of that build.
// Xcode 27.2 does not have these symbols. The file stays behind ASK_ENTITY_SNIPPETS.

/// An entity that shows an `AskEntitySnippet` as its Siri card.
///
/// The app supplies the descriptor. AskKit builds the `CardSnippet`.
/// The mapping runs inside the snippet closure, so it may only read values already on the entity.
@available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *)
public protocol AskSnippetEntity: AppEntity, SnippetRepresentableEntity {
    /// The card for this value.
    ///
    /// Leave `entityType` empty to use `askSnippetTypeName`.
    /// Leave `entityID` empty to use `String(describing:)` of the entity id, which matches `String`, `Int`, and `UUID`.
    /// Set `entityID` when a custom identifier's description is not the id the handler should see.
    static func askEntitySnippet(for entity: Self) -> AskEntitySnippet
}

@available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *)
extension AskSnippetEntity {
    /// `String(reflecting:)` for this entity. `register(_:handler:)` uses the same string.
    public static var askSnippetTypeName: String {
        String(reflecting: Self.self)
    }

    public static var snippet: some EntitySnippetContent<Self> {
        CardSnippet(supportedFamilies: [.standard]) { entity, context in
            AskEntitySnippetCard(card: Self.card(for: entity, isStandardFamily: context.family == .standard))
        }
    }

    static func card(for entity: Self, isStandardFamily: Bool) -> AskSnippetCard {
        let snippet = Self.askEntitySnippet(for: entity).stamped(
            entityType: Self.askSnippetTypeName,
            entityID: String(describing: entity.id)
        )
        let density = AskSnippetFamily(isStandardFamily: isStandardFamily).density
        return AskSnippetCard.make(from: snippet, density: density)
    }
}

@available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *)
extension AskSnippetActionCenter {
    /// Registers the handler under `askSnippetTypeName`.
    public func register<Entity: AskSnippetEntity>(
        _ type: Entity.Type,
        handler: @escaping @Sendable (AskSnippetActionRequest) async throws -> Void
    ) {
        register(entityType: type.askSnippetTypeName, handler: handler)
    }
}
#endif

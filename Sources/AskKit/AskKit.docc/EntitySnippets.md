# Entity snippets

Map an app entity to an ``AskEntitySnippet`` and Siri shows a card.

## Overview

An app that already has an `AppEntity` can show that entity as a Siri card. The app describes the card. AskKit turns the description into the system card. The app does not write a `CardSnippet` closure.

The description is an ``AskEntitySnippet``. ``AskSnippetCard/make(from:density:)`` maps it onto the card that is drawn. The 27.3 snippet API archives that card. The mapping reads values that are already on the entity. A button runs later.

Three shapes cover the cards a conference-style app needs:

- A detail card has a title, a subtitle, primary and secondary fields, an optional symbol or image, an accent, and up to three actions.
- A list card has a heading and rows. A saved schedule is a list.
- A row is one compact line. It does not show actions.

``AskSnippetLimits/actions`` is 3. A fourth action, a blank title, and a repeated id are dropped. A compact card keeps ``AskSnippetLimits/compactPrimaryFields`` primary fields or ``AskSnippetLimits/compactListRows`` rows, and it hides images, secondary lines, and buttons.

## Define the entity

Conform to `AskSnippetEntity` in AskKitIntents. That conformance is `SnippetRepresentableEntity`. Leave `entityType` and `entityID` empty unless the identifier needs a custom string.

```swift
import AppIntents
import AskKit
import AskKitIntents

@available(iOS 27.3, macCatalyst 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *)
extension PantryItemEntity: AskSnippetEntity {
    public static func askEntitySnippet(for entity: Self) -> AskEntitySnippet {
        .detail(
            title: entity.name,
            subtitle: entity.aisle,
            fields: [
                AskSnippetField(id: "qty", title: "On hand", value: entity.quantity, rank: .primary),
                AskSnippetField(id: "note", title: "Note", value: entity.note, rank: .secondary)
            ],
            symbolName: "fork.knife",
            imageName: entity.photoName,
            accent: .orange,
            actions: [.favorite(), .remind(), .open(title: "Open")]
        )
    }
}
```

`String`, `Int`, and `UUID` identifiers are filled in with `String(describing:)`. Set `entityID` when a custom identifier's description is not the value the handler should receive. The type name is `String(reflecting:)` of the entity. `register(_:)` uses that same string.

A list and a row use the other factories.

```swift
AskEntitySnippet.list(
    title: "My Schedule",
    subtitle: titles.isEmpty ? "Nothing saved yet." : "Saved sessions",
    rows: titles.map { AskSnippetRow(id: $0, title: $0) },
    symbolName: "star.fill",
    actions: [.open(id: "calendar", title: "Add to Calendar", symbolName: "calendar.badge.plus")]
)

AskEntitySnippet.row(title: item.name, subtitle: item.aisle, symbolName: "fork.knife")
```

## Handle the button

Favorite and remind run `AskSnippetButtonIntent`. Open runs `AskSnippetOpenIntent` and brings the app forward. The intents are not listed in Shortcuts and they do not speak a second dialog. Register one handler in `App.init`.

```swift
if #available(iOS 27.3, macOS 27.3, tvOS 27.3, visionOS 27.3, *) {
    AskSnippetActionCenter.shared.register(PantryItemEntity.self) { request in
        switch request.role {
        case .favorite:
            await PantryStore.shared.toggleFavorite(id: request.entityID)
        case .remind:
            await PantryStore.shared.remind(id: request.entityID)
        case .open:
            await PantryStore.shared.show(id: request.entityID)
        case .custom:
            break
        }
    }
}
```

``AskSnippetActionRequest`` carries the entity type, the entity id, the action id, and the ``AskSnippetActionRole``. An unknown role string is `.custom`.

## Availability

The descriptor, the mapping, and the action center compile on every platform AskKit supports, including watchOS and tvOS. The `CardSnippet` bridge compiles on iOS, macOS, Mac Catalyst, tvOS, and visionOS when the 27.3 SDK is present. watchOS does not compile the card view. AskKitUI is already left out of the watchOS build, and this card follows that. The conformance is available on iOS 27.3, macOS 27.3, Mac Catalyst 27.3, tvOS 27.3, and visionOS 27.3. An older system keeps the entity's display representation.

`CardSnippetFamily` is a struct. The bridge compares it with `==`. `.standard` is the full card. Any other family is compact.

The witness returns `some EntitySnippetContent<Self>`. A return type of `some EntitySnippetContent` does not fix the snippet's entity to `Self`.

## Topics

- ``AskEntitySnippet``
- ``AskSnippetCard``
- ``AskSnippetAction``
- ``AskSnippetActionCenter``
- ``AskSnippetAccent``

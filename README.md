# AskKit

AskKit is an on-device receptionist for iOS 27. An app registers domains and skills. A person asks an open question. AskKit picks one skill and either replies, or shows a card from an intent the app already shipped.

The package does not know about a particular app's screens, accounts, or catalogs. United's Ask United app is not this package.

## Turn

1. A chip tap runs that skill. No model.
2. "what about", "how about", and "also" are stitched onto the previous user question from the saved thread.
3. An optional fast path can pick a skill before the model runs.
4. Hop 1 is a new `LanguageModelSession` with a routing profile, zero tools, and tool calling disallowed. It picks one domain.
5. Hop 2 is another new zero-tool session. It picks one skill in that domain.
6. If a required slot is missing, one new session carries that domain's tools. The cap is 5. More than five is ignored and the skill still runs with the slots already in hand.
7. A routing session is never reused as a skill session.

Operational facts come from the app's tools and from the skill handler. They do not come from model weights.

## Skills

```swift
let ask = try AskAssistant(AskConfiguration(
    assistantName: "Ask Pantry",
    persistence: .memory,
    domains: [
        AskDomain(id: "recipes", summary: "Cooking", routingNotes: "Food questions stay here.")
    ],
    skills: [
        AskSkill(
            id: "whatsForDinner",
            domainID: "recipes",
            title: "Dinner",
            summary: "Suggest dinner from what is on hand",
            routingNotes: "Dinner, cook, and meal questions.",
            fulfillment: .reply { _ in
                AskReply(text: "Pasta with what you have.", spoken: "Pasta.", actions: [
                    AskAction(id: "open-recipes", title: "Open recipes")
                ])
            }
        )
    ],
    contextBlock: { "pantry=pasta,tomatoes" },
    chips: { _ in
        [AskChip(id: "dinner", skillID: "whatsForDinner", title: "What's for dinner?")]
    }
))
```

`AskChatView(assistant:)` shows the chips, the transcript, and a composer.

## Handing a turn to an existing intent

Ask's `perform()` cannot `return try await FlightStatusIntent().perform()`. Those `perform()` methods return different opaque result types, and one method cannot branch between two `opensIntent` types.

Share the loader instead. The existing intent and the Ask skill both call it. Ask shows that loader's view, so the person sees the same card.

```swift
enum FlightStatusCard {
    struct Content {
        var spoken: String
        var view: FlightStatusView
    }

    static func load() async -> Content {
        // The body that used to live in FlightStatusIntent.perform().
        Content(spoken: "On time", view: FlightStatusView())
    }
}

// The shortcut and Siri phrase stay on the existing intent.
func perform() async throws -> some IntentResult & ShowsSnippetView & ProvidesDialog {
    let card = await FlightStatusCard.load()
    return .result(dialog: IntentDialog(stringLiteral: card.spoken), view: card.view)
}

// The Ask skill points at the same loader.
AskSkill(
    id: "flightStatus",
    domainID: "trip",
    title: "Flight status",
    summary: "Live status for a flight",
    requiredSlots: ["flightNumber"],
    routingNotes: "Flight status, gate, and boarding. Not a map unless they asked for a map.",
    fulfillment: .intent { _ in
        let card = await FlightStatusCard.load()
        return AskIntentCard(spoken: card.spoken, view: card.view)
    }
)
```

The app's own Ask intent has one result type. It returns the card's view for an `.intent` skill and Ask's reply view otherwise.

```swift
let result = await ask.handle(utterance: asked)
switch AskConversation().step(after: result) {
case .stop(let turn):
    // An intent card stays on screen. Do not ask "what else?" over it.
    return snippet(for: turn)
case .askAgain(let turn, let prompt):
    // Show the reply, then request another utterance with `prompt`.
    return snippet(for: turn, followUp: prompt)
}
```

AskKit does not ship an `AppIntent`. Titles, shortcuts, and snippet chrome belong to the app.

## Store

```swift
public enum AskPersistence {
    case memory
    case swiftData(storeURL: URL?)
    case privateCloud(containerIdentifier: String, storeURL: URL?)
    case container(ModelContainer)
}
```

`memory` is an in-memory SwiftData store. `swiftData` is local only (`cloudKitDatabase: .none`). `privateCloud` uses `cloudKitDatabase: .private(containerIdentifier)`. There is no public database and no shared database.

For private CloudKit the app turns on iCloud and CloudKit, registers that container identifier, and adds the remote-notification background mode. A signed-out or offline device still reads and writes the local store.

Turns store the person's words, the spoken reply, the skill id, and the slot dictionary. They do not store tool calls, tool output, auth tokens, or SwiftUI views. Pass `omittedSlotKeys` to drop values such as a record locator before save. The handler for that turn still sees them.

An app that already has a SwiftData stack can add `AskThread` and `AskTurnRecord` to its schema and pass `.container(modelContainer)`.

`AskChatView` reads the thread with `@Query`. Clear deletes that thread.

## Tests

The package tests use a scripted model, so they do not need Apple Intelligence. Run them on an iOS 27 simulator:

```sh
xcodebuild test -scheme AskKit -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

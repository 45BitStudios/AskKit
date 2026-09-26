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
7. A `.search` skill opens one new session that carries only `SpotlightSearchTool`. It answers from the app's Core Spotlight index.
8. A routing session is never reused as a skill session.

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
            contextKeys: ["pantry"],
            routingNotes: "Dinner, cook, and meal questions.",
            fulfillment: .reply { invocation in
                let pantry = invocation.context.value(for: "pantry") ?? "what you have"
                return AskReply(text: "Cook \(pantry).", spoken: "Cook \(pantry).", actions: [
                    AskAction(id: "open-recipes", title: "Open recipes")
                ])
            }
        )
    ],
    context: {
        AskContext(
            promptBlock: "signedIn=true pantry=pasta,tomatoes",
            values: ["signedIn": "true", "pantry": "pasta,tomatoes", "userID": "42"]
        )
    },
    chips: { context in
        let pantry = context.value(for: "pantry") ?? "what you have"
        return [AskChip(id: "dinner", skillID: "whatsForDinner", title: "Cook \(pantry)?")]
    }
))
```

`AskChatView(assistant:)` shows the chips, the transcript, and a composer.

## Context

Each turn asks the app what is true right now. That snapshot is `AskContext`. Skills read `values`. The model only sees `promptBlock`, so a private value such as `userID` can stay in `values` and out of the prompt.

A skill lists the keys it needs in `contextKeys`. An empty list means the skill receives the whole snapshot. The dinner skill above receives `pantry` and does not receive `userID`. Chips get the same snapshot, which is how "Cook pasta,tomatoes?" is built without a model call.

Pass a closure, or a type that owns the state:

```swift
struct PantrySource: AskContextSource {
    func currentContext() async -> AskContext {
        AskContext(
            promptBlock: "signedIn=true pantry=pasta",
            values: ["signedIn": "true", "pantry": "pasta", "userID": "42"]
        )
    }
}

let ask = try AskAssistant(AskConfiguration(
    assistantName: "Ask Pantry",
    domains: [/* ... */],
    skills: [/* ... */],
    source: PantrySource(),
    chips: { _ in [] }
))
```

`currentContext()` runs at the start of the turn and is what routing and chips use. Override `context(forSkill:keys:)` when one skill needs a heavier snapshot than that, such as the document that is open. The default scopes `values` to the skill's `contextKeys` and leaves `promptBlock` as it was.

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

## Searching the app's index

A `.search` skill answers from what the app already donated to Core Spotlight. After routing picks the skill, Ask opens one new session with a `SpotlightSearchTool` and no other tools. The model searches, then writes a short answer from the results. The skill's `render` gets that answer and every item the tool returned, and draws a reply or a card.

```swift
AskSkill(
    id: "hikeSearch",
    domainID: "hikes",
    title: "Hikes",
    summary: "Find hikes the person logged",
    routingNotes: "Hikes, trails, and walks they went on.",
    fulfillment: .search(AskSearchSkill(
        instructions: "Hikes have a title, altitude, and completion date.",
        restore: { ids in await HikeStore.shared.items(ids: ids) },
        render: { invocation, result in
            .intent(AskIntentCard(spoken: result.answer, view: HikeList(ids: result.items.map(\.id))))
        }
    ))
)
```

`makeTool` defaults to `.focused(.items)` guidance, which fits the on-device context. Pass your own to set a `GuidanceProfile`, a `ContactResolver`, custom stages, or `sources: [.files]`. Implement `CSSearchableIndexDelegate.searchableItems(forIdentifiers:)` so the tool can recover full items.

A search skill does not need required slots. If it has some and they are missing, slot filling runs first as usual.

When the search cannot run, `render` gets an empty `answer` and no items. Check for that and say something useful.

A search reply is saved like any other reply. A search card also saves the item identifiers, and nothing else from the items. When the chat shows that card again, Ask calls `restore` with those identifiers, then calls `render`. The model does not run again.

`AskModelClient.search` runs the session. Tests replace it the same way they replace routing.

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

Turns store the person's words, the spoken reply, the skill id, and the slot dictionary. A search card turn also stores its item identifiers. Turns do not store tool calls, other tool output, auth tokens, or SwiftUI views. Pass `omittedSlotKeys` to drop values such as a record locator before save. The handler for that turn still sees them.

An app that already has a SwiftData stack can add `AskThread` and `AskTurnRecord` to its schema and pass `.container(modelContainer)`.

`AskChatView` reads the thread with `@Query`. Clear deletes that thread.

## Tests

The package tests use a scripted model, so they do not need Apple Intelligence. Run them on an iOS 27 simulator:

```sh
xcodebuild test -scheme AskKit -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

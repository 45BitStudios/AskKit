# Generated cards

A skill can hand AskKit facts and let it lay out the card.

## Overview

`.generated` builds an ``AskCardNode`` tree. ``AskGeneratedCardView`` draws it. The tree is not SwiftUI source. Charts, photos, and maps stay on host-drawn cards.

While the model is composing, the chat shows a redacted placeholder (`AskGeneratedCardPlaceholder`) and the checklist (`AskCompositionProgressView`). Reduce Motion leaves the placeholder still. The checklist has four phases, in order:

- Understand request
- Search
- Prepare data
- Write layout

Search follows a tool call. Prepare data follows the writer. Write layout is the compose session. A phase does not move backward. ``AskCompositionProgress/updates()`` yields each snapshot. Finished phases record a duration in ``AskCompositionMetrics``. That log stays on device.

## Attribute a fact

``AskCardSource`` is the name of a source, and an optional http or https link. Set ``AskGeneratedBlueprint/sources`` or ``AskCardNode/sources``. The sanitizer keeps four sources on a node and drops any other URL scheme. The card footer reads `Source: …`. Older card JSON has no `sources` key and still decodes.

```swift
AskGeneratedBlueprint(
    title: "Forecast",
    spoken: "It is 72 degrees and partly cloudy.",
    facts: "72°\nPartly cloudy",
    sources: [AskCardSource(name: "Weather", url: URL(string: "https://weather.example/today"))]
)
```

## Follow-up cards

``AskAssistant/appendCard(_:from:to:)`` adds a card under an ``AskGeneratedThread``. Earlier cards stay on screen. Their facts go into the next compose prompt as prior facts. ``AskGeneratedContext/bounded(_:limit:cards:)`` keeps at most six cards and 1,200 characters, dropping the oldest first.

``AskAssistant/composeCard(from:priorFacts:)`` leaves the prompt unchanged when `priorFacts` is empty. A chat thread passes saved card facts only when ``AskConfiguration/passesGeneratedFollowUpContext`` is true. A follow-up chip scrolls to the new card. Reduce Motion jumps.

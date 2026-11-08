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

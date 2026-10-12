import SwiftUI

/// Values the shortcut snippet has already loaded. The snippet view is snapshotted as soon as it is returned, so the chart has to be ready in `body`.
struct AskSnippetHealthDraw {
    var range: AskHealthRange
    var series: AskHealthSeriesSnapshot
}

struct AskSnippetSurface {
    var isSnippet = false
    var health: [String: AskSnippetHealthDraw] = [:]
    var completedReminders: Set<String> = []
}

extension EnvironmentValues {
    @Entry var askSnippet = AskSnippetSurface()
}

enum AskSnippetMaps {
    static func key(_ places: [AskLocationPin.Place]) -> String {
        places.map(\.id).joined(separator: "|")
    }
}

/// A view built on the main actor, handed back to the snippet. The snippet renders it and does not share it further.
struct AskSnippetViewBox: @unchecked Sendable {
    var view: AnyView
}

/// Reads the saved turn and prepares the cards. It does not change reminders, health, or the map.
@MainActor
enum AskSnippetPreparation {
    static func make(turnID: UUID?, client: AskIntentClient) async -> AskSnippetViewBox {
        guard let turnID else {
            return AskSnippetViewBox(view: AnyView(AskIntentCards(cards: [])))
        }
        let pages = await client.assistant.pages(for: turnID)
        var surface = AskSnippetSurface(isSnippet: true)
        var seenHealth = Set<String>()
        var reminderIDs: [String] = []
        for page in pages {
            guard let reading = page.appleReading else { continue }
            if reading.name == "health",
               let chart = AskHealthChartModel.parse(reading.lines),
               seenHealth.insert(chart.metric.key).inserted {
                let choice = AskHealthRanges.shared.choices[chart.metric.key]
                let range = AskHealthChartModel.snippetRange(initial: chart.range, choice: choice)
                let series = await AskHealthRead.series(metric: chart.metric, range: range)
                surface.health[chart.metric.key] = AskSnippetHealthDraw(range: range, series: series)
            }
            if reading.name == "reminders" {
                reminderIDs.append(contentsOf: AskReminderItem.tasks(in: reading.lines).map(\.id))
            }
        }
        if !reminderIDs.isEmpty {
            surface.completedReminders = await AskRemindersRead.completedIDs(reminderIDs)
        }
        let cards = pages.compactMap { $0.card?.view }
        return AskSnippetViewBox(view: AnyView(
            AskIntentCards(cards: cards)
                .environment(\.askSnippet, surface)
                .environment(\.askCardStyle, .snippet)
        ))
    }
}

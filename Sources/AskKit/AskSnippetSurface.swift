import SwiftUI

/// Values the shortcut snippet has already loaded. The snippet view is snapshotted as soon as it is returned, so the chart has to be ready in `body`.
package struct AskSnippetHealthDraw {
    package init(range: AskHealthRange, series: AskHealthSeriesSnapshot) {
        self.range = range
        self.series = series
    }

    package var range: AskHealthRange
    package var series: AskHealthSeriesSnapshot
}

package struct AskSnippetSurface {
    package init(isSnippet: Bool = false, health: [String : AskSnippetHealthDraw] = [:], completedReminders: Set<String> = []) {
        self.isSnippet = isSnippet
        self.health = health
        self.completedReminders = completedReminders
    }

    package var isSnippet = false
    package var health: [String: AskSnippetHealthDraw] = [:]
    package var completedReminders: Set<String> = []
}

extension EnvironmentValues {
    @Entry package var askSnippet = AskSnippetSurface()
}

import AppIntents
import AskKit

/// Lists the AskKit package so Shortcuts and Siri can see ``AskIntent``.
nonisolated struct AskGarageAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [AskKitAppIntents.self]
    }
}

struct AskGarageShortcuts: AppShortcutsProvider {
    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask a question in \(.applicationName)"
            ],
            shortTitle: "Ask",
            systemImageName: "bolt.car"
        )
        AppShortcut(
            intent: CompleteAskReminderIntent(),
            phrases: [
                "Complete a reminder in \(.applicationName)",
                "Mark a reminder complete in \(.applicationName)"
            ],
            shortTitle: "Complete Reminder",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: ReopenAskReminderIntent(),
            phrases: [
                "Reopen a reminder in \(.applicationName)",
                "Mark a reminder incomplete in \(.applicationName)"
            ],
            shortTitle: "Reopen Reminder",
            systemImageName: "circle"
        )
        AppShortcut(
            intent: ShowAskHealthRangeIntent(),
            phrases: [
                "Show \(\.$measurement) for \(\.$range) in \(.applicationName)",
                "Show my \(\.$measurement) for the \(\.$range) in \(.applicationName)"
            ],
            shortTitle: "Show Health",
            systemImageName: "chart.bar"
        )
    }
}

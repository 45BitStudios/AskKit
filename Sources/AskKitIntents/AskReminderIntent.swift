import AppIntents
import AskKit
import Foundation

/// Marks one reminder complete. Siri and the Complete Reminder shortcut run this and speak the result.
public struct CompleteAskReminderIntent: AppIntent {
    public static let title: LocalizedStringResource = "Complete Reminder"
    public static let description = IntentDescription("Marks a reminder complete.")

    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Reminder")
    public var reminder: AskReminderEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$reminder)")
    }

    public init() {}

    public init(reminder: AskReminderEntity) {
        self.reminder = reminder
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = reminder.title
        try await AskReminderIntentWork.complete(reminder)
        return .result(dialog: "Completed \(title).")
    }
}

/// The circle on a reminder row. A dialog would open a second shortcut window, so this only completes the reminder and the snippet redraws.
package struct AskReminderCompleteTap: AppIntent {
    package static let title: LocalizedStringResource = "Complete Reminder"
    package static let isDiscoverable = false

    package static var supportedModes: IntentModes { .background }
    package static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Reminder")
    var reminder: AskReminderEntity

    package init() {}

    package init(reminder: AskReminderEntity) {
        self.reminder = reminder
    }

    package func perform() async throws -> some IntentResult {
        try await AskReminderIntentWork.complete(reminder)
        return .result()
    }
}

/// Marks one completed reminder open again. Siri and the Reopen Reminder shortcut run this and speak the result.
public struct ReopenAskReminderIntent: AppIntent {
    public static let title: LocalizedStringResource = "Reopen Reminder"
    public static let description = IntentDescription("Marks a completed reminder incomplete.")

    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Reminder", query: AskCompletedReminderQuery())
    public var reminder: AskReminderEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Reopen \(\.$reminder)")
    }

    public init() {}

    public init(reminder: AskReminderEntity) {
        self.reminder = reminder
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let title = reminder.title
        try await AskReminderIntentWork.reopen(reminder)
        return .result(dialog: "Reopened \(title).")
    }
}

/// The checkmark on a reminder row. A dialog would open a second shortcut window, so this only reopens the reminder and the snippet redraws.
package struct AskReminderReopenTap: AppIntent {
    package static let title: LocalizedStringResource = "Reopen Reminder"
    package static let isDiscoverable = false

    package static var supportedModes: IntentModes { .background }
    package static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Reminder")
    var reminder: AskReminderEntity

    package init() {}

    package init(reminder: AskReminderEntity) {
        self.reminder = reminder
    }

    package func perform() async throws -> some IntentResult {
        try await AskReminderIntentWork.reopen(reminder)
        return .result()
    }
}

private enum AskReminderIntentWork {
    static func complete(_ reminder: AskReminderEntity) async throws {
        try await AskRemindersRead.complete(id: reminder.id)
        let id = reminder.id
        await MainActor.run { AskReminderChecks.shared.mark(id) }
    }

    static func reopen(_ reminder: AskReminderEntity) async throws {
        try await AskRemindersRead.reopen(id: reminder.id)
        let id = reminder.id
        await MainActor.run { AskReminderChecks.shared.unmark(id) }
    }
}

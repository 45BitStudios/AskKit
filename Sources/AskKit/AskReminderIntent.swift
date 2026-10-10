import AppIntents
import Foundation

/// Reminders the Complete button and Siri can mark done.
public struct AskReminderEntity: AppEntity, Sendable, Equatable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Reminder")
    public static let defaultQuery = AskReminderQuery()

    public var id: String

    @Property(title: "Title")
    public var title: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct AskReminderQuery: EntityQuery, EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [AskReminderEntity.ID]) async throws -> [AskReminderEntity] {
        await AskRemindersRead.entities(ids: identifiers)
    }

    public func suggestedEntities() async throws -> [AskReminderEntity] {
        await AskRemindersRead.incomplete(matching: nil, limit: 8)
    }

    public func entities(matching string: String) async throws -> [AskReminderEntity] {
        await AskRemindersRead.incomplete(matching: string, limit: 8)
    }
}

/// Completed reminders. Reopen uses this so Siri offers ones that can be undone.
public struct AskCompletedReminderQuery: EntityQuery, EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [AskReminderEntity.ID]) async throws -> [AskReminderEntity] {
        await AskRemindersRead.entities(ids: identifiers)
    }

    public func suggestedEntities() async throws -> [AskReminderEntity] {
        await AskRemindersRead.completed(matching: nil, limit: 8)
    }

    public func entities(matching string: String) async throws -> [AskReminderEntity] {
        await AskRemindersRead.completed(matching: string, limit: 8)
    }
}

public enum AskReminderIntentError: Error, CustomLocalizedStringResourceConvertible {
    case missing
    case denied

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .missing:
            "That reminder is not on this device."
        case .denied:
            "AskKit doesn't have permission to update reminders."
        }
    }
}

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
struct AskReminderCompleteTap: AppIntent {
    static let title: LocalizedStringResource = "Complete Reminder"
    static let isDiscoverable = false

    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Reminder")
    var reminder: AskReminderEntity

    init() {}

    init(reminder: AskReminderEntity) {
        self.reminder = reminder
    }

    func perform() async throws -> some IntentResult {
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
struct AskReminderReopenTap: AppIntent {
    static let title: LocalizedStringResource = "Reopen Reminder"
    static let isDiscoverable = false

    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Reminder")
    var reminder: AskReminderEntity

    init() {}

    init(reminder: AskReminderEntity) {
        self.reminder = reminder
    }

    func perform() async throws -> some IntentResult {
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

/// Reminder rows the open chat has already completed.
@MainActor
@Observable
final class AskReminderChecks {
    static let shared = AskReminderChecks()
    private(set) var completed: Set<String> = []

    func mark(_ id: String) {
        completed.insert(id)
    }

    func unmark(_ id: String) {
        completed.remove(id)
    }

    func adopt(_ ids: Set<String>) {
        completed.formUnion(ids)
    }
}

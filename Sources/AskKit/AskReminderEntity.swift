import AppIntents
import CoreTransferable
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

    /// `@Property` stores an `EntityProperty`, which is a class and is not `Equatable`.
    public static func == (lhs: AskReminderEntity, rhs: AskReminderEntity) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}

/// Reminder rows the open chat has already completed.
@MainActor
@Observable
package final class AskReminderChecks {
    package static let shared = AskReminderChecks()
    package private(set) var completed: Set<String> = []

    package func mark(_ id: String) {
        completed.insert(id)
    }

    package func unmark(_ id: String) {
        completed.remove(id)
    }

    package func adopt(_ ids: Set<String>) {
        completed.formUnion(ids)
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

extension AskReminderEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.title)
    }
}

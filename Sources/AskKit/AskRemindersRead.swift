import AskKitSurface
import Foundation

#if canImport(EventKit)
import EventKit

package enum AskRemindersRead {
    static func add(
        title: String,
        day: Int?,
        hour: Int?,
        minute: Int,
        notes: String,
        priority: String
    ) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = EKEventStore()
        guard await allowReminders(store, writing: true) else { return AskAppleCopy.denied }
        guard let target = store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first(where: \.allowsContentModifications) else {
            return "No list to add to."
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = target
        reminder.title = AskAppleCopy.plain(title, limit: 200)
        let about = AskAppleCopy.plain(notes, limit: 500)
        if !about.isEmpty { reminder.notes = about }
        if let rank = priorityValue(priority) { reminder.priority = rank }
        let calendar = Calendar.current
        if let day, let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) {
            var parts = calendar.dateComponents([.year, .month, .day], from: window.start)
            if let hour {
                parts.hour = hour
                parts.minute = minute
            }
            reminder.dueDateComponents = parts
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            return "Could not add the reminder."
        }
        return AskReminderItem.line(
            title: AskAppleCopy.addedPrefix + AskAppleCopy.plain(title, limit: 200),
            due: dueText(reminder),
            id: reminder.calendarItemIdentifier
        )
#endif
    }

    /// Changes one incomplete reminder. Write-only access can add, but it cannot find one to change.
    static func update(
        title: String,
        day: Int?,
        hour: Int?,
        minute: Int?,
        notes: String?,
        priority: String?,
        newTitle: String?
    ) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return AskAppleCopy.denied }
        let found = await match(store, title: title, day: day)
        switch found {
        case .none:
            return "No matching reminder."
        case .many:
            return "More than one reminder is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let reminder):
            if let newTitle {
                let renamed = AskAppleCopy.plain(newTitle, limit: 200)
                if !renamed.isEmpty { reminder.title = renamed }
            }
            if hour != nil || day != nil {
                applyDue(day: day, hour: hour, minute: minute, to: reminder)
            }
            if let notes {
                reminder.notes = AskAppleCopy.plain(notes, limit: 500)
            }
            if let priority, let rank = priorityValue(priority) {
                reminder.priority = rank
            }
            do {
                try store.save(reminder, commit: true)
            } catch {
                return "Could not change the reminder."
            }
            let name = AskAppleCopy.plain(reminder.title ?? title, limit: 200)
            return "\(AskAppleCopy.updatedPrefix)\(name)."
        }
#endif
    }

    /// Removes one incomplete reminder. Several matches, or none, leave the list unchanged.
    static func remove(title: String) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return AskAppleCopy.denied }
        switch await match(store, title: title, day: nil) {
        case .none:
            return "No matching reminder."
        case .many:
            return "More than one reminder is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let reminder):
            let name = AskAppleCopy.plain(reminder.title ?? title, limit: 200)
            do {
                try store.remove(reminder, commit: true)
            } catch {
                return "Could not remove the reminder."
            }
            return "\(AskAppleCopy.removedPrefix)\(name)."
        }
#endif
    }

    package static func complete(id: String) async throws {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        throw AskReminderIntentError.denied
#else
        let store = EKEventStore()
        guard await allowReminders(store, writing: true) else { throw AskReminderIntentError.denied }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw AskReminderIntentError.missing
        }
        if reminder.isCompleted { return }
        reminder.isCompleted = true
        reminder.completionDate = Date()
        try store.save(reminder, commit: true)
#endif
    }

    package static func reopen(id: String) async throws {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        throw AskReminderIntentError.denied
#else
        let store = EKEventStore()
        guard await allowReminders(store, writing: true) else { throw AskReminderIntentError.denied }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw AskReminderIntentError.missing
        }
        if !reminder.isCompleted { return }
        reminder.isCompleted = false
        reminder.completionDate = nil
        try store.save(reminder, commit: true)
#endif
    }

    /// Identifiers already completed in Reminders. The card shows a filled check for these.
    package static func completedIDs(_ ids: [String]) async -> Set<String> {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        var done: Set<String> = []
        for id in ids {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.isCompleted else { continue }
            done.insert(id)
        }
        return done
    }

    static func entities(ids: [String]) async -> [AskReminderEntity] {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        return ids.compactMap { id in
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
            return entity(reminder)
        }
    }

    static func completed(matching name: String?, limit: Int) async -> [AskReminderEntity] {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: nil)
        let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let matched = (reminders ?? []).filter { reminder in
                    guard !wanted.isEmpty else { return true }
                    return (reminder.title ?? "").localizedStandardContains(wanted)
                }
                let entities = matched.prefix(limit).map(Self.entity)
                continuation.resume(returning: Array(entities))
            }
        }
    }

    private static func entity(_ reminder: EKReminder) -> AskReminderEntity {
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title?.isEmpty == false) ? title! : "Reminder"
        return AskReminderEntity(id: reminder.calendarItemIdentifier, title: name)
    }

    static func incomplete(matching name: String?, limit: Int) async -> [AskReminderEntity] {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let matched = (reminders ?? []).filter { reminder in
                    guard !wanted.isEmpty else { return true }
                    return (reminder.title ?? "").localizedStandardContains(wanted)
                }
                let entities = matched.prefix(limit).map(Self.entity)
                continuation.resume(returning: Array(entities))
            }
        }
    }

    /// Open reminders in due-date order. Does not ask for access.
    static func openItems(limit: Int) async -> [AskSurfaceReminder] {
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let cap = min(max(limit, 1), 8)
        let calendar = Calendar.current
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let soonest = (reminders ?? []).sorted { lhs, rhs in
                    switch (Self.dueDate(lhs, calendar: calendar), Self.dueDate(rhs, calendar: calendar)) {
                    case let (left?, right?):
                        return left < right
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return false
                    }
                }
                let items = soonest.prefix(cap).map { reminder in
                    let raw = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let title = raw.isEmpty ? "Reminder" : AskAppleCopy.plain(raw, limit: 120)
                    return AskSurfaceReminder(
                        id: reminder.calendarItemIdentifier,
                        title: title,
                        due: Self.dueDate(reminder, calendar: calendar)
                    )
                }
                continuation.resume(returning: Array(items))
            }
        }
    }

    static func lines(limit: Int) async -> String {
        let store = EKEventStore()
        let granted = await allowReminders(store, writing: false)
        guard granted else { return AskAppleCopy.denied }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let cap = min(max(limit, 1), 8)
        let calendar = Calendar.current
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let soonest = (reminders ?? []).sorted { lhs, rhs in
                    switch (Self.dueDate(lhs, calendar: calendar), Self.dueDate(rhs, calendar: calendar)) {
                    case let (left?, right?):
                        return left < right
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return false
                    }
                }
                let lines = soonest.prefix(cap).map(Self.line)
                let text = lines.isEmpty ? "No reminders." : lines.joined(separator: "\n")
                continuation.resume(returning: text)
            }
        }
    }

    private static func dueDate(_ reminder: EKReminder, calendar: Calendar) -> Date? {
        guard let parts = reminder.dueDateComponents else { return nil }
        return calendar.date(from: parts)
    }

    private enum Match {
        case one(EKReminder)
        case none
        case many
    }

    /// One exact title wins. One title that contains the words is next. A day limits the search to that due date.
    private static func match(_ store: EKEventStore, title: String, day: Int?) async -> Match {
        switch await choose(store, title: title, day: day) {
        case .none:
            return .none
        case .many:
            return .many
        case .one(let id):
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return .none }
            return .one(reminder)
        }
    }

    /// The fetch callback stays on EventKit's queue. Only the identifier crosses back.
    private static func choose(_ store: EKEventStore, title: String, day: Int?) async -> Choice {
        let wanted = folded(title)
        guard !wanted.isEmpty else { return .none }
        let calendar = Calendar.current
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let scoped = (reminders ?? []).filter { onDay($0, day: day, calendar: calendar) }
                let exact = scoped.filter { folded($0.title ?? "") == wanted }
                if exact.count == 1, let reminder = exact.first {
                    continuation.resume(returning: .one(reminder.calendarItemIdentifier))
                    return
                }
                if exact.count > 1 {
                    continuation.resume(returning: .many)
                    return
                }
                let contains = scoped.filter { folded($0.title ?? "").localizedStandardContains(wanted) }
                if contains.count == 1, let reminder = contains.first {
                    continuation.resume(returning: .one(reminder.calendarItemIdentifier))
                    return
                }
                continuation.resume(returning: contains.isEmpty ? .none : .many)
            }
        }
    }

    private enum Choice: Sendable {
        case one(String)
        case none
        case many
    }

    private static func onDay(_ reminder: EKReminder, day: Int?, calendar: Calendar) -> Bool {
        guard let day else { return true }
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar),
              let parts = reminder.dueDateComponents,
              let due = calendar.date(from: parts) else { return false }
        return calendar.isDate(due, inSameDayAs: window.start)
    }

    private static func applyDue(day: Int?, hour: Int?, minute: Int?, to reminder: EKReminder) {
        let calendar = Calendar.current
        let base: Date
        if let day, let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) {
            base = window.start
        } else if let existing = reminder.dueDateComponents, let date = calendar.date(from: existing) {
            base = date
        } else {
            base = calendar.startOfDay(for: Date())
        }
        var parts = calendar.dateComponents([.year, .month, .day], from: base)
        if let hour {
            parts.hour = hour
            parts.minute = minute ?? 0
        } else if let existing = reminder.dueDateComponents, existing.hour != nil {
            parts.hour = existing.hour
            parts.minute = existing.minute
        }
        reminder.dueDateComponents = parts
    }

    /// 0 none, 1 high, 5 medium, 9 low. An empty rank stays unset.
    private static func priorityValue(_ rank: String) -> Int? {
        switch rank.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none": 0
        case "high": 1
        case "medium": 5
        case "low": 9
        default: nil
        }
    }

    private static func priorityLabel(_ value: Int) -> String {
        switch value {
        case 1...4: "high"
        case 5: "medium"
        case 6...9: "low"
        default: ""
        }
    }

    /// Due, then priority, then notes. They stay after the first separator so the card title is only the name.
    private static func dueText(_ reminder: EKReminder) -> String {
        var parts: [String] = []
        if let components = reminder.dueDateComponents, let due = Calendar.current.date(from: components) {
            let when = components.hour == nil
                ? due.formatted(date: .abbreviated, time: .omitted)
                : due.formatted(date: .abbreviated, time: .shortened)
            parts.append(when)
        }
        let rank = priorityLabel(reminder.priority)
        if !rank.isEmpty { parts.append(rank) }
        let notes = AskAppleCopy.plain(reminder.notes ?? "", limit: 80)
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func allowReminders(_ store: EKEventStore, writing: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .writeOnly:
            return writing
        case .notDetermined:
            return (try? await store.requestFullAccessToReminders()) ?? false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func line(_ reminder: EKReminder) -> String {
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title?.isEmpty == false) ? title! : "Reminder"
        return AskReminderItem.line(title: name, due: dueText(reminder), id: reminder.calendarItemIdentifier)
    }
}
#else
/// EventKit is not on this platform. The reminders tool is never offered here; these keep the callers compiling.
package enum AskRemindersRead {
    static func add(
        title: String,
        day: Int?,
        hour: Int?,
        minute: Int,
        notes: String,
        priority: String
    ) async -> String { AskAppleCopy.unavailable }

    static func update(
        title: String,
        day: Int?,
        hour: Int?,
        minute: Int?,
        notes: String?,
        priority: String?,
        newTitle: String?
    ) async -> String { AskAppleCopy.unavailable }

    static func remove(title: String) async -> String { AskAppleCopy.unavailable }

    package static func complete(id: String) async throws { throw AskReminderIntentError.denied }

    package static func reopen(id: String) async throws { throw AskReminderIntentError.denied }

    package static func completedIDs(_ ids: [String]) async -> Set<String> { [] }

    static func entities(ids: [String]) async -> [AskReminderEntity] { [] }

    static func completed(matching name: String?, limit: Int) async -> [AskReminderEntity] { [] }

    static func incomplete(matching name: String?, limit: Int) async -> [AskReminderEntity] { [] }

    static func openItems(limit: Int) async -> [AskSurfaceReminder] { [] }

    static func lines(limit: Int) async -> String { AskAppleCopy.unavailable }
}
#endif

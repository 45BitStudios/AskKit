import AskKitSurface
import CoreGraphics
import Foundation

#if canImport(EventKit)
import EventKit

enum AskCalendarRead {
    static func add(title: String, day: Int, hour: Int?, minute: Int, place: String, notes: String) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = EKEventStore()
        guard await allowEvents(store, writing: true) else { return AskAppleCopy.denied }
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) else {
            return "Could not add the event."
        }
        guard let target = store.defaultCalendarForNewEvents
            ?? store.calendars(for: .event).first(where: \.allowsContentModifications) else {
            return "No calendar to add to."
        }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = AskAppleCopy.plain(title, limit: 200)
        event.timeZone = calendar.timeZone
        let whereTo = AskAppleCopy.plain(place, limit: 200)
        if !whereTo.isEmpty { event.location = whereTo }
        let about = AskAppleCopy.plain(notes, limit: 500)
        if !about.isEmpty { event.notes = about }
        if let hour {
            guard applyTime(hour: hour, minute: minute, on: window.start, to: event, calendar: calendar) else {
                return "Could not add the event."
            }
        } else {
            event.isAllDay = true
            event.startDate = window.start
            event.endDate = window.end
        }
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            return "Could not add the event."
        }
        let saved = line(event, dayTitle: window.title, dayStart: window.start, calendar: calendar)
        return AskAppleCopy.addedPrefix + saved
#endif
    }

    /// Changes one event on that day. Write-only access can add, but it cannot find an event to change.
    static func update(
        title: String,
        day: Int,
        hour: Int?,
        minute: Int?,
        place: String?,
        notes: String?,
        newTitle: String?
    ) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = EKEventStore()
        guard await allowEvents(store, writing: false) else { return AskAppleCopy.denied }
        guard let found = events(store, day: day) else { return "Could not change the event." }
        switch match(found.events, title: title) {
        case .none:
            return "No matching event."
        case .many:
            return "More than one event is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let event):
            if let newTitle {
                let renamed = AskAppleCopy.plain(newTitle, limit: 200)
                if !renamed.isEmpty { event.title = renamed }
            }
            if let hour {
                guard applyTime(hour: hour, minute: minute ?? 0, on: found.window.start, to: event, calendar: found.calendar) else {
                    return "Could not change the event."
                }
            }
            if let place {
                event.location = AskAppleCopy.plain(place, limit: 200)
            }
            if let notes {
                event.notes = AskAppleCopy.plain(notes, limit: 500)
            }
            do {
                try store.save(event, span: .thisEvent)
            } catch {
                return "Could not change the event."
            }
            let saved = line(event, dayTitle: found.window.title, dayStart: found.window.start, calendar: found.calendar)
            return AskAppleCopy.updatedPrefix + saved
        }
#endif
    }

    /// Removes one event on that day. Several matches, or none, leave the calendar unchanged.
    static func remove(title: String, day: Int) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = EKEventStore()
        guard await allowEvents(store, writing: false) else { return AskAppleCopy.denied }
        guard let found = events(store, day: day) else { return "Could not remove the event." }
        switch match(found.events, title: title) {
        case .none:
            return "No matching event."
        case .many:
            return "More than one event is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let event):
            let saved = line(event, dayTitle: found.window.title, dayStart: found.window.start, calendar: found.calendar)
            do {
                try store.remove(event, span: .thisEvent)
            } catch {
                return "Could not remove the event."
            }
            return AskAppleCopy.removedPrefix + saved
        }
#endif
    }

    static func lines(day: Int) async -> String {
        let store = EKEventStore()
        let granted = await allowEvents(store, writing: false)
        guard granted else { return AskAppleCopy.denied }
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) else {
            return "Nothing scheduled."
        }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.startDate < window.end }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
        guard !events.isEmpty else { return "\(window.title) · Nothing scheduled." }
        return events.map { line($0, dayTitle: window.title, dayStart: window.start, calendar: calendar) }.joined(separator: "\n")
    }

    /// Birthday calendar events from the start day through the next two weeks.
    static func birthdays(from day: Int) async -> String {
        let store = EKEventStore()
        let granted = await allowEvents(store, writing: false)
        guard granted else { return AskAppleCopy.denied }
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar),
              let end = calendar.date(byAdding: .day, value: 14, to: window.start) else {
            return "No birthdays."
        }
        let birthdayCalendars = store.calendars(for: .event).filter { $0.type == .birthday }
        let calendars = birthdayCalendars.isEmpty ? nil : birthdayCalendars
        let predicate = store.predicateForEvents(withStart: window.start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
            .filter { calendars != nil || $0.calendar.type == .birthday }
            .filter { $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
        guard !events.isEmpty else { return "No birthdays." }
        return events.map { event in
            let dayStart = calendar.startOfDay(for: event.startDate)
            let dayTitle = AskCalendarWindow.heading(for: dayStart, calendar: calendar)
            let name = AskAppleCopy.plain(event.title ?? "Birthday", limit: 120)
            return AskCalendarItem.line(
                day: dayTitle,
                title: name,
                when: "all day",
                colorHex: AskCalendarItem.hex(from: event.calendar.cgColor),
                kind: .birthday,
                calendarName: event.calendar.title
            )
        }.joined(separator: "\n")
    }

    private static func events(_ store: EKEventStore, day: Int) -> (window: AskCalendarWindow, events: [EKEvent], calendar: Calendar)? {
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) else { return nil }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.startDate < window.end }
            .sorted { $0.startDate < $1.startDate }
        return (window, events, calendar)
    }

    private enum Match {
        case one(EKEvent)
        case none
        case many
    }

    /// One exact title wins. One title that contains the words is next. Several matches change nothing.
    private static func match(_ events: [EKEvent], title: String) -> Match {
        let wanted = folded(title)
        guard !wanted.isEmpty else { return .none }
        let exact = events.filter { folded($0.title ?? "") == wanted }
        if exact.count == 1, let event = exact.first { return .one(event) }
        if exact.count > 1 { return .many }
        let contains = events.filter { folded($0.title ?? "").localizedStandardContains(wanted) }
        if contains.count == 1, let event = contains.first { return .one(event) }
        return contains.isEmpty ? .none : .many
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A timed event lasts one hour. An all-day event becomes timed when an hour is set.
    private static func applyTime(hour: Int, minute: Int, on day: Date, to event: EKEvent, calendar: Calendar) -> Bool {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        guard let start = calendar.date(from: parts),
              let end = calendar.date(byAdding: .hour, value: 1, to: start) else {
            return false
        }
        event.isAllDay = false
        event.timeZone = calendar.timeZone
        event.startDate = start
        event.endDate = end
        return true
    }

    private static func allowEvents(_ store: EKEventStore, writing: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .writeOnly:
            return writing
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func line(_ event: EKEvent, dayTitle: String, dayStart: Date, calendar: Calendar) -> String {
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title?.isEmpty == false) ? title! : "Event"
        let when: String
        if event.isAllDay {
            when = calendar.isDate(event.startDate, inSameDayAs: dayStart)
                ? "all day"
                : event.startDate.formatted(date: .abbreviated, time: .omitted)
        } else if calendar.isDate(event.startDate, inSameDayAs: dayStart) {
            when = event.startDate.formatted(date: .omitted, time: .shortened)
        } else {
            when = event.startDate.formatted(date: .abbreviated, time: .shortened)
        }
        var detailParts: [String] = []
        let place = AskAppleCopy.plain(event.location ?? "", limit: 80)
        if !place.isEmpty { detailParts.append(place) }
        let notes = AskAppleCopy.plain(event.notes ?? "", limit: 80)
        if !notes.isEmpty { detailParts.append(notes) }
        let birthday = event.calendar.type == .birthday || event.birthdayContactIdentifier != nil
        let kind: AskCalendarItem.Kind
        if birthday {
            kind = .birthday
        } else if event.isAllDay {
            kind = .allDay
        } else {
            kind = .timed
        }
        return AskCalendarItem.line(
            day: dayTitle,
            title: AskAppleCopy.plain(name, limit: 120),
            when: when,
            detail: detailParts.joined(separator: " · "),
            colorHex: AskCalendarItem.hex(from: event.calendar.cgColor),
            kind: kind,
            calendarName: event.calendar.title
        )
    }

    /// The soonest event that has not ended, through the next week. Does not ask for access.
    static func upcoming(now: Date) async -> AskSurfaceEvent? {
        let store = EKEventStore()
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        guard let event = store.events(matching: predicate)
            .filter({ $0.endDate > now })
            .sorted(by: { $0.startDate < $1.startDate })
            .first else { return nil }
        let rawTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "Event" : AskAppleCopy.plain(rawTitle, limit: 120)
        return AskSurfaceEvent(
            id: event.calendarItemIdentifier,
            title: title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: AskAppleCopy.plain(event.location ?? "", limit: 80)
        )
    }
}

enum AskSurfaceCalendar {
    static func upcoming(now: Date) async -> AskSurfaceEvent? {
        await AskCalendarRead.upcoming(now: now)
    }
}
#else
/// EventKit is not on this platform. The calendar tool is never offered here; these keep the callers compiling.
enum AskCalendarRead {
    static func add(title: String, day: Int, hour: Int?, minute: Int, place: String, notes: String) async -> String { AskAppleCopy.unavailable }

    static func update(
        title: String,
        day: Int,
        hour: Int?,
        minute: Int?,
        place: String?,
        notes: String?,
        newTitle: String?
    ) async -> String { AskAppleCopy.unavailable }

    static func remove(title: String, day: Int) async -> String { AskAppleCopy.unavailable }

    static func lines(day: Int) async -> String { AskAppleCopy.unavailable }

    static func birthdays(from day: Int) async -> String { AskAppleCopy.unavailable }

    static func upcoming(now: Date) async -> AskSurfaceEvent? { nil }
}

enum AskSurfaceCalendar {
    static func upcoming(now: Date) async -> AskSurfaceEvent? { nil }
}
#endif

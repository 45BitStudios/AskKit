import Foundation

/// Dates above a group of turns, and the clock time revealed beside a bubble.
struct AskTranscriptClock: Sendable {
    var calendar: Calendar
    var locale: Locale
    var now: Date

    /// Same-day turns this far apart start a new dated group.
    static let gap: TimeInterval = 60 * 60

    func showsMark(after previous: Date?, date: Date) -> Bool {
        guard let previous else { return true }
        if !calendar.isDate(previous, inSameDayAs: date) { return true }
        return date.timeIntervalSince(previous) >= Self.gap
    }

    /// "8:03 PM"
    func time(for date: Date) -> String {
        date.formatted(timeStyle)
    }

    /// "Today 4:49 PM", "Yesterday 8:03 PM", "Monday 8:03 PM", or "Oct 5 at 8:03 PM".
    func mark(for date: Date) -> String {
        let time = time(for: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(
                localized: "Today \(time)",
                comment: "Date above messages sent today. The variable is the time."
            )
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(
                localized: "Yesterday \(time)",
                comment: "Date above messages sent yesterday. The variable is the time."
            )
        }
        let start = calendar.startOfDay(for: now)
        if let week = calendar.date(byAdding: .day, value: -6, to: start), date >= week {
            return date.formatted(weekdayStyle)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(monthDayStyle)
        }
        return date.formatted(monthDayYearStyle)
    }

    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var weekdayStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide)
            .hour()
            .minute()
    }

    private var monthDayStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
            .hour()
            .minute()
    }

    private var monthDayYearStyle: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated)
            .day()
            .year()
            .hour()
            .minute()
    }
}

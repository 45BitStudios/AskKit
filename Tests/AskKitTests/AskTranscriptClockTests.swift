import XCTest
@testable import AskKit

final class AskTranscriptClockTests: XCTestCase {
    func testFirstTurnAndLongGapShowADate() {
        let now = date(2026, 10, 6, 16, 49)
        let clock = clock(now: now)
        let first = date(2026, 10, 6, 16, 40)
        XCTAssertTrue(clock.showsMark(after: nil, date: first))
        XCTAssertFalse(clock.showsMark(after: first, date: date(2026, 10, 6, 16, 50)))
        XCTAssertTrue(clock.showsMark(after: first, date: date(2026, 10, 6, 17, 40)))
    }

    func testANewDayShowsADate() {
        let clock = clock(now: date(2026, 10, 6, 0, 5))
        XCTAssertTrue(clock.showsMark(after: date(2026, 10, 5, 23, 55), date: date(2026, 10, 6, 0, 4)))
    }

    func testTodayAndYesterday() {
        let now = date(2026, 10, 6, 16, 49)
        let clock = clock(now: now)
        XCTAssertEqual(clock.mark(for: date(2026, 10, 6, 16, 49)), "Today \(clock.time(for: date(2026, 10, 6, 16, 49)))")
        XCTAssertEqual(clock.mark(for: date(2026, 10, 5, 20, 3)), "Yesterday \(clock.time(for: date(2026, 10, 5, 20, 3)))")
    }

    func testEarlierThisWeekUsesTheWeekday() {
        let now = date(2026, 10, 6, 16, 49)
        let clock = clock(now: now)
        let sent = date(2026, 9, 30, 20, 3)
        let expected = sent.formatted(weekdayStyle)
        XCTAssertEqual(clock.mark(for: sent), expected)
        XCTAssertTrue(expected.hasPrefix("Wednesday"))
    }

    func testOlderDatesIncludeTheMonth() {
        let now = date(2026, 10, 6, 16, 49)
        let clock = clock(now: now)
        let sent = date(2026, 9, 29, 20, 3)
        let expected = sent.formatted(monthDayStyle)
        XCTAssertEqual(clock.mark(for: sent), expected)
        XCTAssertTrue(expected.contains("Sep"))
        XCTAssertTrue(expected.contains("29"))
    }

    func testAPreviousYearIncludesTheYear() {
        let now = date(2026, 10, 6, 16, 49)
        let clock = clock(now: now)
        let sent = date(2025, 10, 5, 20, 3)
        let expected = sent.formatted(monthDayYearStyle)
        XCTAssertEqual(clock.mark(for: sent), expected)
        XCTAssertTrue(expected.contains("2025"))
    }

    private func clock(now: Date) -> AskTranscriptClock {
        AskTranscriptClock(calendar: gregorian, locale: Locale(identifier: "en_US"), now: now)
    }

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var weekdayStyle: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: gregorian, timeZone: TimeZone(secondsFromGMT: 0)!)
            .weekday(.wide)
            .hour()
            .minute()
    }

    private var monthDayStyle: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: gregorian, timeZone: TimeZone(secondsFromGMT: 0)!)
            .month(.abbreviated)
            .day()
            .hour()
            .minute()
    }

    private var monthDayYearStyle: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: gregorian, timeZone: TimeZone(secondsFromGMT: 0)!)
            .month(.abbreviated)
            .day()
            .year()
            .hour()
            .minute()
    }
}

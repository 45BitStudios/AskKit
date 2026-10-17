import CoreLocation
import Foundation
import SwiftUI
import WeatherKit

/// Hourly or daily, and which days. Tests use this so they do not open WeatherKit.
enum AskWeatherQuery {
    static let maximumOffset = 9
    static let maximumDays = 7
    static let maximumHours = 24

    enum Span: Equatable, Sendable {
        case hourly
        case daily
    }

    /// Hours stay on that day's card. A daily forecast, including a week, is one card.
    static func request(in question: String, now: Date = Date(), calendar: Calendar = .current) -> AskWeatherRequest {
        let span: AskWeatherQuery.Span = isHourly(question) ? .hourly : .daily
        let named = AskCalendarWindow.offset(namedIn: question, now: now, calendar: calendar)
        let offset = min(max(named ?? 0, 0), maximumOffset)
        let place = place(in: question)
        if span == .hourly {
            return AskWeatherRequest(span: .hourly, dayOffset: offset, dayCount: 1, place: place)
        }
        if named != nil {
            return AskWeatherRequest(span: .daily, dayOffset: offset, dayCount: 1, place: place)
        }
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        if tokens.contains("week") || tokens.contains("weeks") || tokens.contains("weekly") {
            return AskWeatherRequest(span: .daily, dayOffset: 0, dayCount: maximumDays, place: place)
        }
        return AskWeatherRequest(span: .daily, dayOffset: 0, dayCount: maximumDays, place: place)
    }

    /// Tool arguments. Hourly is always one day. Daily is clamped to seven.
    static func request(span: String?, day: Int?, days: Int?, place: String? = nil) -> AskWeatherRequest {
        let hourly = AskAppleCopy.folded(span ?? "").contains("hour")
        let offset = min(max(day ?? 0, 0), maximumOffset)
        let named = usablePlace(place ?? "")
        if hourly {
            return AskWeatherRequest(span: .hourly, dayOffset: offset, dayCount: 1, place: named)
        }
        let count = min(max(days ?? maximumDays, 1), maximumDays)
        return AskWeatherRequest(span: .daily, dayOffset: offset, dayCount: count, place: named)
    }

    /// The city after "in", "for", or "at". A weekday or "the week" is not a place.
    static func place(in question: String) -> String {
        let folded = AskAppleCopy.folded(question)
        let markers = [" in ", " for ", " at "]
        guard let marker = markers.compactMap({ folded.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return ""
        }
        let head = folded[..<marker.lowerBound]
        guard head.contains("weather") || head.contains("forecast") || head.contains("rain") || head.contains("snow") else {
            return ""
        }
        return usablePlace(String(folded[marker.upperBound...]))
    }

    static func usablePlace(_ raw: String) -> String {
        var words = AskAppleCopy.folded(raw).split(separator: " ").map(String.init)
        let trailing: Set<String> = [
            "today", "tomorrow", "tonight", "now", "please", "currently", "on", "this",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "weekend", "week", "morning", "afternoon", "evening"
        ]
        while let last = words.last, trailing.contains(last) {
            words.removeLast()
        }
        let tail = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked: Set<String> = [
            "", "me", "here", "us", "you", "now", "current", "the week", "a week", "this week",
            "the weekend", "the day", "a day", "the forecast", "the weather"
        ]
        if blocked.contains(tail) || tail.count < 2 { return "" }
        return String(tail.prefix(80))
    }

    /// Start is inclusive. End is the next midnight and is not included.
    static func interval(for request: AskWeatherRequest, now: Date, calendar: Calendar) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        guard let startDay = calendar.date(byAdding: .day, value: request.dayOffset, to: today) else { return nil }
        guard let end = calendar.date(byAdding: .day, value: request.dayCount, to: startDay) else { return nil }
        if request.span == .hourly {
            let raw = calendar.isDate(startDay, inSameDayAs: now) ? now : startDay
            let parts = calendar.dateComponents([.year, .month, .day, .hour], from: raw)
            guard let start = calendar.date(from: parts), start < end else { return nil }
            return DateInterval(start: start, end: end)
        }
        // Midnight today is already in the past. WeatherKit rejects that start.
        let start = startDay < now ? now : startDay
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Empty or the wrong shape is read again. A denial is left alone.
    static func needsReread(_ request: AskWeatherRequest, lines: [String]) -> Bool {
        if lines.contains(where: { settled.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
            return false
        }
        if !request.place.isEmpty {
            let want = AskAppleCopy.folded(request.place)
            let named = lines.contains { AskAppleCopy.folded($0).contains(want) }
            if !named { return true }
        }
        let days = lines.compactMap(AskWeatherLine.day(from:))
        let hours = lines.contains { AskWeatherLine.hour(from: $0) != nil }
        switch request.span {
        case .hourly:
            return !hours
        case .daily:
            if hours { return true }
            return days.count != request.dayCount
        }
    }

    static func isHourly(_ question: String) -> Bool {
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        return tokens.contains("hourly") || tokens.contains("hour") || tokens.contains("hours")
    }

    private static let settled: Set<String> = [
        AskAppleCopy.denied,
        "Location is unavailable.",
        "No forecast.",
        "No matching place."
    ]
}

struct AskWeatherRequest: Equatable, Sendable {
    var span: AskWeatherQuery.Span
    var dayOffset: Int
    var dayCount: Int
    /// Empty uses the device. A city from the question is geocoded.
    var place: String = ""
}

/// One day, plus the hours when the question asked for them. Lines never contain `=`.
package enum AskWeatherLine {
    package struct Day: Equatable, Sendable {
        package init(title: String, symbol: String, condition: String, high: String, low: String, rain: String) {
            self.title = title
            self.symbol = symbol
            self.condition = condition
            self.high = high
            self.low = low
            self.rain = rain
        }

        package var title: String
        package var symbol: String
        package var condition: String
        package var high: String
        package var low: String
        package var rain: String

        /// Words for Copy, Share, and the trace picture. The spoken rewrite stays off this text.
        var shareText: String {
            var lines = [title, condition, "High \(high)", "Low \(low)"]
            if !rain.isEmpty { lines.append("Rain \(rain)") }
            return lines.filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    package struct Hour: Equatable, Sendable {
        package var time: String
        package var symbol: String
        package var condition: String
        package var temperature: String
        package var rain: String
    }

    package struct Forecast: Equatable, Sendable {
        package var day: Day
        package var hours: [Hour]
        /// Every day on this forecast. A week stays on one card.
        package var days: [Day]
        package var place: String

        package init(day: Day, hours: [Hour] = [], days: [Day] = [], place: String = "") {
            let listed = days.isEmpty ? [day] : days
            self.day = listed[0]
            self.hours = hours
            self.days = listed
            self.place = place
        }

        var shareText: String {
            var lines = days.map(\.shareText)
            let name = AskWeatherLine.displayPlace(place)
            if !name.isEmpty { lines.insert(name, at: 0) }
            lines.append(contentsOf: hours.map { "\($0.time) \($0.temperature)".trimmingCharacters(in: .whitespaces) })
            return lines.filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    package static func dayLine(title: String, symbol: String, condition: String, high: String, low: String, rain: String) -> String {
        [
            "Day: \(clean(title))",
            symbolName(symbol),
            clean(condition).isEmpty ? "Unknown" : clean(condition),
            "High \(clean(high))",
            "Low \(clean(low))",
            "Rain \(clean(rain))"
        ].joined(separator: " · ")
    }

    package static func hourLine(time: String, symbol: String, condition: String, temperature: String, rain: String) -> String {
        [
            "Hour: \(clean(time))",
            symbolName(symbol),
            clean(condition).isEmpty ? "Unknown" : clean(condition),
            clean(temperature),
            "Rain \(clean(rain))"
        ].joined(separator: " · ")
    }

    static func day(from line: String) -> Day? {
        guard let parts = fields(line, prefix: "Day:"), parts.count >= 6 else { return nil }
        guard !parts[0].isEmpty else { return nil }
        return Day(
            title: parts[0],
            symbol: symbolName(parts[1]),
            condition: parts[2],
            high: labeled(parts[3], dropping: "High"),
            low: labeled(parts[4], dropping: "Low"),
            rain: labeled(parts[5], dropping: "Rain")
        )
    }

    static func hour(from line: String) -> Hour? {
        guard let parts = fields(line, prefix: "Hour:"), parts.count >= 5 else { return nil }
        guard !parts[0].isEmpty else { return nil }
        return Hour(
            time: parts[0],
            symbol: symbolName(parts[1]),
            condition: parts[2],
            temperature: parts[3],
            rain: labeled(parts[4], dropping: "Rain")
        )
    }

    package static func forecast(from lines: [String]) -> Forecast? {
        let days = lines.compactMap(day(from:))
        guard let day = days.first else { return nil }
        return Forecast(day: day, hours: lines.compactMap(hour(from:)), days: days, place: place(from: lines))
    }

    static func place(from lines: [String]) -> String {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("place:") else { continue }
            return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    package static func displayPlace(_ place: String) -> String {
        place.split(separator: " ").map { word in
            let text = String(word)
            guard let first = text.first else { return text }
            return first.uppercased() + text.dropFirst()
        }.joined(separator: " ")
    }

    /// One or two sentences. The cards keep each day and each hour.
    static func spoken(_ lines: [String]) -> String? {
        let days = lines.compactMap(day(from:))
        guard let first = days.first else { return nil }
        let hours = lines.compactMap(hour(from:))
        if let hour = hours.first {
            let condition = hour.condition == "Unknown" ? "" : ", \(hour.condition)"
            return "Hourly forecast for \(first.title). \(hour.time) is \(hour.temperature)\(condition)."
        }
        let condition = first.condition == "Unknown" ? "" : " is \(first.condition)"
        if days.count == 1 {
            return "\(first.title)\(condition). High \(first.high). Low \(first.low)."
        }
        return "\(days.count) day forecast. \(first.title)\(condition). High \(first.high)."
    }

    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "=", with: " ")
            .replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func temperature(_ measurement: Measurement<UnitTemperature>) -> String {
        let metric = Locale.current.measurementSystem == .metric
        let unit: UnitTemperature = metric ? .celsius : .fahrenheit
        let letter = metric ? "C" : "F"
        let value = Int(measurement.converted(to: unit).value.rounded())
        return "\(value) \(letter)"
    }

    static func percent(_ chance: Double) -> String {
        let value = Int((chance * 100).rounded())
        let clamped = min(max(value, 0), 100)
        return "\(clamped) percent"
    }

    static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        date.formatted(dayStyle(calendar))
    }

    static func hourTitle(_ date: Date, calendar: Calendar) -> String {
        date.formatted(hourStyle(calendar))
    }

    private static func dayStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            locale: calendar.locale ?? .autoupdatingCurrent,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()
    }

    private static func hourStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            locale: calendar.locale ?? .autoupdatingCurrent,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .hour()
        .minute()
    }

    private static func fields(_ line: String, prefix: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func labeled(_ text: String, dropping prefix: String) -> String {
        guard text.hasPrefix(prefix) else { return text }
        return text.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func symbolName(_ raw: String) -> String {
        let cleaned = clean(raw)
        if cleaned.isEmpty || cleaned.contains(" ") { return "cloud.sun" }
        return cleaned
    }
}

/// The forecast where the person is. Location permission is the same prompt the map uses.
enum AskWeatherRead {
    static func lines(_ request: AskWeatherRequest, now: Date = Date(), calendar: Calendar = .current) async -> String {
        guard let window = AskWeatherQuery.interval(for: request, now: now, calendar: calendar) else {
            return "Weather isn't available."
        }
        let location: CLLocation
        if !request.place.isEmpty {
            guard let found = await AskLocationRead.coordinate(forPlace: request.place) else {
                return "No matching place."
            }
            location = found
        } else {
            switch await AskLocationRead.deviceFix() {
            case .denied:
                return AskAppleCopy.denied
            case .unavailable:
                return "Location is unavailable."
            case .fix(let fix):
                location = fix
            }
        }
        return await forecast(request, location: location, window: window, calendar: calendar)
    }

    private static func forecast(
        _ request: AskWeatherRequest,
        location: CLLocation,
        window: DateInterval,
        calendar: Calendar
    ) async -> String {
        do {
            if request.span == .hourly && request.dayOffset == 0 {
                let weather = try await WeatherService.shared.weather(for: location)
                let hours = weather.hourlyForecast.forecast.filter { window.contains($0.date) }
                let day = weather.dailyForecast.forecast.first { includes($0.date, window: window, calendar: calendar) }
                let text = hourlyLines(
                    day: day,
                    hours: Array(hours.prefix(AskWeatherQuery.maximumHours)),
                    calendar: calendar
                )
                return labeled(text, place: request.place)
            }
            if request.span == .hourly {
                let dayStart = max(calendar.startOfDay(for: window.start), Date())
                let (daily, hourly) = try await WeatherService.shared.weather(
                    for: location,
                    including: WeatherQuery.daily(startDate: dayStart, endDate: window.end),
                    WeatherQuery.hourly(startDate: window.start, endDate: window.end)
                )
                let text = hourlyLines(
                    day: daily.forecast.first,
                    hours: Array(hourly.forecast.prefix(AskWeatherQuery.maximumHours)),
                    calendar: calendar
                )
                return labeled(text, place: request.place)
            }
            let weather = try await WeatherService.shared.weather(for: location)
            let days = weather.dailyForecast.forecast.filter { includes($0.date, window: window, calendar: calendar) }
            let lines = days.prefix(request.dayCount).map { dayLine($0, calendar: calendar) }
            let text = lines.isEmpty ? "No forecast." : lines.joined(separator: "\n")
            return labeled(text, place: request.place)
        } catch let error as WeatherError where error == .permissionDenied {
            return AskAppleCopy.denied
        } catch {
            let reason = String(describing: error).replacingOccurrences(of: "=", with: " ")
            AskTrace.attribute("weatherError", String(reason.prefix(160)))
            return "Weather isn't available."
        }
    }

    /// A day forecast belongs to the requested window. The day's own date is the start of that day.
    private static func includes(_ date: Date, window: DateInterval, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        let first = calendar.startOfDay(for: window.start)
        return day >= first && day < window.end
    }

    /// Names the city on the tool line so a device forecast is not kept for a named place.
    private static func labeled(_ body: String, place: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = AskWeatherLine.clean(place)
        guard !name.isEmpty else { return trimmed }
        let quiet: Set<String> = [
            AskAppleCopy.denied,
            "Location is unavailable.",
            "Weather isn't available.",
            "No forecast.",
            "No matching place."
        ]
        if quiet.contains(trimmed) { return trimmed }
        return "Place: \(name)\n\(trimmed)"
    }

    private static func hourlyLines(day: DayWeather?, hours: [HourWeather], calendar: Calendar) -> String {
        guard day != nil || !hours.isEmpty else { return "No forecast." }
        let sample = hours.first
        let anchor = day?.date ?? sample?.date ?? Date()
        let header = AskWeatherLine.dayLine(
            title: AskWeatherLine.dayTitle(anchor, calendar: calendar),
            symbol: day?.symbolName ?? sample?.symbolName ?? "",
            condition: day?.condition.description ?? sample?.condition.description ?? "",
            high: day.map { AskWeatherLine.temperature($0.highTemperature) } ?? extreme(hours, highest: true),
            low: day.map { AskWeatherLine.temperature($0.lowTemperature) } ?? extreme(hours, highest: false),
            rain: AskWeatherLine.percent(day?.precipitationChance ?? sample?.precipitationChance ?? 0)
        )
        let rows = hours.prefix(AskWeatherQuery.maximumHours).map { hour in
            AskWeatherLine.hourLine(
                time: AskWeatherLine.hourTitle(hour.date, calendar: calendar),
                symbol: hour.symbolName,
                condition: hour.condition.description,
                temperature: AskWeatherLine.temperature(hour.temperature),
                rain: AskWeatherLine.percent(hour.precipitationChance)
            )
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func extreme(_ hours: [HourWeather], highest: Bool) -> String {
        guard let first = hours.first else { return "" }
        let picked = hours.dropFirst().reduce(first) { current, hour in
            let left = current.temperature.converted(to: .celsius).value
            let right = hour.temperature.converted(to: .celsius).value
            if highest {
                return right > left ? hour : current
            }
            return right < left ? hour : current
        }
        return AskWeatherLine.temperature(picked.temperature)
    }

    private static func dayLine(_ day: DayWeather, calendar: Calendar) -> String {
        AskWeatherLine.dayLine(
            title: AskWeatherLine.dayTitle(day.date, calendar: calendar),
            symbol: day.symbolName,
            condition: day.condition.description,
            high: AskWeatherLine.temperature(day.highTemperature),
            low: AskWeatherLine.temperature(day.lowTemperature),
            rain: AskWeatherLine.percent(day.precipitationChance)
        )
    }
}

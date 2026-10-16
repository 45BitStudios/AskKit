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
enum AskWeatherLine {
    struct Day: Equatable, Sendable {
        var title: String
        var symbol: String
        var condition: String
        var high: String
        var low: String
        var rain: String

        /// Words for Copy, Share, and the trace picture. The spoken rewrite stays off this text.
        var shareText: String {
            var lines = [title, condition, "High \(high)", "Low \(low)"]
            if !rain.isEmpty { lines.append("Rain \(rain)") }
            return lines.filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    struct Hour: Equatable, Sendable {
        var time: String
        var symbol: String
        var condition: String
        var temperature: String
        var rain: String
    }

    struct Forecast: Equatable, Sendable {
        var day: Day
        var hours: [Hour]
        /// Every day on this forecast. A week stays on one card.
        var days: [Day]
        var place: String

        init(day: Day, hours: [Hour] = [], days: [Day] = [], place: String = "") {
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

    static func dayLine(title: String, symbol: String, condition: String, high: String, low: String, rain: String) -> String {
        [
            "Day: \(clean(title))",
            symbolName(symbol),
            clean(condition).isEmpty ? "Unknown" : clean(condition),
            "High \(clean(high))",
            "Low \(clean(low))",
            "Rain \(clean(rain))"
        ].joined(separator: " · ")
    }

    static func hourLine(time: String, symbol: String, condition: String, temperature: String, rain: String) -> String {
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

    static func forecast(from lines: [String]) -> Forecast? {
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

    static func displayPlace(_ place: String) -> String {
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

/// One forecast. A week lists each day here. Hours stay on a single day's card.
/// The Apple Weather mark links to the legal page. The data-source list stays on that page.
struct AskWeatherCard: View {
    var forecast: AskWeatherLine.Forecast
    /// Sample cards keep the Apple Weather credit and do not call WeatherKit.
    var loadsCredit: Bool = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.askCardStyle) private var style
    @State private var mark: URL?
    @State private var legal: URL?

    private var showsWeek: Bool { forecast.days.count > 1 }

    /// Snippet keeps a short week. Chat and full screen show every day.
    private var visibleDays: [AskWeatherLine.Day] {
        let days = forecast.days
        guard style == .snippet, days.count > 3 else { return days }
        return Array(days.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .fullScreen ? 18 : 14) {
            AskCardMark(
                title: "Forecast",
                symbol: AskWeatherPalette.badgeSymbol(forecast.day.symbol),
                tint: AskWeatherTint.color(for: forecast.day.symbol)
            )
            if showsWeek, style == .fullScreen {
                Text(weekTitle)
                    .font(style.titleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ForEach(Array(visibleDays.enumerated()), id: \.offset) { _, day in
                    AskWeatherDayRow(day: day)
                }
            } else if showsWeek, let day = forecast.days.first {
                AskWeatherCompactDay(day: day)
            } else {
                AskWeatherCompactDay(day: forecast.day)
                if style == .fullScreen, !forecast.hours.isEmpty {
                    AskWeatherHourGrid(hours: forecast.hours)
                }
            }
            if style == .fullScreen {
                attribution
            }
        }
        .askCardSurface()
        .task(id: scheme) {
            guard loadsCredit, style == .fullScreen else { return }
            await loadAttribution()
        }
    }

    private var weekTitle: String {
        let place = AskWeatherLine.displayPlace(forecast.place)
        return place.isEmpty ? "Forecast" : place
    }

    @ViewBuilder
    private var attribution: some View {
        if let legal {
            Link(destination: legal) {
                attributionLabel
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else {
            attributionLabel
        }
    }

    private var attributionLabel: some View {
        HStack(spacing: 8) {
            if let mark {
                AsyncImage(url: mark) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 24, height: 16)
                .accessibilityHidden(true)
            }
            Text("Apple Weather")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadAttribution() async {
        guard let attribution = try? await WeatherService.shared.attribution else { return }
        mark = scheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL
        legal = attribution.legalPageURL
    }
}

private enum AskWeatherTint {
    static func color(for symbol: String) -> Color {
        let name = symbol.lowercased()
        if name.contains("bolt") || name.contains("storm") { return .purple }
        if name.contains("snow") { return .cyan }
        if name.contains("rain") || name.contains("drizzle") { return .blue }
        if name.contains("sun") && !name.contains("cloud") { return .orange }
        if name.contains("wind") { return .teal }
        return .blue
    }
}

private struct AskWeatherCompactDay: View {
    var day: AskWeatherLine.Day

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !day.condition.isEmpty, day.condition != "Unknown" {
                Text(day.condition)
                    .font(.title3.weight(.semibold))
            }
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                if !day.high.isEmpty {
                    AskWeatherReading(label: "High", value: day.high)
                }
                if !day.low.isEmpty {
                    AskWeatherReading(label: "Low", value: day.low)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AskWeatherDayRow: View {
    var day: AskWeatherLine.Day

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AskWeatherSymbol(name: day.symbol, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !day.condition.isEmpty, day.condition != "Unknown" {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                if !day.high.isEmpty {
                    Text(day.high)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                if !day.low.isEmpty {
                    Text(day.low)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard !day.rain.isEmpty, day.rain != "0 percent" else { return day.condition }
        return "\(day.condition) · \(day.rain) rain"
    }
}

private struct AskWeatherReading: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Palette colors, not a single tint. Resizing an SF Symbol flattens it to black.
private struct AskWeatherSymbol: View {
    var name: String
    var size: CGFloat

    var body: some View {
        painted
            .font(.system(size: size))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var painted: some View {
        let image = Image(systemName: name).symbolRenderingMode(.palette)
        switch AskWeatherPalette.kind(for: name) {
        case .sun:
            image.foregroundStyle(Color.yellow, Color.orange)
        case .moon:
            image.foregroundStyle(Color.yellow, Color.indigo)
        case .cloudSun:
            image.foregroundStyle(AskWeatherPalette.cloud, Color.yellow)
        case .cloudMoon:
            image.foregroundStyle(AskWeatherPalette.cloud, Color.yellow)
        case .rain:
            image.foregroundStyle(AskWeatherPalette.cloud, Color.blue)
        case .cloudSunRain:
            image.foregroundStyle(AskWeatherPalette.cloud, Color.yellow, Color.blue)
        case .bolt:
            image.foregroundStyle(AskWeatherPalette.cloud, Color.yellow)
        case .boltRain:
            image.foregroundStyle(AskWeatherPalette.cloud, Color.yellow, Color.blue)
        case .snow:
            image.foregroundStyle(AskWeatherPalette.cloud, Color.cyan)
        case .cloud:
            image.foregroundStyle(AskWeatherPalette.cloud)
        case .wind:
            image.foregroundStyle(Color.teal)
        }
    }
}

enum AskWeatherPalette {
    /// Slate, dark enough to read on the pale forecast card. The sun and rain stay their own colors.
    static let cloud = Color(red: 0.27, green: 0.34, blue: 0.42)

    enum Kind {
        case sun, moon, cloudSun, cloudMoon, rain, cloudSunRain, bolt, boltRain, snow, cloud, wind
    }

    static func kind(for symbol: String) -> Kind {
        let name = symbol.lowercased()
        if name.contains("wind") { return .wind }
        if name.contains("bolt") && (name.contains("rain") || name.contains("drizzle")) { return .boltRain }
        if name.contains("bolt") || name.contains("storm") { return .bolt }
        if name.contains("snow") || name.contains("sleet") || name.contains("hail") { return .snow }
        let wet = name.contains("rain") || name.contains("drizzle")
        if wet && name.contains("sun") { return .cloudSunRain }
        if wet && name.contains("moon") { return .cloudMoon }
        if wet { return .rain }
        if name.contains("sun") && name.contains("cloud") { return .cloudSun }
        if name.contains("moon") && name.contains("cloud") { return .cloudMoon }
        if name.contains("sun") { return .sun }
        if name.contains("moon") { return .moon }
        return .cloud
    }

    /// A filled mark stays legible at chip size. Outline weather symbols turn into hairlines.
    static func badgeSymbol(_ name: String) -> String {
        name.hasSuffix(".fill") ? name : "\(name).fill"
    }
}

private struct AskWeatherHourGrid: View {
    var hours: [AskWeatherLine.Hour]

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                AskWeatherHourColumn(hour: hour)
            }
        }
    }
}

private struct AskWeatherHourColumn: View {
    var hour: AskWeatherLine.Hour

    var body: some View {
        VStack(spacing: 6) {
            Text(hour.time)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            AskWeatherSymbol(name: hour.symbol, size: 28)
            Text(hour.temperature)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(hour.condition == "Unknown" ? rainShort : hour.condition)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var rainShort: String {
        let digits = hour.rain.prefix { $0.isNumber }
        guard !digits.isEmpty else { return "\(hour.rain) rain" }
        return "\(digits)% rain"
    }
}

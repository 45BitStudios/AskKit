import AppIntents
import Charts
import Foundation
import SwiftUI

/// Day, week, month, or year. Raw values stay stable for saved shortcuts.
public enum AskHealthRange: String, AppEnum, CaseIterable, Sendable {
    case day = "day"
    case week = "week"
    case month = "month"
    case year = "year"

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Health Range")

    public static let caseDisplayRepresentations: [AskHealthRange: DisplayRepresentation] = [
        .day: "Day",
        .week: "Week",
        .month: "Month",
        .year: "Year"
    ]

    package var controlTitle: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    package var spokenName: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }

    package var xTitle: String {
        switch self {
        case .day: "Hour"
        case .week, .month: "Day"
        case .year: "Month"
        }
    }

    package var bucket: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        }
    }

    var interval: DateComponents {
        switch self {
        case .day: DateComponents(hour: 1)
        case .week, .month: DateComponents(day: 1)
        case .year: DateComponents(month: 1)
        }
    }

    package var xFormat: Date.FormatStyle {
        switch self {
        case .day:
            Date.FormatStyle(date: .omitted, time: .shortened)
        case .week:
            Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated)
        case .month:
            Date.FormatStyle(date: .omitted, time: .omitted).day()
        case .year:
            Date.FormatStyle(date: .omitted, time: .omitted).month(.abbreviated)
        }
    }
}

/// The measurements the health card can chart. Raw values stay stable for saved shortcuts.
public enum AskHealthMeasurement: String, AppEnum, Sendable {
    case steps = "steps"
    case heart = "heart"
    case energy = "energy"
    case distance = "distance"
    case flights = "flights"
    case exercise = "exercise"
    case weight = "weight"
    case height = "height"
    case bodyFat = "bodyFat"
    case restingHeart = "restingHeart"
    case bloodPressure = "bloodPressure"
    case glucose = "glucose"
    case oxygen = "oxygen"
    case temperature = "temperature"
    case breathing = "breathing"
    case vo2 = "vo2"

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Health Measurement")

    public static let caseDisplayRepresentations: [AskHealthMeasurement: DisplayRepresentation] = [
        .steps: "Steps",
        .heart: "Heart Rate",
        .energy: "Active Energy",
        .distance: "Walking Distance",
        .flights: "Flights Climbed",
        .exercise: "Exercise",
        .weight: "Weight",
        .height: "Height",
        .bodyFat: "Body Fat",
        .restingHeart: "Resting Heart Rate",
        .bloodPressure: "Blood Pressure",
        .glucose: "Blood Glucose",
        .oxygen: "Oxygen",
        .temperature: "Temperature",
        .breathing: "Breathing Rate",
        .vo2: "VO2 Max"
    ]

    package var spokenName: String {
        switch self {
        case .steps: "steps"
        case .heart: "heart rate"
        case .energy: "active energy"
        case .distance: "walking distance"
        case .flights: "flights climbed"
        case .exercise: "exercise"
        case .weight: "weight"
        case .height: "height"
        case .bodyFat: "body fat"
        case .restingHeart: "resting heart rate"
        case .bloodPressure: "blood pressure"
        case .glucose: "blood glucose"
        case .oxygen: "oxygen"
        case .temperature: "temperature"
        case .breathing: "breathing rate"
        case .vo2: "VO2 max"
        }
    }
}

package enum AskHealthChartKind: String, Equatable, Sendable {
    case bar
    case line
}

package struct AskHealthRangeChoice: Equatable, Sendable {
    var range: AskHealthRange
    var at: Date
}

struct AskHealthClaim: Equatable, Sendable {
    var id: UUID
    var opened: Date
}

/// The range a health card is showing. A newer card for the same measurement wins.
@MainActor
@Observable
package final class AskHealthRanges {
    package static let shared = AskHealthRanges()

    package private(set) var choices: [String: AskHealthRangeChoice] = [:]
    private(set) var claims: [String: AskHealthClaim] = [:]

    /// Ignores an older card, including one that appears again while scrolling.
    package func claim(metric: String, id: UUID, opened: Date) {
        if let current = claims[metric], current.opened >= opened { return }
        claims[metric] = AskHealthClaim(id: id, opened: opened)
    }

    package func select(metric: String, range: AskHealthRange) {
        choices[metric] = AskHealthRangeChoice(range: range, at: Date())
    }

    package func activeID(for metric: String) -> UUID? {
        claims[metric]?.id
    }
}

struct AskHealthWindow: Equatable, Sendable {
    var start: Date
    var end: Date
}

/// Bucket starts for a health chart. Tests use this instead of HealthKit.
package enum AskHealthBuckets {
    package static func dates(range: AskHealthRange, now: Date, calendar: Calendar) -> [Date] {
        switch range {
        case .day:
            let start = calendar.startOfDay(for: now)
            return (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: start) }
        case .week:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .month:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))
                ?? calendar.startOfDay(for: now)
            let count = calendar.component(.day, from: now)
            return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .year:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now))
                ?? calendar.startOfDay(for: now)
            return (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
        }
    }

    static func window(range: AskHealthRange, now: Date, calendar: Calendar) -> AskHealthWindow? {
        let dates = dates(range: range, now: now, calendar: calendar)
        guard let start = dates.first, let last = dates.last else { return nil }
        let end = calendar.date(byAdding: range.bucket, value: 1, to: last) ?? now
        return AskHealthWindow(start: start, end: end)
    }

    /// Start of the summary query. Week is the last seven days, including today.
    static func start(span: String, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch span {
        case "week":
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case "month":
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
        case "year":
            return calendar.date(from: calendar.dateComponents([.year], from: now)) ?? today
        default:
            return today
        }
    }
}

package struct AskHealthPoint: Identifiable, Equatable, Sendable {
    package init(id: String, date: Date, value: Double, recorded: Bool) {
        self.id = id
        self.date = date
        self.value = value
        self.recorded = recorded
    }

    package var id: String
    package var date: Date
    package var value: Double
    package var recorded: Bool
}

package struct AskHealthSeriesSnapshot: Equatable, Sendable {
    package init(points: [AskHealthPoint], headline: String, axisLabel: String, denied: Bool, recorded: Bool) {
        self.points = points
        self.headline = headline
        self.axisLabel = axisLabel
        self.denied = denied
        self.recorded = recorded
    }

    package var points: [AskHealthPoint]
    package var headline: String
    package var axisLabel: String
    package var denied: Bool
    package var recorded: Bool

    static func unavailable(_ axis: String) -> AskHealthSeriesSnapshot {
        AskHealthSeriesSnapshot(points: [], headline: "Not allowed.", axisLabel: axis, denied: true, recorded: false)
    }

    static func empty(_ axis: String) -> AskHealthSeriesSnapshot {
        AskHealthSeriesSnapshot(points: [], headline: "Nothing recorded.", axisLabel: axis, denied: false, recorded: false)
    }
}

/// Which measurement to chart, and the range the question asked for.
package struct AskHealthChartModel: Equatable, Sendable {
    package var metric: AskHealthCatalog.Metric
    package var range: AskHealthRange

    package static func parse(_ lines: [String]) -> AskHealthChartModel? {
        for line in lines {
            if let metric = metric(in: line) {
                return AskHealthChartModel(metric: metric, range: range(in: line))
            }
        }
        return nil
    }

    package static func metric(in line: String) -> AskHealthCatalog.Metric? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let title = trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        return AskHealthCatalog.Metric.allCases.first { $0.title.compare(title, options: .caseInsensitive) == .orderedSame }
    }

    package static func range(in line: String) -> AskHealthRange {
        let folded = AskAppleCopy.folded(line)
        if folded.localizedStandardContains("this year") { return .year }
        if folded.localizedStandardContains("this month") { return .month }
        if folded.localizedStandardContains("this week") { return .week }
        return .day
    }

    package static func value(in line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return trimmed }
        return trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A choice from before this card existed belongs to an earlier answer.
    static func displayed(initial: AskHealthRange, choice: AskHealthRangeChoice?, opened: Date) -> AskHealthRange {
        follows(choice: choice, opened: opened, active: true) ?? initial
    }

    package static func follows(choice: AskHealthRangeChoice?, opened: Date, active: Bool) -> AskHealthRange? {
        guard active, let choice, choice.at >= opened else { return nil }
        return choice.range
    }

    /// A shortcut snippet is a new view on every refresh. The button's choice applies even when it is older than that view.
    package static func snippetRange(initial: AskHealthRange, choice: AskHealthRangeChoice?) -> AskHealthRange {
        choice?.range ?? initial
    }
}

/// Spoken summary for a health chart. VoiceOver reads this instead of the drawn marks.
package enum AskHealthChartSummary {
    package static func spoken(title: String, range: String, headline: String, values: [Double]) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let span = range.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !name.isEmpty, !span.isEmpty {
            parts.append("\(name) for the \(span)")
        } else if !name.isEmpty {
            parts.append(name)
        } else if !span.isEmpty {
            parts.append(span)
        }
        if !value.isEmpty { parts.append(value) }
        if let low = values.min(), let high = values.max(), !values.isEmpty {
            let lowText = format(low)
            let highText = format(high)
            if lowText != highText {
                parts.append(
                    String(
                        localized: "Low \(lowText), high \(highText)",
                        comment: "VoiceOver summary of a health chart. The first value is the lowest point and the second is the highest."
                    )
                )
            }
        }
        return parts.joined(separator: ". ")
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

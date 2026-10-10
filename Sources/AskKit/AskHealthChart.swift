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

    var controlTitle: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var spokenName: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }

    var xTitle: String {
        switch self {
        case .day: "Hour"
        case .week, .month: "Day"
        case .year: "Month"
        }
    }

    var bucket: Calendar.Component {
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

    var xFormat: Date.FormatStyle {
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
        .glucose: "Blood Glucose",
        .oxygen: "Oxygen",
        .temperature: "Temperature",
        .breathing: "Breathing Rate",
        .vo2: "VO2 Max"
    ]

    var spokenName: String {
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
        case .glucose: "blood glucose"
        case .oxygen: "oxygen"
        case .temperature: "temperature"
        case .breathing: "breathing rate"
        case .vo2: "VO2 max"
        }
    }
}

enum AskHealthChartKind: String, Equatable, Sendable {
    case bar
    case line
}

struct AskHealthRangeChoice: Equatable, Sendable {
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
final class AskHealthRanges {
    static let shared = AskHealthRanges()

    private(set) var choices: [String: AskHealthRangeChoice] = [:]
    private(set) var claims: [String: AskHealthClaim] = [:]

    /// Ignores an older card, including one that appears again while scrolling.
    func claim(metric: String, id: UUID, opened: Date) {
        if let current = claims[metric], current.opened >= opened { return }
        claims[metric] = AskHealthClaim(id: id, opened: opened)
    }

    func select(metric: String, range: AskHealthRange) {
        choices[metric] = AskHealthRangeChoice(range: range, at: Date())
    }

    func activeID(for metric: String) -> UUID? {
        claims[metric]?.id
    }
}

/// Shows one measurement for a day, week, month, or year. Siri and the Show Health shortcut run this and speak the result.
public struct ShowAskHealthRangeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Health Range"
    public static let description = IntentDescription("Shows a health measurement for a day, week, month, or year.")

    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Measurement")
    public var measurement: AskHealthMeasurement

    @Parameter(title: "Range")
    public var range: AskHealthRange

    public static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$measurement) for \(\.$range)")
    }

    public init() {}

    public init(measurement: AskHealthMeasurement, range: AskHealthRange) {
        self.measurement = measurement
        self.range = range
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let chosen = measurement
        let chosenRange = range
        let name = chosen.spokenName
        let period = chosenRange.spokenName
        await AskHealthRangeApply.select(metric: chosen.rawValue, range: chosenRange)
        return .result(dialog: "Showing \(name) for the \(period).")
    }
}

/// Day, Week, Month, and Year on the chart. A dialog would open a second shortcut window, so this only stores the choice and the snippet redraws.
struct AskHealthRangeTap: AppIntent {
    static let title: LocalizedStringResource = "Show Health Range"
    static let isDiscoverable = false

    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Measurement")
    var measurement: AskHealthMeasurement

    @Parameter(title: "Range")
    var range: AskHealthRange

    init() {}

    init(measurement: AskHealthMeasurement, range: AskHealthRange) {
        self.measurement = measurement
        self.range = range
    }

    func perform() async throws -> some IntentResult {
        let chosen = measurement
        let chosenRange = range
        await AskHealthRangeApply.select(metric: chosen.rawValue, range: chosenRange)
        return .result()
    }
}

private enum AskHealthRangeApply {
    static func select(metric: String, range: AskHealthRange) async {
        await MainActor.run {
            AskHealthRanges.shared.select(metric: metric, range: range)
        }
    }
}

struct AskHealthWindow: Equatable, Sendable {
    var start: Date
    var end: Date
}

/// Bucket starts for a health chart. Tests use this instead of HealthKit.
enum AskHealthBuckets {
    static func dates(range: AskHealthRange, now: Date, calendar: Calendar) -> [Date] {
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

struct AskHealthPoint: Identifiable, Equatable, Sendable {
    var id: String
    var date: Date
    var value: Double
    var recorded: Bool
}

struct AskHealthSeriesSnapshot: Equatable, Sendable {
    var points: [AskHealthPoint]
    var headline: String
    var axisLabel: String
    var denied: Bool
    var recorded: Bool

    static func unavailable(_ axis: String) -> AskHealthSeriesSnapshot {
        AskHealthSeriesSnapshot(points: [], headline: "Not allowed.", axisLabel: axis, denied: true, recorded: false)
    }

    static func empty(_ axis: String) -> AskHealthSeriesSnapshot {
        AskHealthSeriesSnapshot(points: [], headline: "Nothing recorded.", axisLabel: axis, denied: false, recorded: false)
    }
}

/// Which measurement to chart, and the range the question asked for.
struct AskHealthChartModel: Equatable, Sendable {
    var metric: AskHealthCatalog.Metric
    var range: AskHealthRange

    static func parse(_ lines: [String]) -> AskHealthChartModel? {
        for line in lines {
            if let metric = metric(in: line) {
                return AskHealthChartModel(metric: metric, range: range(in: line))
            }
        }
        return nil
    }

    static func metric(in line: String) -> AskHealthCatalog.Metric? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let title = trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        return AskHealthCatalog.Metric.allCases.first { $0.title.compare(title, options: .caseInsensitive) == .orderedSame }
    }

    static func range(in line: String) -> AskHealthRange {
        let folded = AskAppleCopy.folded(line)
        if folded.localizedStandardContains("this year") { return .year }
        if folded.localizedStandardContains("this month") { return .month }
        if folded.localizedStandardContains("this week") { return .week }
        return .day
    }

    static func value(in line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return trimmed }
        return trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A choice from before this card existed belongs to an earlier answer.
    static func displayed(initial: AskHealthRange, choice: AskHealthRangeChoice?, opened: Date) -> AskHealthRange {
        follows(choice: choice, opened: opened, active: true) ?? initial
    }

    static func follows(choice: AskHealthRangeChoice?, opened: Date, active: Bool) -> AskHealthRange? {
        guard active, let choice, choice.at >= opened else { return nil }
        return choice.range
    }

    /// A shortcut snippet is a new view on every refresh. The button's choice applies even when it is older than that view.
    static func snippetRange(initial: AskHealthRange, choice: AskHealthRangeChoice?) -> AskHealthRange {
        choice?.range ?? initial
    }
}

/// Steps and the other totals. Heart rate and samples use a line.
struct AskHealthChartCard: View {
    var metric: AskHealthCatalog.Metric
    var initial: AskHealthRange
    var lines: [String]
    /// Sample points for the card gallery. Nil reads HealthKit.
    var sampleSeries: ((AskHealthRange) -> AskHealthSeriesSnapshot)? = nil

    /// Captured once. A later answer gets a later date, so an older tap does not move it.
    @State private var opened = Date()
    @State private var cardID = UUID()
    @State private var pinned: AskHealthRange?
    @State private var snapshot: AskHealthSeriesSnapshot?
    @State private var loadedRange: AskHealthRange?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.askSnippet) private var snippet

    var body: some View {
        let prepared = snippet.health[metric.key]
        let active = AskHealthRanges.shared.activeID(for: metric.key) == cardID
        let choice = AskHealthRanges.shared.choices[metric.key]
        let live = AskHealthChartModel.follows(choice: choice, opened: opened, active: active)
        let range = prepared?.range ?? live ?? (active ? initial : (pinned ?? initial))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AskHealthFigure(text: headline(for: range), color: AskHealthColor.color(for: metric))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AskCardBadge(
                    title: metric.title,
                    symbol: AskHealthColor.symbol(for: metric),
                    tint: AskHealthColor.color(for: metric)
                )
            }
            AskHealthRangeControl(metric: metric, selected: range)
            AskHealthChartPlot(
                metric: metric,
                range: prepared?.range ?? loadedRange ?? range,
                snapshot: prepared?.series ?? snapshot,
                shapes: prepared != nil
            )
            AskHealthExtraLines(lines: extras)
        }
        .askCardSurface(tint: AskHealthColor.color(for: metric))
        .onAppear {
            guard prepared == nil else { return }
            AskHealthRanges.shared.claim(metric: metric.key, id: cardID, opened: opened)
        }
        .onChange(of: live ?? initial) { _, newValue in
            if active { pinned = newValue }
        }
        .task(id: range) {
            guard prepared == nil else { return }
            let requested = range
            if let sampleSeries {
                reveal(sampleSeries(requested), range: requested)
                return
            }
            let loaded = await AskHealthRead.series(metric: metric, range: requested)
            guard !Task.isCancelled else { return }
            reveal(loaded, range: requested)
        }
    }

    private func reveal(_ loaded: AskHealthSeriesSnapshot, range: AskHealthRange) {
        if reduceMotion {
            snapshot = loaded
            loadedRange = range
        } else {
            withAnimation(.smooth(duration: 0.55)) {
                snapshot = loaded
                loadedRange = range
            }
        }
    }

    private func headline(for range: AskHealthRange) -> String {
        if let prepared = snippet.health[metric.key], prepared.range == range {
            return prepared.series.headline
        }
        if loadedRange == range, let snapshot {
            return snapshot.headline
        }
        guard let line = lines.first(where: { AskHealthChartModel.metric(in: $0) == metric }) else {
            return "Nothing recorded."
        }
        return AskHealthChartModel.value(in: line)
    }

    private var extras: [String] {
        lines.filter { line in
            guard let found = AskHealthChartModel.metric(in: line) else {
                return !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return found != metric
        }
    }
}

private struct AskHealthRangeControl: View {
    var metric: AskHealthCatalog.Metric
    var selected: AskHealthRange

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AskHealthRange.allCases, id: \.rawValue) { item in
                AskHealthRangeButton(
                    metric: metric,
                    range: item,
                    selected: item == selected,
                    selection: selection
                )
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.65), in: Capsule())
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: selected)
        .accessibilityElement(children: .contain)
    }
}

private struct AskHealthRangeButton: View {
    var metric: AskHealthCatalog.Metric
    var range: AskHealthRange
    var selected: Bool
    var selection: Namespace.ID

    var body: some View {
        Button(intent: AskHealthRangeTap(measurement: metric.measurement, range: range)) {
            Text(range.controlTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if selected {
                        Capsule()
                            .fill(.background)
                            .matchedGeometryEffect(id: "health-range", in: selection)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AskHealthFigure: View {
    var text: String
    var color: Color

    @Environment(\.askSnippet) private var snippet

    var body: some View {
        if let split = splitNumber {
            if snippet.isSnippet {
                snippetLine(split)
            } else {
                chatLine(split)
            }
        } else {
            Text(text)
                .font(snippet.isSnippet ? .subheadline.weight(.semibold) : .title3.weight(.semibold))
                .lineLimit(snippet.isSnippet ? 2 : nil)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// One line. A large title breaks "189,125" after the comma in the shortcut card.
    private func snippetLine(_ split: (number: String, rest: String)) -> some View {
        let number = Text(split.number)
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(color)
        let rest = Text(split.rest)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        return Text("\(number)\u{00a0}\(rest)")
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func chatLine(_ split: (number: String, rest: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(split.number)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(split.rest)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var splitNumber: (number: String, rest: String)? {
        guard let space = text.firstIndex(of: " ") else { return nil }
        let number = String(text[..<space])
        guard number.contains(where: \.isNumber) else { return nil }
        let rest = String(text[text.index(after: space)...])
        guard !rest.isEmpty else { return nil }
        return (number, rest)
    }
}

private enum AskHealthColor {
    static func color(for metric: AskHealthCatalog.Metric) -> Color {
        switch metric {
        case .steps: .orange
        case .energy: .pink
        case .distance: .blue
        case .flights: .teal
        case .exercise: .green
        case .heart, .restingHeart: .pink
        case .weight: .indigo
        case .height: .blue
        case .bodyFat: .purple
        case .glucose: .red
        case .oxygen: .cyan
        case .temperature: .orange
        case .breathing: .mint
        case .vo2: .green
        }
    }

    static func symbol(for metric: AskHealthCatalog.Metric) -> String {
        switch metric {
        case .steps: "figure.walk"
        case .energy: "flame.fill"
        case .distance: "figure.walk.motion"
        case .flights: "figure.stairs"
        case .exercise: "figure.run"
        case .heart, .restingHeart: "heart.fill"
        case .weight: "scalemass.fill"
        case .height: "ruler"
        case .bodyFat: "percent"
        case .glucose: "drop.fill"
        case .oxygen: "lungs.fill"
        case .temperature: "thermometer.medium"
        case .breathing: "wind"
        case .vo2: "lungs.fill"
        }
    }
}

private struct AskHealthExtraLines: View {
    var lines: [String]

    var body: some View {
        if lines.isEmpty {
            EmptyView()
        } else {
            Text(lines.joined(separator: "\n"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AskHealthChartPlot: View {
    var metric: AskHealthCatalog.Metric
    var range: AskHealthRange
    var snapshot: AskHealthSeriesSnapshot?
    /// Shortcut snippets snapshot the view immediately. Swift Charts does not draw into that image, so the snippet uses shapes.
    var shapes = false

    var body: some View {
        if let snapshot {
            if snapshot.denied {
                AskHealthChartNote(text: "Health data isn't available.")
            } else if AskHealthCatalog.chartKind(for: metric) == .bar, !snapshot.points.isEmpty {
                if shapes {
                    AskHealthShapeChart(
                        points: snapshot.points,
                        range: range,
                        kind: .bar,
                        headline: snapshot.headline,
                        title: metric.title,
                        color: AskHealthColor.color(for: metric)
                    )
                } else {
                    AskHealthBarChart(
                        points: snapshot.points,
                        range: range,
                        axisLabel: snapshot.axisLabel,
                        headline: snapshot.headline,
                        title: metric.title,
                        color: AskHealthColor.color(for: metric)
                    )
                }
            } else {
                let recordedPoints = snapshot.points.filter(\.recorded)
                if snapshot.recorded, !recordedPoints.isEmpty {
                    if shapes {
                        AskHealthShapeChart(
                            points: recordedPoints,
                            range: range,
                            kind: .line,
                            headline: snapshot.headline,
                            title: metric.title,
                            color: AskHealthColor.color(for: metric)
                        )
                    } else {
                        AskHealthLineChart(
                            points: recordedPoints,
                            range: range,
                            axisLabel: snapshot.axisLabel,
                            headline: snapshot.headline,
                            title: metric.title,
                            color: AskHealthColor.color(for: metric)
                        )
                    }
                } else {
                    AskHealthChartNote(text: "Nothing recorded.")
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Loading chart")
        }
    }
}

private struct AskHealthChartNote: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private struct AskHealthBarChart: View {
    var points: [AskHealthPoint]
    var range: AskHealthRange
    var axisLabel: String
    var headline: String
    var title: String
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let peak = max(points.map(\.value).max() ?? 0, 1)
        Chart(points) { point in
            BarMark(
                x: .value("When", point.date, unit: range.bucket),
                y: .value("Value", point.value)
            )
            .foregroundStyle(color.gradient)
            .cornerRadius(5)
        }
        .chartYScale(domain: 0.0 ... peak * 1.08)
        .healthAxes(range: range, unit: axisLabel)
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: points.map(\.value))
        .frame(height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) for the \(range.spokenName)")
        .accessibilityValue(headline)
    }
}

private struct AskHealthLineChart: View {
    var points: [AskHealthPoint]
    var range: AskHealthRange
    var axisLabel: String
    var headline: String
    var title: String
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = max(values.max() ?? 1, low + 1)
        let pad = max((high - low) * 0.35, 1)
        Chart(points) { point in
            AreaMark(
                x: .value("When", point.date, unit: range.bucket),
                yStart: .value("Base", low - pad),
                yEnd: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.38), color.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
            LineMark(
                x: .value("When", point.date, unit: range.bucket),
                y: .value("Value", point.value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            PointMark(
                x: .value("When", point.date, unit: range.bucket),
                y: .value("Value", point.value)
            )
            .foregroundStyle(color)
            .symbolSize(36)
        }
        .chartYScale(domain: (low - pad) ... (high + pad))
        .healthAxes(range: range, unit: axisLabel)
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: points.map(\.value))
        .frame(height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) for the \(range.spokenName)")
        .accessibilityValue(headline)
    }
}

private extension View {
    func healthAxes(range: AskHealthRange, unit: String) -> some View {
        chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: range.xFormat)
                            .font(.caption2)
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number, format: .number.notation(.compactName))
                            .font(.caption2)
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .chartXAxisLabel(range.xTitle)
        .chartYAxisLabel(unit)
    }
}

/// Bars and a line drawn with shapes. A shortcut snippet captures the view before Swift Charts paints.
private struct AskHealthShapeChart: View {
    var points: [AskHealthPoint]
    var range: AskHealthRange
    var kind: AskHealthChartKind
    var headline: String
    var title: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if kind == .bar {
                    bars
                } else {
                    line
                }
            }
            .frame(height: 140)
            labels
        }
        .frame(height: 168)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) for the \(range.spokenName)")
        .accessibilityValue(headline)
    }

    private var bars: some View {
        let peak = max(points.map(\.value).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: points.count > 12 ? 2 : 4) {
            ForEach(points) { point in
                Capsule()
                    .fill(point.value > 0 ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.16)))
                    .frame(height: barHeight(point.value, peak: peak))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var line: some View {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = max(values.max() ?? 1, low + 1)
        let pad = max((high - low) * 0.35, 1)
        return AskHealthTrend(points: points, low: low - pad, high: high + pad, closes: false)
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .background {
                AskHealthTrend(points: points, low: low - pad, high: high + pad, closes: true)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.38), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                GeometryReader { geo in
                    let plot = AskHealthTrend.layout(points: points, low: low - pad, high: high + pad, in: geo.size)
                    ForEach(Array(plot.enumerated()), id: \.offset) { _, mark in
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                            .position(mark)
                    }
                }
            }
    }

    private var labels: some View {
        let indexes = labelIndexes(count: points.count)
        return HStack(spacing: 0) {
            ForEach(indexes, id: \.self) { index in
                if index != indexes.first { Spacer(minLength: 4) }
                Text(points[index].date, format: range.xFormat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func barHeight(_ value: Double, peak: Double) -> CGFloat {
        let plot: CGFloat = 140
        guard value > 0, peak > 0 else { return 4 }
        return max(plot * value / peak, 8)
    }

    private func labelIndexes(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= 7 { return Array(0..<count) }
        return [0, count / 2, count - 1]
    }
}

private struct AskHealthTrend: Shape {
    var points: [AskHealthPoint]
    var low: Double
    var high: Double
    var closes: Bool

    func path(in rect: CGRect) -> Path {
        let marks = Self.layout(points: points, low: low, high: high, in: rect.size)
        var path = Path()
        guard let first = marks.first else { return path }
        path.move(to: first)
        for mark in marks.dropFirst() {
            path.addLine(to: mark)
        }
        if closes, let last = marks.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }

    static func layout(points: [AskHealthPoint], low: Double, high: Double, in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty, high > low else { return [] }
        let span = points.last?.date.timeIntervalSince(points.first?.date ?? .distantPast) ?? 0
        return points.enumerated().map { index, point in
            let x: CGFloat
            if points.count == 1 || span <= 0 {
                x = size.width / 2
            } else if span > 0, let first = points.first?.date {
                let t = point.date.timeIntervalSince(first) / span
                x = size.width * CGFloat(min(max(t, 0), 1))
            } else {
                x = size.width * CGFloat(index) / CGFloat(points.count - 1)
            }
            let y = size.height - size.height * CGFloat((point.value - low) / (high - low))
            return CGPoint(x: x, y: min(max(y, 0), size.height))
        }
    }
}

import AppIntents
import AskKit
import AskKitIntents
import Charts
import Foundation
import SwiftUI

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
    /// The range this card is showing after a tap. Local so the chart moves even when another card holds the shared claim.
    @State private var picked: AskHealthRange?
    @State private var snapshot: AskHealthSeriesSnapshot?
    @State private var loadedRange: AskHealthRange?
    /// Held so Day/Week/Month/Year taps invalidate this card when the shared store changes.
    @State private var ranges = AskHealthRanges.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.askSnippet) private var snippet
    @Environment(\.askCardStyle) private var style

    var body: some View {
        let prepared = snippet.health[metric.key]
        let active = ranges.activeID(for: metric.key) == cardID
        let choice = ranges.choices[metric.key]
        let live = AskHealthChartModel.follows(choice: choice, opened: opened, active: active)
        let range = prepared?.range ?? picked ?? live ?? (active ? initial : (pinned ?? initial))
        VStack(alignment: .leading, spacing: style.contentSpacing) {
            AskCardMark(
                title: metric.title,
                symbol: AskHealthColor.symbol(for: metric),
                tint: AskHealthColor.color(for: metric)
            )
            AskHealthFigure(text: headline(for: range), color: AskHealthColor.color(for: metric))
                .frame(maxWidth: .infinity, alignment: .leading)
            if style == .fullScreen {
                AskHealthRangeControl(metric: metric, selected: range) { item in
                    picked = item
                    ranges.select(metric: metric.key, range: item)
                }
                AskHealthChartPlot(
                    metric: metric,
                    range: prepared?.range ?? loadedRange ?? range,
                    snapshot: prepared?.series ?? snapshot,
                    shapes: prepared != nil
                )
                AskHealthExtraLines(lines: extras)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: style.fillsPage ? .infinity : nil, alignment: .top)
        .askCardSurface()
        .onAppear {
            guard prepared == nil else { return }
            ranges.claim(metric: metric.key, id: cardID, opened: opened)
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
    var onSelect: (AskHealthRange) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AskHealthRange.allCases, id: \.rawValue) { item in
                AskHealthRangeButton(
                    metric: metric,
                    range: item,
                    selected: item == selected,
                    selection: selection,
                    onSelect: onSelect
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
    var onSelect: (AskHealthRange) -> Void

    @Environment(\.askSnippet) private var snippet

    var body: some View {
        control
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var control: some View {
        if snippet.isSnippet {
            Button(intent: AskHealthRangeTap(measurement: metric.measurement, range: range)) {
                label
            }
        } else {
            Button {
                AskCue.tap()
                onSelect(range)
            } label: {
                label
            }
        }
    }

    private var label: some View {
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
                        // The pill is drawn over the row. Leaving it hittable swallows Week, Month, and Year.
                        .allowsHitTesting(false)
                        .matchedGeometryEffect(id: "health-range", in: selection)
                }
            }
            .contentShape(.rect)
    }
}

private struct AskHealthFigure: View {
    var text: String
    var color: Color

    @Environment(\.askSnippet) private var snippet
    @Environment(\.askCardStyle) private var style

    var body: some View {
        if let split = splitNumber {
            if snippet.isSnippet || style == .snippet {
                snippetLine(split)
            } else if style == .fullScreen {
                stacked(split, numberFont: .system(size: 72, weight: .semibold, design: .rounded))
            } else {
                ViewThatFits(in: .horizontal) {
                    beside(split)
                    stacked(split, numberFont: .system(.largeTitle, design: .rounded).weight(.semibold))
                }
            }
        } else {
            Text(text)
                .font(snippet.isSnippet ? .subheadline.weight(.semibold) : style.valueFont)
                .lineLimit(snippet.isSnippet || style == .snippet ? 2 : 1)
                .minimumScaleFactor(0.6)
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

    /// Number and unit on one line. No shrinking, so a total that cannot fit falls through to the stack.
    private func beside(_ split: (number: String, rest: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            number(split.number, font: .system(.largeTitle, design: .rounded).weight(.semibold), scale: 1)
            unit(split.rest, font: .title3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Full screen puts the unit under the total, so "1,691,035" stays one line while the chart grows.
    private func stacked(_ split: (number: String, rest: String), numberFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            number(split.number, font: numberFont, scale: 0.4)
            unit(split.rest, font: style == .fullScreen ? .title2 : .title3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func number(_ value: String, font: Font, scale: CGFloat) -> some View {
        Text(value)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(scale)
            .contentTransition(.numericText())
    }

    private func unit(_ value: String, font: Font) -> some View {
        Text(value)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(2)
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
        case .bloodPressure: .red
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
        case .bloodPressure: "heart.text.square.fill"
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

    @Environment(\.askCardStyle) private var style

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
                .healthPlotHeight(fillsPage: style.fillsPage, compact: style.chartHeight)
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
    @Environment(\.askCardStyle) private var style

    var body: some View {
        let peak = max(points.map(\.value).max() ?? 0, 1)
        Chart(points) { point in
            BarMark(
                x: .value("When", point.date, unit: range.bucket),
                y: .value("Value", point.value)
            )
            .foregroundStyle(color.gradient)
            .cornerRadius(style == .fullScreen ? 8 : 5)
        }
        .chartYScale(domain: 0.0 ... peak * 1.08)
        .healthAxes(range: range, unit: axisLabel, labelFont: style == .fullScreen ? .caption : .caption2)
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: points.map(\.value))
        .healthPlotHeight(fillsPage: style.fillsPage, compact: style.chartHeight)
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
    @Environment(\.askCardStyle) private var style

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
            .lineStyle(StrokeStyle(lineWidth: style == .fullScreen ? 3.5 : 2.5, lineCap: .round, lineJoin: .round))
            PointMark(
                x: .value("When", point.date, unit: range.bucket),
                y: .value("Value", point.value)
            )
            .foregroundStyle(color)
            .symbolSize(36)
        }
        .chartYScale(domain: (low - pad) ... (high + pad))
        .healthAxes(range: range, unit: axisLabel, labelFont: style == .fullScreen ? .caption : .caption2)
        .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: points.map(\.value))
        .healthPlotHeight(fillsPage: style.fillsPage, compact: style.chartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) for the \(range.spokenName)")
        .accessibilityValue(headline)
    }
}

private extension View {
    /// Chat keeps a fixed plot. Full screen gives the chart whatever height the page has left.
    func healthPlotHeight(fillsPage: Bool, compact: CGFloat) -> some View {
        frame(maxWidth: .infinity, maxHeight: fillsPage ? .infinity : compact)
            .frame(height: fillsPage ? nil : compact)
    }

    func healthAxes(range: AskHealthRange, unit: String, labelFont: Font) -> some View {
        chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: range.xFormat)
                            .font(labelFont)
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
                            .font(labelFont)
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

import AskKit
import AskKitIntents
import Foundation
import SwiftUI
import WeatherKit

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

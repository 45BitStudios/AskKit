#if !os(watchOS)
import AskKit
import AskKitIntents
import SwiftUI

/// Agenda-style calendar card. Each row uses that event's calendar color.
struct AskCalendarCard: View {
    var title: String
    var items: [AskCalendarItem.Item]

    @Environment(\.askCardStyle) private var style

    private var groups: [(day: String, items: [AskCalendarItem.Item])] {
        var order: [String] = []
        var map: [String: [AskCalendarItem.Item]] = [:]
        for item in items {
            if map[item.day] == nil {
                order.append(item.day)
                map[item.day] = []
            }
            map[item.day, default: []].append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AskCardMark(title: title.isEmpty ? "Calendar" : title, symbol: "calendar", tint: .red)
            ForEach(shown, id: \.day) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.day)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(group.items) { item in
                        AskCalendarEventRow(item: item)
                    }
                }
            }
        }
        .askCardSurface()
        .accessibilityElement(children: .contain)
    }

    /// Chat shows the next event. Full screen shows the rest of the day.
    private var shown: [(day: String, items: [AskCalendarItem.Item])] {
        guard style != .fullScreen, let first = groups.first, let event = first.items.first else { return groups }
        return [(first.day, [event])]
    }
}

private struct AskCalendarEventRow: View {
    var item: AskCalendarItem.Item

    private var tint: Color { item.color }

    var body: some View {
        Group {
            if item.isBirthday {
                birthdayRow
            } else {
                coloredRow
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var coloredRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(tint)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                timeLine(symbol: item.isAllDay ? "sun.max.fill" : "clock.fill")
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(tint.opacity(0.78))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tint.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: AskCardRadius.medium, style: .continuous))
    }

    private var birthdayRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            Text(item.title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(allDayLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AskCardRadius.medium, style: .continuous))
    }

    private func timeLine(symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(item.isAllDay ? allDayLabel : item.when)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint.opacity(0.9))
    }

    private var allDayLabel: String { "all-day" }

    private var accessibilityLabel: String {
        var parts = [item.title]
        if item.isAllDay {
            parts.append("all day")
        } else if !item.when.isEmpty {
            parts.append(item.when)
        }
        if !item.detail.isEmpty { parts.append(item.detail) }
        if !item.calendarName.isEmpty { parts.append(item.calendarName) }
        parts.append(item.day)
        return parts.joined(separator: ", ")
    }
}
#endif

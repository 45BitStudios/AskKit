import AppIntents
import AskKitSurface
import SwiftUI
import WidgetKit

nonisolated struct AskKitWidgetsIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [AskKitSurfaceIntents.self]
    }
}

@main
struct AskKitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AskNextUpWidget()
        AskRemindersWidget()
        AskNextEventLiveActivity()
        AskControlWidget()
        AskWhatsNextControlWidget()
    }
}

struct AskSurfaceEntry: TimelineEntry {
    var date: Date
    var board: AskSurfaceBoard
}

struct AskSurfaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> AskSurfaceEntry {
        AskSurfaceEntry(date: Date(), board: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (AskSurfaceEntry) -> Void) {
        let board = context.isPreview ? AskSurfaceBoard.sample : AskSurfaceStore.shared.load()
        completion(AskSurfaceEntry(date: Date(), board: board))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AskSurfaceEntry>) -> Void) {
        let board = AskSurfaceStore.shared.load()
        let entry = AskSurfaceEntry(date: Date(), board: board)
        let refresh = board.nextEvent?.end ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

struct AskNextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AskWidgetKind.nextUp, provider: AskSurfaceProvider()) { entry in
            AskNextUpView(entry: entry)
        }
        .configurationDisplayName("Next up")
        .description("The next event Ask has loaded.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AskRemindersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AskWidgetKind.reminders, provider: AskSurfaceProvider()) { entry in
            AskRemindersView(entry: entry)
        }
        .configurationDisplayName("Reminders")
        .description("Open reminders Ask has loaded.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct AskNextUpView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AskSurfaceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next up", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let event = entry.board.nextEvent {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(family == .systemSmall ? 2 : 1)
                Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if family != .systemSmall, !event.location.isEmpty {
                    Text(event.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(entry.board.hasLoaded ? "Nothing coming up" : "Open Ask")
                    .font(.headline)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if family != .systemSmall {
                Button(intent: AskWhatsNextIntent()) {
                    Label("Pin", systemImage: "pin")
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .accessibilityLabel("Pin the next event")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private struct AskRemindersView: View {
    @Environment(\.widgetFamily) private var family
    var entry: AskSurfaceEntry

    private var items: [AskSurfaceReminder] {
        Array(entry.board.reminders.prefix(family == .systemSmall ? 2 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Reminders", systemImage: "checklist")
                .font(.caption)
                .foregroundStyle(.secondary)
            if items.isEmpty {
                Text(entry.board.hasLoaded ? "No open reminders" : "Open Ask")
                    .font(.headline)
                    .lineLimit(2)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if family != .systemSmall {
                Button(intent: AskOpenQuestionIntent(question: "What reminders do I have?")) {
                    Label("Ask", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .accessibilityLabel("Ask about reminders")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AskNextEventLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AskNextEventAttributes.self) { context in
            AskNextEventLockScreen(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AskNextEventTiming(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "calendar")
                    .accessibilityLabel(context.state.title)
            } compactTrailing: {
                AskNextEventTiming(state: context.state)
            } minimal: {
                Image(systemName: "calendar")
                    .accessibilityLabel(context.state.title)
            }
        }
    }
}

private struct AskNextEventLockScreen: View {
    var state: AskNextEventAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                AskNextEventTiming(state: state)
                if !state.location.isEmpty {
                    Text(state.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let url = AskSurfaceMaps.directionsURL(location: state.location) {
                Link(destination: url) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.title3)
                }
                .accessibilityLabel("Get directions")
            }
        }
        .padding(16)
        .activityBackgroundTint(nil)
    }
}

private struct AskNextEventTiming: View {
    var state: AskNextEventAttributes.ContentState

    var body: some View {
        if state.isAllDay {
            Text("All day")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(timerInterval: state.start...state.end, countsDown: true)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct AskControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AskWidgetKind.askControl) {
            ControlWidgetButton(action: AskOpenIntent()) {
                Label("Ask", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .displayName("Ask")
        .description("Opens Ask.")
    }
}

struct AskWhatsNextControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: AskWidgetKind.whatsNextControl) {
            ControlWidgetButton(action: AskWhatsNextIntent()) {
                Label("What's Next", systemImage: "calendar")
            }
        }
        .displayName("What's Next")
        .description("Asks what is on the calendar and pins the next event.")
    }
}

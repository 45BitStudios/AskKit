import SwiftUI
import ThinkingOrbsKit

/// Toolbar button that opens every card with sample data. Renders nothing in Release.
public struct AskCardGalleryButton: View {
    @State private var isPresented = false

    public init() {}

    public var body: some View {
        #if DEBUG
        Button {
            AskCue.tap()
            isPresented = true
        } label: {
            Image(systemName: "rectangle.stack")
        }
        .accessibilityLabel("Cards")
        .sheet(isPresented: $isPresented) {
            AskCardGalleryScreen()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
/// Each card the chat can draw, filled with sample lines. Nothing here reads Music, Weather, Health, or Reminders.
public struct AskCardGalleryScreen: View {
    @Environment(\.dismiss) private var dismiss
    private let showsClose: Bool

    public init(showsClose: Bool = true) {
        self.showsClose = showsClose
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    AskOrbGallerySection()
                    ForEach(AskCardSamples.sections()) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            if !section.note.isEmpty {
                                Text(section.note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            section.view
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            AskCue.tap()
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            AskReminderChecks.shared.adopt([AskCardSamples.reminderDoneID])
        }
    }
}

enum AskCardSamples {
    static let reminderDoneID = "askkit.sample.reminder.done"

    static let names = [
        "Calendar",
        "Reminders",
        "Alarm",
        "Contact",
        "Place",
        "Nearby",
        "Coordinates",
        "Steps",
        "Heart rate",
        "Song",
        "Now playing",
        "Album",
        "Daily forecast",
        "Hourly forecast",
        "Music unavailable",
        "Nothing playing",
        "No forecast",
        "Capabilities",
        "Skill"
    ]

    static let calendarLines = [
        AskCalendarItem.line(
            day: "Thursday, Oct 8",
            title: "Standup",
            when: "9:00 AM",
            colorHex: "0A84FF",
            kind: .timed,
            calendarName: "Work"
        ),
        AskCalendarItem.line(
            day: "Thursday, Oct 8",
            title: "Dentist",
            when: "3:00 PM",
            detail: "Apple Park",
            colorHex: "FF9F0A",
            kind: .timed,
            calendarName: "Personal"
        ),
        AskCalendarItem.line(
            day: "Thursday, Oct 8",
            title: "Alex Rivera’s Birthday",
            when: "all day",
            colorHex: "8E8E93",
            kind: .birthday,
            calendarName: "Birthdays"
        )
    ]

    static let alarmLine = AskAlarmLine.line(AskAlarmDraft(
        title: "Wake up",
        hour: 7,
        minute: 0,
        repeats: .weekdays,
        label: "Garage",
        symbol: "sunrise.fill",
        actionID: "open"
    ))

    static let reminderLines = [
        AskReminderItem.line(title: "Pick up tires", due: "Thu, Oct 8", id: "askkit.sample.reminder.open"),
        AskReminderItem.line(title: "Charge overnight", due: "Tonight", id: reminderDoneID)
    ]

    static let contactLine = AskContactLine.line(
        name: "April Chen",
        phone: "(312) 555-0148",
        email: "april@example.com"
    )

    static let placeLine = AskLocationPin.line(label: "Apple Park, Cupertino", latitude: 37.3349, longitude: -122.0090)

    static let nearbyLines = [
        AskLocationPin.line(label: "Apple Park, 1 Apple Park Way", latitude: 37.3349, longitude: -122.0090),
        AskLocationPin.line(label: "Visitor Center, 10600 N Tantau Ave", latitude: 37.3327, longitude: -122.0053),
        AskLocationPin.line(label: "Main Street, Cupertino", latitude: 37.3230, longitude: -122.0322)
    ]

    static let songLine = AskMusicLine.songLine(
        title: "Anti-Hero",
        artist: "Taylor Swift",
        album: "Midnights",
        duration: 201
    )

    static let nowPlayingLine = AskMusicLine.nowLine(
        title: "Sunday Morning Call",
        artist: "Oasis",
        album: "Standing on the Shoulder of Giants",
        duration: 312
    )

    static let albumLine = AskMusicLine.albumLine(
        title: "Abbey Road",
        artist: "The Beatles",
        songs: 17,
        year: "1969"
    )

    static let dayLine = AskWeatherLine.dayLine(
        title: "Thu, Oct 8",
        symbol: "cloud.sun",
        condition: "Partly cloudy",
        high: "72 F",
        low: "54 F",
        rain: "20 percent"
    )

    static let hourlyLines = [
        dayLine,
        AskWeatherLine.hourLine(time: "9 AM", symbol: "sun.max", condition: "Sunny", temperature: "61 F", rain: "0 percent"),
        AskWeatherLine.hourLine(time: "12 PM", symbol: "cloud.sun", condition: "Partly cloudy", temperature: "68 F", rain: "10 percent"),
        AskWeatherLine.hourLine(time: "3 PM", symbol: "cloud", condition: "Cloudy", temperature: "72 F", rain: "20 percent"),
        AskWeatherLine.hourLine(time: "6 PM", symbol: "cloud.rain", condition: "Rain", temperature: "64 F", rain: "60 percent")
    ]

    static var lines: [String] {
        calendarLines + reminderLines + [alarmLine, contactLine, placeLine] + nearbyLines
            + [songLine, nowPlayingLine, albumLine, dayLine] + hourlyLines
            + ["Not allowed.", "Nothing is playing.", "No forecast.", "Steps: 8,420 steps", "Heart rate: 72 bpm"]
    }

    static func healthSeries(
        metric: AskHealthCatalog.Metric,
        range: AskHealthRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AskHealthSeriesSnapshot {
        let dates = AskHealthBuckets.dates(range: range, now: now, calendar: calendar)
        let line = AskHealthCatalog.chartKind(for: metric) == .line
        let points = dates.enumerated().map { index, date in
            AskHealthPoint(
                id: "\(metric.key)-\(range.rawValue)-\(index)",
                date: date,
                value: sampleValue(metric: metric, index: index),
                recorded: line ? index % 2 == 0 : true
            )
        }
        let shown = line ? points.filter(\.recorded) : points
        let number = shown.isEmpty ? 0 : shown.map(\.value).reduce(0, +) / (line ? Double(shown.count) : 1)
        let headline = AskHealthCatalog.headline(
            value: Int(number.rounded()).formatted(),
            unit: sampleUnit(metric),
            range: range
        )
        return AskHealthSeriesSnapshot(
            points: points,
            headline: headline,
            axisLabel: AskHealthCatalog.axisLabel(for: metric),
            denied: false,
            recorded: !shown.isEmpty
        )
    }

    @MainActor
    static func sections() -> [AskCardGallerySection] {
        [
            section("Calendar", "Each event uses its calendar color.", apple("calendar", calendarLines, "Standup at 9, dentist at 3.")),
            section("Reminders", "One sample is already complete. These are not in Reminders.", reminders),
            section("Alarm", "A custom button label and symbol. Several alarms in one answer are one card each.", apple("alarms", [alarmLine], "Wake up at 7:00 AM.")),
            section("Contact", "Phone and email stay on one line and open a call or message.", apple("contacts", [contactLine], "April Chen.")),
            section("Place", "The map is the answer.", apple("location", [placeLine], "Apple Park.")),
            section("Nearby", "Several places share one map.", apple("location", nearbyLines, "Three places nearby.")),
            section("Coordinates", "Shown only when the question asks for them.", coordinates),
            section("Steps", "Sample bars. Day, Week, Month, and Year stay on this card.", health(.steps, "Steps: 8,420 steps")),
            section("Heart rate", "Sample line.", health(.heart, "Heart rate: 72 bpm")),
            section("Song", "A song search.", apple("music", [songLine], "Anti-Hero by Taylor Swift.")),
            section("Now playing", "What is playing, with scrubber and transport.", nowPlaying),
            section("Album", "An album search.", apple("music", [albumLine], "Abbey Road by The Beatles.")),
            section("Daily forecast", "A week stays on one card.", weather([dayLine], hours: false)),
            section("Hourly forecast", "Hours stay on that day.", weather(hourlyLines, hours: true)),
            section("Music unavailable", "The fact card when Music is off.", apple("music", ["Not allowed."], "Not allowed.")),
            section("Nothing playing", "", apple("music", ["Nothing is playing."], "Nothing is playing.")),
            section("No forecast", "", apple("weather", ["No forecast."], "No forecast.")),
            section("Capabilities", "What this assistant can answer.", capabilities),
            section("Skill", "Same shape as a sample fact card.", skill)
        ]
    }

    private static func sampleValue(metric: AskHealthCatalog.Metric, index: Int) -> Double {
        switch metric {
        case .steps: Double(180 + (index * 97) % 820)
        case .heart, .restingHeart: Double(58 + (index * 5) % 30)
        case .energy: Double(20 + (index * 11) % 80)
        case .distance: Double(index % 5) * 0.4 + 0.2
        case .flights: Double(index % 4)
        case .exercise: Double(index % 6) * 5
        default: Double(150 + index % 12)
        }
    }

    private static func sampleUnit(_ metric: AskHealthCatalog.Metric) -> String {
        switch metric {
        case .steps: "steps"
        case .heart, .restingHeart: "bpm"
        case .energy: "kcal"
        case .distance: "mi"
        case .flights: "flights"
        case .exercise: "min"
        default: AskHealthCatalog.axisLabel(for: metric)
        }
    }

    @MainActor
    private static func section(_ title: String, _ note: String, _ view: some View) -> AskCardGallerySection {
        AskCardGallerySection(id: title, title: title, note: note, view: AnyView(view))
    }

    @MainActor
    private static func apple(_ name: String, _ lines: [String], _ spoken: String) -> some View {
        AskAppleCards.make(
            AskAppleReading(name: name, lines: lines),
            spoken: spoken,
            custom: nil
        ).view
    }

    @MainActor
    private static var nowPlaying: some View {
        AskNowPlayingCard(
            item: AskMusicLine.item(from: nowPlayingLine)!,
            playedBy: "Cobot",
            previewElapsed: 0,
            previewPlaying: false
        )
    }

    @MainActor
    private static var reminders: some View {
        AskReminderCard(
            title: "Reminders",
            items: AskReminderItem.tasks(in: reminderLines),
            readsCompletion: false
        )
    }

    @MainActor
    private static var coordinates: some View {
        AskAppleCards.make(
            AskAppleReading(name: "location", lines: [placeLine]),
            spoken: "Apple Park is at 37.3349, -122.0090.",
            showsCoordinates: true,
            custom: nil
        ).view
    }

    @MainActor
    private static func health(_ metric: AskHealthCatalog.Metric, _ line: String) -> some View {
        AskHealthChartCard(
            metric: metric,
            initial: .day,
            lines: [line],
            sampleSeries: { range in
                healthSeries(metric: metric, range: range)
            }
        )
    }

    @MainActor
    private static func weather(_ lines: [String], hours: Bool) -> some View {
        let forecast = AskWeatherLine.forecast(from: lines)
        return AskWeatherCard(forecast: forecast ?? AskWeatherLine.Forecast(
            day: AskWeatherLine.Day(title: "Thu, Oct 8", symbol: "cloud.sun", condition: "Unknown", high: "72 F", low: "54 F", rain: "0 percent"),
            hours: []
        ), loadsCredit: false)
        .accessibilityLabel(hours ? "Hourly forecast" : "Daily forecast")
    }

    @MainActor
    private static var capabilities: some View {
        AskCapabilitiesCard(groups: [
            AskCapabilityGroup(id: "battery", title: "Battery", items: [
                AskCapability(id: "charge", title: "Charge status", detail: "Current battery"),
                AskCapability(id: "limit", title: "Charge limit", detail: "The limit you set")
            ]),
            AskCapabilityGroup(id: "trip", title: "Trip", items: [
                AskCapability(id: "range", title: "Range left", detail: "Miles left on this charge")
            ])
        ])
    }

    @MainActor
    private static var skill: some View {
        AskAppleFactCard(title: "Charge", value: "68 percent", detail: "About 40 minutes to the limit.")
    }
}

struct AskCardGallerySection: Identifiable {
    var id: String
    var title: String
    var note: String
    var view: AnyView
}

private struct AskOrbGallerySection: View {
    /// A held style. Nil plays working, then connecting, then searching.
    @State private var pinned: OrbState?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Orb")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let pinned {
                    HStack(spacing: 16) {
                        ThinkingOrb(state: pinned, size: .px64, theme: .auto, displaySize: 88)
                            .accessibilityHidden(true)
                        Text(pinned.styleTitle)
                            .font(.title3.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                } else {
                    AskOrbSequence(displaySize: 88, showsLabel: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .contextMenu {
            Button {
                AskCue.tap()
                pinned = nil
            } label: {
                if pinned == nil {
                    Label("In order", systemImage: "checkmark")
                } else {
                    Text("In order")
                }
            }
            ForEach(OrbState.allCases, id: \.rawValue) { state in
                Button {
                    AskCue.tap()
                    pinned = state
                } label: {
                    if pinned == state {
                        Label(state.styleTitle, systemImage: "checkmark")
                    } else {
                        Text(state.styleTitle)
                    }
                }
            }
        }
        .accessibilityHint("Hold to look at one style")
    }

    private var caption: String {
        if let pinned {
            return "Holding \(pinned.styleTitle). Hold and choose In order to play them."
        }
        return "Working, then connecting, then searching."
    }
}
#endif

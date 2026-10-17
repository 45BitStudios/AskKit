#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Shared by the app and the widget extension. The app writes the board. Widgets and Live Activities read it.
public enum AskSurfaceGroup {
    public static let identifier = "group.com.45bitstudios.askkitapp"
}

public enum AskWidgetKind {
    public static let nextUp = "com.45bitstudios.askkitapp.next-up"
    public static let reminders = "com.45bitstudios.askkitapp.reminders"
    public static let askControl = "com.45bitstudios.askkitapp.ask"
    public static let whatsNextControl = "com.45bitstudios.askkitapp.whats-next"
}

extension Notification.Name {
    public static let askSurfaceQueued = Notification.Name("AskSurfaceQueued")
}

/// The next event a host already knows how to read.
public struct AskSurfaceEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }
}

/// One open reminder, in the same order the reminders card would list.
public struct AskSurfaceReminder: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var due: Date?

    public init(id: String, title: String, due: Date?) {
        self.id = id
        self.title = title
        self.due = due
    }
}

/// Facts the widgets show. Empty until the app has read calendar or reminders.
public struct AskSurfaceBoard: Codable, Hashable, Sendable {
    public var nextEvent: AskSurfaceEvent?
    public var reminders: [AskSurfaceReminder]
    public var updatedAt: Date

    public init(nextEvent: AskSurfaceEvent?, reminders: [AskSurfaceReminder], updatedAt: Date) {
        self.nextEvent = nextEvent
        self.reminders = reminders
        self.updatedAt = updatedAt
    }

    public static let empty = AskSurfaceBoard(nextEvent: nil, reminders: [], updatedAt: .distantPast)

    public static var sample: AskSurfaceBoard {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return AskSurfaceBoard(
            nextEvent: AskSurfaceEvent(
                id: "sample-event",
                title: "Design review",
                start: start,
                end: start.addingTimeInterval(60 * 60),
                isAllDay: false,
                location: "Studio"
            ),
            reminders: [
                AskSurfaceReminder(id: "sample-1", title: "Send the build", due: nil),
                AskSurfaceReminder(id: "sample-2", title: "Pick up the car", due: start)
            ],
            updatedAt: start
        )
    }

    public var hasLoaded: Bool { updatedAt != .distantPast }
}

/// App-group store. A custom defaults object keeps tests off the shared suite.
public final class AskSurfaceStore: @unchecked Sendable {
    public static let shared = AskSurfaceStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let boardKey = "AskSurface.board"
    private let questionKey = "AskSurface.question"
    private let pinKey = "AskSurface.pin"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: AskSurfaceGroup.identifier) ?? .standard
    }

    public func save(_ board: AskSurfaceBoard) {
        guard let data = try? JSONEncoder().encode(board) else { return }
        lock.lock()
        defaults.set(data, forKey: boardKey)
        lock.unlock()
        Task { @MainActor in
#if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: AskWidgetKind.nextUp)
            WidgetCenter.shared.reloadTimelines(ofKind: AskWidgetKind.reminders)
#endif
        }
    }

    public func load() -> AskSurfaceBoard {
        lock.lock()
        let data = defaults.data(forKey: boardKey)
        lock.unlock()
        guard let data, let board = try? JSONDecoder().decode(AskSurfaceBoard.self, from: data) else {
            return .empty
        }
        return board
    }

    /// The chat sends this question the next time it is idle.
    public func enqueue(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        defaults.set(trimmed, forKey: questionKey)
        lock.unlock()
        NotificationCenter.default.post(name: .askSurfaceQueued, object: nil)
    }

    public func takeQuestion() -> String? {
        lock.lock()
        let stored = defaults.string(forKey: questionKey)
        defaults.removeObject(forKey: questionKey)
        lock.unlock()
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// After the next calendar read, keep that event on the Lock Screen.
    public func requestPin() {
        lock.lock()
        defaults.set(true, forKey: pinKey)
        lock.unlock()
        NotificationCenter.default.post(name: .askSurfaceQueued, object: nil)
    }

    public func consumePin() -> Bool {
        lock.lock()
        let pinned = defaults.bool(forKey: pinKey)
        if pinned { defaults.set(false, forKey: pinKey) }
        lock.unlock()
        return pinned
    }
}

public enum AskSurfaceMaps {
    public static func directionsURL(location: String) -> URL? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "maps.apple.com"
        parts.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return parts.url
    }
}

public enum AskLiveActivityPin: Sendable, Equatable {
    case pinned(String)
    case nothingToPin
    case turnedOff
    case failed
    /// This device has no Lock Screen Live Activities. Only iPhone shows them.
    case unsupported
}

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)

/// Lock Screen and Dynamic Island for the next event.
public struct AskNextEventAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var start: Date
        public var end: Date
        public var isAllDay: Bool
        public var location: String

        public init(title: String, start: Date, end: Date, isAllDay: Bool, location: String) {
            self.title = title
            self.start = start
            self.end = end
            self.isAllDay = isAllDay
            self.location = location
        }
    }

    public var name: String

    public init(name: String) {
        self.name = name
    }
}

@MainActor
public enum AskNextEventActivity {
    public static func pin(_ event: AskSurfaceEvent) async -> AskLiveActivityPin {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .turnedOff }
        let state = AskNextEventAttributes.ContentState(
            title: event.title,
            start: event.start,
            end: event.end > event.start ? event.end : event.start.addingTimeInterval(60),
            isAllDay: event.isAllDay,
            location: event.location
        )
        let content = ActivityContent(state: state, staleDate: state.end)
        let activities = Activity<AskNextEventAttributes>.activities
        if let current = activities.first {
            await current.update(content)
            for extra in activities.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return .pinned(event.title)
        }
        do {
            _ = try Activity.request(
                attributes: AskNextEventAttributes(name: "Next up"),
                content: content,
                pushType: nil
            )
            return .pinned(event.title)
        } catch {
            return .failed
        }
    }

    public static func endFinished(now: Date = Date()) async {
        for activity in Activity<AskNextEventAttributes>.activities where activity.content.state.end <= now {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#else
@MainActor
public enum AskNextEventActivity {
    public static func pin(_ event: AskSurfaceEvent) async -> AskLiveActivityPin {
        .unsupported
    }

    public static func endFinished(now: Date = Date()) async {}
}
#endif

/// Surface intents. The app includes this package so Controls and widgets can run them in the app.
public struct AskKitSurfaceIntents: AppIntentsPackage {}

/// Opens Ask.
public struct AskOpenIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask"
    public static let description = IntentDescription("Opens Ask.")
    public static var supportedModes: IntentModes { .foreground(.immediate) }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Asks what is on the calendar and pins that event.
public struct AskWhatsNextIntent: AppIntent {
    public static let title: LocalizedStringResource = "What's Next"
    public static let description = IntentDescription("Asks what is on the calendar and keeps the next event on the Lock Screen.")
    public static var supportedModes: IntentModes { .foreground(.immediate) }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    public init() {}

    public func perform() async throws -> some IntentResult {
        AskSurfaceStore.shared.requestPin()
        AskSurfaceStore.shared.enqueue("What's on my calendar today?")
        return .result()
    }
}

/// Opens Ask with one fixed question. Widget buttons use this.
public struct AskOpenQuestionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask a Question"
    public static let description = IntentDescription("Opens Ask with a question.")
    public static let isDiscoverable = false
    public static var supportedModes: IntentModes { .foreground(.immediate) }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Question")
    public var question: String

    public init() {
        question = ""
    }

    public init(question: String) {
        self.question = question
    }

    public func perform() async throws -> some IntentResult {
        AskSurfaceStore.shared.enqueue(question)
        return .result()
    }
}

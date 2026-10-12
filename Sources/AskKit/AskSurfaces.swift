import AskKitIntents
import Foundation

/// Publishes calendar and reminder facts the widgets already know how to show.
@MainActor
public enum AskSurfaces {
    /// Reads what this assistant is allowed to see. Does not ask for access.
    public static func refresh(access: AskAppleAccess, now: Date = Date()) async {
        let event = access.contains(.calendar) ? await AskSurfaceCalendar.upcoming(now: now) : nil
        let reminders = access.contains(.reminders) ? await AskRemindersRead.openItems(limit: 3) : []
        AskSurfaceStore.shared.save(AskSurfaceBoard(nextEvent: event, reminders: reminders, updatedAt: now))
        await AskNextEventActivity.endFinished(now: now)
    }

    /// Pins the event currently on the board.
    @discardableResult
    public static func pinNextEvent() async -> AskLiveActivityPin {
        guard let event = AskSurfaceStore.shared.load().nextEvent else { return .nothingToPin }
        return await AskNextEventActivity.pin(event)
    }

    /// Reads the calendar, then pins the next event. The line is what the chat should say.
    public static func pinSpoken(access: AskAppleAccess, now: Date = Date()) async -> String {
        await refresh(access: access, now: now)
        switch await pinNextEvent() {
        case .pinned(let title):
            return "Pinned \(title) on the Lock Screen."
        case .nothingToPin:
            return "Nothing coming up to pin."
        case .turnedOff:
            return "Live Activities are turned off, so that stays in the chat."
        case .failed:
            return "I couldn't pin that on the Lock Screen."
        }
    }
}

enum AskPinPhrase {
    static let actionID = "ask.pin.next-event"

    private static let phrases = [
        "pin this",
        "pin that",
        "pin it",
        "pin the next event",
        "keep this on the lock screen",
        "keep it on the lock screen",
        "show this on the lock screen"
    ]

    static func matches(_ utterance: String) -> Bool {
        var text = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = text.last, ".!?".contains(last) {
            text.removeLast()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return phrases.contains(text)
    }
}

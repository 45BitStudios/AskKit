import AlarmKit
import AppIntents
import Foundation
import FoundationModels
import os
import SwiftUI

/// How often a clock alarm repeats. A timer ignores this.
public enum AskAlarmRepeat: Sendable, Equatable {
    /// Words the alarm tool accepts for `repeats`. The guide uses this list.
    static let choices = [
        "never", "once", "daily", "weekdays", "weekends",
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"
    ]

    case never
    case daily
    case weekdays
    case weekends
    /// One weekday, such as "monday".
    case weekday(String)

    var phrase: String {
        switch self {
        case .never: "once"
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .weekends: "weekends"
        case .weekday(let name):
            name.prefix(1).uppercased() + name.dropFirst() + "s"
        }
    }
}

/// One alarm to schedule. The button is optional.
/// `actionID` names an action registered with `AskAlarms`. "open" is built in.
public struct AskAlarmDraft: Sendable, Equatable {
    public var title: String
    public var hour: Int?
    public var minute: Int
    /// 0 is today, through 13. Nil means the next time that hour comes.
    public var day: Int?
    /// Minutes from now. Used when `hour` is nil.
    public var afterMinutes: Int?
    public var repeats: AskAlarmRepeat
    public var label: String?
    public var symbol: String?
    public var actionID: String?

    public init(
        title: String,
        hour: Int? = nil,
        minute: Int = 0,
        day: Int? = nil,
        afterMinutes: Int? = nil,
        repeats: AskAlarmRepeat = .never,
        label: String? = nil,
        symbol: String? = nil,
        actionID: String? = nil
    ) {
        self.title = title
        self.hour = hour
        self.minute = minute
        self.day = day
        self.afterMinutes = afterMinutes
        self.repeats = repeats
        self.label = label
        self.symbol = symbol
        self.actionID = actionID
    }
}

/// A custom button a host can attach when an alarm is created.
/// The closure receives the alarm id and the alarm title.
public struct AskAlarmAction: Sendable {
    public var id: String
    public var label: String
    public var symbol: String
    public var intent: @Sendable (UUID, String) -> any LiveActivityIntent

    public init(
        id: String,
        label: String,
        symbol: String,
        intent: @escaping @Sendable (UUID, String) -> any LiveActivityIntent
    ) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.intent = intent
    }
}

/// Opens the app from an alarm button. Not a Siri shortcut.
public struct AskAlarmOpenIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Open Alarm"
    public static let description = IntentDescription("Opens the app from an alarm button.")
    public static let isDiscoverable = false

    public static var supportedModes: IntentModes { .foreground(.immediate) }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Alarm")
    public var alarmID: String

    public init() {
        alarmID = ""
    }

    public init(alarmID: String) {
        self.alarmID = alarmID
    }

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Registers alarm buttons and schedules alarms.
///
/// "open" is always available. A host registers more actions before a question runs.
/// Scheduling asks for AlarmKit permission the first time.
public enum AskAlarms {
    public static func register(_ action: AskAlarmAction) {
        guard let id = AskAlarmText.actionID(action.id), !id.isEmpty else { return }
        let stored = AskAlarmAction(
            id: id,
            label: AskAlarmText.label(action.label) ?? action.label,
            symbol: AskAlarmText.symbol(action.symbol) ?? "bell.fill",
            intent: action.intent
        )
        store.withLock { $0[id] = stored }
    }

    /// Schedules every draft. One line per alarm. A denial is "Not allowed."
    public static func schedule(_ drafts: [AskAlarmDraft]) async -> String {
        await AskAlarmRead.schedule(drafts)
    }

    static func action(id: String?) -> AskAlarmAction? {
        guard let id = AskAlarmText.actionID(id), !id.isEmpty else { return nil }
        if let stored = store.withLock({ $0[id] }) { return stored }
        if id == builtin.id { return builtin }
        return nil
    }

    static func identifiers() -> Set<String> {
        var ids = store.withLock { Set($0.keys) }
        ids.insert(builtin.id)
        return ids
    }

    static func menu() -> String {
        var actions = store.withLock { Array($0.values) }
        if !actions.contains(where: { $0.id == builtin.id }) {
            actions.append(builtin)
        }
        return actions
            .sorted { $0.id < $1.id }
            .map { "\($0.id) (\($0.label), \($0.symbol))" }
            .joined(separator: "; ")
    }

    private static let builtin = AskAlarmAction(
        id: "open",
        label: "Open",
        symbol: "arrow.up.forward.app",
        intent: { id, _ in AskAlarmOpenIntent(alarmID: id.uuidString) }
    )

    private static let store = OSAllocatedUnfairLock(initialState: [String: AskAlarmAction]())
}

/// The button that will be stored on the alarm. Nil means no custom button.
struct AskAlarmButtonChoice: Equatable {
    var label: String
    var symbol: String
    var actionID: String
}

enum AskAlarmButtonPlan {
    /// `registered` is the action that matched the draft, when one did.
    /// An unknown action id is ignored. Label and symbol still make an Open button.
    static func choice(
        draft: AskAlarmDraft,
        registered: (id: String, label: String, symbol: String)?
    ) -> AskAlarmButtonChoice? {
        let label = AskAlarmText.label(draft.label)
            ?? AskAlarmText.label(registered?.label)
            ?? ((draft.symbol != nil || registered != nil) ? "Open" : nil)
        guard let label else { return nil }
        let symbol = AskAlarmText.symbol(draft.symbol)
            ?? AskAlarmText.symbol(registered?.symbol)
            ?? (registered == nil ? "arrow.up.forward.app" : "bell.fill")
        return AskAlarmButtonChoice(label: label, symbol: symbol, actionID: registered?.id ?? "open")
    }
}

enum AskAlarmWhen: Equatable {
    case timer(Int)
    case fixed(day: Int, hour: Int, minute: Int)
    case relative(hour: Int, minute: Int, repeats: AskAlarmRepeat)
}

/// A change to alarms that are already scheduled. A nil match means every alarm, or the only one.
struct AskAlarmChange: Equatable {
    var matchHour: Int? = nil
    var matchMinute: Int? = nil
    var hour: Int? = nil
    var minute: Int? = nil
    var repeats: AskAlarmRepeat? = nil
    var title: String? = nil
}

/// Removes one alarm, or every alarm when the hour is nil.
struct AskAlarmRemoval: Equatable {
    var hour: Int? = nil
    var minute: Int? = nil
}

/// What this question asks the alarms tool to do. The question wins over the model's arguments.
enum AskAlarmIntent: Equatable {
    case list
    case set([AskAlarmDraft])
    case change(AskAlarmChange)
    case remove(AskAlarmRemoval)
    case needsTime
    case none
}

/// Turns tool fields into drafts. Parsing does not open AlarmKit.
enum AskAlarmCommand: Equatable {
    case drafts([AskAlarmDraft])
    case needsTitle
    case badTime
    case empty

    static let maximum = 8

    struct Field: Equatable {
        var title: String?
        var hour: Int?
        var minute: Int?
        var day: Int?
        var after: Int?
        var repeats: String?
        var label: String?
        var symbol: String?
        var action: String?
    }

    static func parse(_ fields: [Field]) -> AskAlarmCommand {
        if fields.isEmpty { return .empty }
        var drafts: [AskAlarmDraft] = []
        var sawBadTime = false
        for field in fields {
            if drafts.count >= maximum { break }
            switch one(field) {
            case .draft(let draft):
                drafts.append(draft)
            case .badTime:
                sawBadTime = true
            case .skip:
                break
            }
        }
        if !drafts.isEmpty { return .drafts(drafts) }
        return sawBadTime ? .badTime : .needsTitle
    }

    /// Clock times and timers named in the question. Parsing does not open AlarmKit.
    /// An empty list means this question is not asking to set one, or it names no time.
    /// A clock alarm with no name uses the title Alarm. A timer with no name uses Timer.
    /// A custom button label or symbol named in the question is copied onto every draft.
    static func drafts(in question: String, now: Date = Date(), calendar: Calendar = .current) -> [AskAlarmDraft] {
        guard sets(question) else { return [] }
        let folded = AskAppleCopy.folded(question)
        var timers: [Mark] = []
        collectTimers(in: folded, into: &timers)
        let found = clocks(in: folded)
        let day = AskCalendarWindow.offset(namedIn: question, now: now, calendar: calendar)
        let repeats = repeats(in: folded)
        let named = namedTitle(in: question)
        let label = namedLabel(in: question)
        let symbol = namedSymbol(in: question)
        var ordered: [(start: Int, draft: AskAlarmDraft)] = []
        for timer in timers {
            guard let after = timer.after else { continue }
            ordered.append((timer.start, AskAlarmDraft(
                title: named ?? "Timer",
                afterMinutes: after,
                label: label,
                symbol: symbol
            )))
        }
        for clock in found {
            ordered.append((clock.start, AskAlarmDraft(
                title: named ?? "Alarm",
                hour: clock.hour,
                minute: clock.minute,
                day: day,
                repeats: repeats,
                label: label,
                symbol: symbol
            )))
        }
        ordered.sort { $0.start < $1.start }
        return ordered.prefix(maximum).map(\.draft)
    }

    /// List, set, change, or remove. Parsing does not open AlarmKit. The question wins over a draft copied from an earlier turn.
    static func intent(in question: String, now: Date = Date(), calendar: Calendar = .current) -> AskAlarmIntent {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let folded = AskAppleCopy.folded(trimmed)
        if isRemoval(folded), !sets(trimmed) {
            let marks = clocks(in: folded)
            if let clock = marks.first {
                return .remove(AskAlarmRemoval(hour: clock.hour, minute: clock.minute))
            }
            return .remove(AskAlarmRemoval())
        }
        if isChange(folded), !sets(trimmed) {
            return .change(change(in: trimmed, folded: folded))
        }
        if sets(trimmed) {
            let found = drafts(in: trimmed, now: now, calendar: calendar)
            return found.isEmpty ? .needsTime : .set(found)
        }
        if isList(folded) { return .list }
        return .none
    }

    /// Drafts whose time the question asked to set. An empty `asked` list schedules nothing, so a count cannot create an alarm from an earlier turn.
    /// A second alarm the question did not name, such as a reminder at midnight, is left out and is not scheduled.
    /// Button label and symbol from the question fill in when the model left them empty.
    static func matching(_ drafts: [AskAlarmDraft], asked: [AskAlarmDraft]) -> [AskAlarmDraft] {
        guard !asked.isEmpty else { return [] }
        return drafts.compactMap { draft in
            guard let asked = asked.first(where: { sameClock($0, draft) }) else { return nil }
            return enriched(draft, from: asked)
        }
    }

    /// Copies a button label, symbol, or action from `asked` when the model draft left that field empty.
    static func enriched(_ draft: AskAlarmDraft, from asked: AskAlarmDraft) -> AskAlarmDraft {
        var copy = draft
        if AskAlarmText.label(copy.label) == nil {
            copy.label = AskAlarmText.label(asked.label)
        }
        if AskAlarmText.symbol(copy.symbol) == nil {
            copy.symbol = AskAlarmText.symbol(asked.symbol)
        }
        if AskAlarmText.actionID(copy.actionID) == nil {
            copy.actionID = AskAlarmText.actionID(asked.actionID)
        }
        return copy
    }

    private static func sameClock(_ asked: AskAlarmDraft, _ draft: AskAlarmDraft) -> Bool {
        if asked.hour == nil || draft.hour == nil {
            return asked.hour == nil && draft.hour == nil && asked.afterMinutes == draft.afterMinutes
        }
        return asked.hour == draft.hour && asked.minute == draft.minute
    }

    static func schedule(for draft: AskAlarmDraft) -> AskAlarmWhen? {
        if draft.hour == nil, let minutes = draft.afterMinutes {
            guard (1...720).contains(minutes) else { return nil }
            return .timer(minutes)
        }
        guard let hour = draft.hour, (0...23).contains(hour), (0...59).contains(draft.minute) else { return nil }
        if draft.repeats != .never {
            return .relative(hour: hour, minute: draft.minute, repeats: draft.repeats)
        }
        if let day = draft.day {
            guard (0...AskCalendarWindow.maximumOffset).contains(day) else { return nil }
            return .fixed(day: day, hour: hour, minute: draft.minute)
        }
        return .relative(hour: hour, minute: draft.minute, repeats: .never)
    }

    private enum One {
        case draft(AskAlarmDraft)
        case badTime
        case skip
    }

    private static func one(_ field: Field) -> One {
        let title = AskAlarmText.title(field.title)
        let minute = field.minute ?? 0
        let repeats = AskAlarmText.repeats(field.repeats)
        let day = field.day.flatMap { (0...AskCalendarWindow.maximumOffset).contains($0) ? $0 : nil }
        if let hour = field.hour {
            guard (0...23).contains(hour), (0...59).contains(minute) else { return .badTime }
            guard let title else { return .skip }
            return .draft(AskAlarmDraft(
                title: title,
                hour: hour,
                minute: minute,
                day: day,
                repeats: repeats,
                label: AskAlarmText.label(field.label),
                symbol: AskAlarmText.symbol(field.symbol),
                actionID: AskAlarmText.actionID(field.action)
            ))
        }
        if let after = field.after {
            guard (1...720).contains(after) else { return .badTime }
            guard let title else { return .skip }
            return .draft(AskAlarmDraft(
                title: title,
                afterMinutes: after,
                repeats: .never,
                label: AskAlarmText.label(field.label),
                symbol: AskAlarmText.symbol(field.symbol),
                actionID: AskAlarmText.actionID(field.action)
            ))
        }
        return .skip
    }

    private struct Mark {
        var start: Int
        var end: Int
        var hour: Int?
        var minute: Int
        var after: Int?
    }

    private static func sets(_ question: String) -> Bool {
        let folded = AskAppleCopy.folded(question)
        let phrases = [
            "set an alarm", "set a timer", "set alarm", "set timer",
            "create an alarm", "add an alarm", "new alarm",
            "wake me", "timer for",
            "make an alarm", "make a timer", "recurring alarm", "repeating alarm"
        ]
        return phrases.contains { folded.localizedStandardContains($0) }
    }

    private static func isRemoval(_ folded: String) -> Bool {
        if folded.localizedStandardContains("turn off") || folded.localizedStandardContains("switch off") { return true }
        let tokens = Set(folded.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if tokens.contains("turn") && tokens.contains("off") { return true }
        return tokens.contains("delete") || tokens.contains("remove") || tokens.contains("cancel")
    }

    private static func isChange(_ folded: String) -> Bool {
        let edits = ["change", "move", "edit", "update", "reschedule"]
        if edits.contains(where: { folded.localizedStandardContains($0) }) { return true }
        if isList(folded) { return false }
        let repeating = folded.localizedStandardContains("recurring") || folded.localizedStandardContains("repeat")
        if repeating { return true }
        return folded.localizedStandardContains("make") && namedRepeats(in: folded) != nil
    }

    private static func isList(_ folded: String) -> Bool {
        guard folded.localizedStandardContains("alarm") || folded.localizedStandardContains("timer") else { return false }
        let phrases = [
            "how many", "what alarm", "what alarms", "which alarm", "which alarms",
            "what are my alarms", "what's my alarm",
            "alarms do i", "alarm do i",
            "list", "show", "next alarm", "do i have"
        ]
        return phrases.contains { folded.localizedStandardContains($0) }
    }

    private static func change(in question: String, folded: String) -> AskAlarmChange {
        let marks = clocks(in: folded)
        var change = AskAlarmChange(repeats: namedRepeats(in: folded), title: namedTitle(in: question))
        if marks.count >= 2 {
            change.matchHour = marks[0].hour
            change.matchMinute = marks[0].minute
            change.hour = marks[marks.count - 1].hour
            change.minute = marks[marks.count - 1].minute
        } else if let only = marks.first {
            if only.destination {
                change.hour = only.hour
                change.minute = only.minute
            } else {
                change.matchHour = only.hour
                change.matchMinute = only.minute
            }
        }
        return change
    }

    /// A repeat the question named. Nil when the question leaves the current repeat alone.
    /// A weekday name is a change. A new alarm still uses `repeats(in:)`, so Saturday stays the next Saturday.
    private static func namedRepeats(in folded: String) -> AskAlarmRepeat? {
        if folded.localizedStandardContains("weekday") { return .weekdays }
        if folded.localizedStandardContains("weekend") { return .weekends }
        if folded.localizedStandardContains("every day")
            || folded.localizedStandardContains("daily")
            || folded.localizedStandardContains("recurring") {
            return .daily
        }
        let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let day = days.first(where: { folded.localizedStandardContains($0) }) {
            return .weekday(day)
        }
        if folded.localizedStandardContains("don't repeat")
            || folded.localizedStandardContains("do not repeat")
            || folded.localizedStandardContains("once") {
            return .never
        }
        if folded.localizedStandardContains("repeat") { return .daily }
        return nil
    }

    private static func repeats(in folded: String) -> AskAlarmRepeat {
        if folded.localizedStandardContains("weekday") { return .weekdays }
        if folded.localizedStandardContains("weekend") { return .weekends }
        if folded.localizedStandardContains("every day")
            || folded.localizedStandardContains("daily")
            || folded.localizedStandardContains("recurring") {
            return .daily
        }
        if folded.localizedStandardContains("repeat"),
           !folded.localizedStandardContains("don't repeat"),
           !folded.localizedStandardContains("do not repeat") {
            return .daily
        }
        return .never
    }

    private static func namedTitle(in question: String) -> String? {
        let pattern = #"(?i)\b(?:called|named|titled)\s+(.+?)(?:\s+(?:for|at|on)\b|[.,]|$)"#
        guard let result = matches(pattern, in: question).first,
              let text = capture(result, group: 1, in: question) else { return nil }
        return AskAlarmText.title(text)
    }

    /// A custom button title named in the question, such as "custom button of awesome".
    private static func namedLabel(in question: String) -> String? {
        let patterns = [
            #"(?i)\b(?:custom\s+)?button\s+(?:of|called|named|saying|labeled|labelled)\s+(.+?)(?:\s+(?:and|with|for|at|on)\b|[.,]|$)"#,
            #"(?i)\bbutton\s+title\s+(.+?)(?:\s+(?:and|with|for|at|on)\b|[.,]|$)"#
        ]
        for pattern in patterns {
            guard let result = matches(pattern, in: question).first,
                  let text = capture(result, group: 1, in: question) else { continue }
            if let label = AskAlarmText.label(text) { return label }
        }
        return nil
    }

    /// An SF Symbol named in the question, such as "symbol of food" or "with a food symbol".
    private static func namedSymbol(in question: String) -> String? {
        let patterns = [
            #"(?i)\b(?:sf\s+)?symbol\s+(?:of|called|named|for)\s+([A-Za-z][A-Za-z0-9.]{0,63})"#,
            #"(?i)\bwith\s+a\s+([A-Za-z][A-Za-z0-9.]{0,63})\s+symbol\b"#
        ]
        for pattern in patterns {
            guard let result = matches(pattern, in: question).first,
                  let text = capture(result, group: 1, in: question) else { continue }
            if let symbol = AskAlarmText.symbol(text) { return symbol }
        }
        return nil
    }

    private static func collectTimers(in text: String, into marks: inout [Mark]) {
        let pattern = #"(?<!\d)(\d{1,3})\s*(?:minutes|minute|mins|min)\b"#
        for result in matches(pattern, in: text) {
            guard let minutes = number(result, group: 1, in: text), (1...720).contains(minutes) else { continue }
            marks.append(Mark(start: result.range.location, end: result.range.location + result.range.length, hour: nil, minute: 0, after: minutes))
        }
    }

    private struct ClockMark {
        var start: Int
        var end: Int
        var hour: Int
        var minute: Int
        /// The clock was introduced with to, for, or at, so a single clock is the new time.
        var destination: Bool
    }

    private static func clocks(in text: String) -> [ClockMark] {
        var marks: [ClockMark] = []
        let pattern = #"(?<!\d)(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b"#
        for result in matches(pattern, in: text) {
            guard let raw = number(result, group: 1, in: text),
                  let suffix = capture(result, group: 3, in: text),
                  let hour = clockHour(raw, suffix: suffix) else { continue }
            let minute = number(result, group: 2, in: text) ?? 0
            guard (0...59).contains(minute) else { continue }
            marks.append(ClockMark(
                start: result.range.location,
                end: result.range.location + result.range.length,
                hour: hour,
                minute: minute,
                destination: destination(text, before: result.range.location)
            ))
        }
        let bare = #"(?:\bto|\bat|\bfor)\s+(\d{1,2})(?::(\d{2}))?\b(?!\s*(?:a\.?m\.?|p\.?m\.?|minutes|minute|mins|min|hours|hour))"#
        for result in matches(bare, in: text) {
            guard !overlaps(result.range, marks: marks) else { continue }
            guard let raw = number(result, group: 1, in: text), let hour = clockHour(raw, suffix: nil) else { continue }
            let minute = number(result, group: 2, in: text) ?? 0
            guard (0...59).contains(minute) else { continue }
            marks.append(ClockMark(
                start: result.range.location,
                end: result.range.location + result.range.length,
                hour: hour,
                minute: minute,
                destination: true
            ))
        }
        marks.sort { $0.start < $1.start }
        return marks
    }

    private static func destination(_ text: String, before location: Int) -> Bool {
        guard location > 0 else { return false }
        let head = (text as NSString).substring(to: location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return head.hasSuffix(" to") || head.hasSuffix(" for") || head.hasSuffix(" at")
            || head == "to" || head == "for" || head == "at"
    }

    private static func clockHour(_ raw: Int, suffix: String?) -> Int? {
        if let suffix {
            guard (1...12).contains(raw) else { return nil }
            let afternoon = suffix.first == "p"
            if raw == 12 { return afternoon ? 12 : 0 }
            return afternoon ? raw + 12 : raw
        }
        guard (0...23).contains(raw) else { return nil }
        return raw
    }

    private static func overlaps(_ range: NSRange, marks: [ClockMark]) -> Bool {
        let end = range.location + range.length
        return marks.contains { range.location < $0.end && end > $0.start }
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range)
    }

    private static func number(_ result: NSTextCheckingResult, group: Int, in text: String) -> Int? {
        guard let capture = capture(result, group: group, in: text) else { return nil }
        return Int(capture)
    }

    private static func capture(_ result: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard group < result.numberOfRanges else { return nil }
        let range = result.range(at: group)
        guard range.location != NSNotFound, let swift = Range(range, in: text) else { return nil }
        let captured = String(text[swift]).trimmingCharacters(in: .whitespacesAndNewlines)
        return captured.isEmpty ? nil : captured
    }
}

enum AskAlarmText {
    static func title(_ raw: String?) -> String? {
        clip(raw, limit: 80)
    }

    static func label(_ raw: String?) -> String? {
        clip(raw, limit: 32)
    }

    static func symbol(_ raw: String?) -> String? {
        guard let text = clip(raw, limit: 64) else { return nil }
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        if let alias = symbolAliases[folded] { return alias }
        guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." }) else { return nil }
        guard text.contains(where: \.isLetter) else { return nil }
        return text
    }

    /// Everyday words the person may say instead of an SF Symbol name.
    private static let symbolAliases: [String: String] = [
        "food": "fork.knife",
        "meal": "fork.knife",
        "restaurant": "fork.knife",
        "coffee": "cup.and.saucer.fill",
        "car": "car.fill",
        "drive": "car.fill",
        "sun": "sunrise.fill",
        "sunrise": "sunrise.fill",
        "bed": "bed.double.fill",
        "sleep": "bed.double.fill",
        "gym": "figure.run",
        "workout": "figure.run",
        "music": "music.note",
        "home": "house.fill",
        "work": "briefcase.fill"
    ]

    static func actionID(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else {
            return nil
        }
        let clipped = String(text.prefix(64))
        guard clipped.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return clipped
    }

    static func repeats(_ raw: String?) -> AskAlarmRepeat {
        let word = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            ?? ""
        switch word {
        case "", "never", "once", "no":
            return .never
        case "daily", "everyday", "every day":
            return .daily
        case "weekday", "weekdays":
            return .weekdays
        case "weekend", "weekends":
            return .weekends
        case "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday":
            return .weekday(word)
        default:
            return .never
        }
    }

    private static func clip(_ raw: String?, limit: Int) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: " · ", with: " ")
        text = text.replacingOccurrences(of: "=", with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(limit))
    }
}

enum AskAlarmLine {
    struct Item: Equatable {
        var title: String
        var time: String
        var repeats: String
        var label: String?
        var symbol: String?
        /// "on" or "paused" for an alarm that was already scheduled. Nil for one this turn added or changed.
        var state: String?
    }

    static func line(_ draft: AskAlarmDraft) -> String {
        line(draft, prefix: AskAppleCopy.addedPrefix)
    }

    static func updated(_ draft: AskAlarmDraft) -> String {
        line(draft, prefix: AskAppleCopy.updatedPrefix)
    }

    static func removed(time: String) -> String {
        AskAppleCopy.removedPrefix + time
    }

    static func line(_ draft: AskAlarmDraft, prefix: String) -> String {
        line(
            title: draft.title,
            time: time(draft),
            repeats: draft.repeats.phrase,
            label: draft.label,
            symbol: draft.symbol,
            prefix: prefix
        )
    }

    static func line(title: String, time: String, repeats: String, label: String?, symbol: String?, prefix: String = AskAppleCopy.addedPrefix) -> String {
        var parts = ["\(prefix)\(title)", time, repeats]
        if let label, !label.isEmpty {
            parts.append(label)
            if let symbol, !symbol.isEmpty {
                parts.append(symbol)
            }
        }
        return parts.joined(separator: " · ")
    }

    static func clock(hour: Int, minute: Int) -> String {
        let suffix = hour >= 12 ? "PM" : "AM"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12):\(String(format: "%02d", minute)) \(suffix)"
    }

    static func item(from line: String) -> Item? {
        if let written = writeItem(from: line) { return written }
        return AskAlarmList.item(from: line)
    }

    private static func writeItem(from line: String) -> Item? {
        let prefix: String
        if line.hasPrefix(AskAppleCopy.addedPrefix) {
            prefix = AskAppleCopy.addedPrefix
        } else if line.hasPrefix(AskAppleCopy.updatedPrefix) {
            prefix = AskAppleCopy.updatedPrefix
        } else {
            return nil
        }
        let parts = line.components(separatedBy: " · ")
        guard parts.count >= 2 else { return nil }
        let title = String(parts[0].dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let repeats = parts.count >= 3 ? parts[2] : "once"
        let label = parts.count >= 4 ? parts[3] : nil
        let symbol = parts.count >= 5 ? parts[4] : nil
        return Item(title: title, time: parts[1], repeats: repeats, label: label, symbol: symbol)
    }

    static func spoken(_ lines: [String]) -> String? {
        if let listed = AskAlarmList.spoken(lines: lines) { return listed }
        let items = lines.compactMap(item(from:)).filter { $0.state == nil }
        guard !items.isEmpty else { return nil }
        if items.count == 1 {
            var sentence = when(items[0])
            if items[0].repeats != "once" {
                sentence += ", \(items[0].repeats)"
            }
            sentence += "."
            if let label = items[0].label, !label.isEmpty {
                sentence += " The button is \(label)."
            }
            return sentence
        }
        let list = items.map(when).joined(separator: ", ")
        return "Set \(items.count) alarms: \(list)."
    }

    /// Added lines that match the question. A failure beside an alarm that was added is dropped, so the card is not titled with that failure.
    /// When nothing was added, the failure lines stay and the sentence can say so.
    static func kept(
        _ lines: [String],
        matching question: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        if case .list = AskAlarmCommand.intent(in: question, now: now, calendar: calendar) {
            let listed = lines.filter { AskAlarmList.item(from: $0) != nil }
            if !listed.isEmpty { return listed }
            return lines.filter { $0 == "No alarms." || isStatus($0) }
        }
        let added = lines.filter { line in
            guard let item = item(from: line) else { return false }
            return item.state == nil
        }
        guard !added.isEmpty else { return lines }
        let drafts = AskAlarmCommand.drafts(in: question, now: now, calendar: calendar)
        guard !drafts.isEmpty else { return added }
        let matched = added.filter { line in
            guard let item = item(from: line) else { return false }
            return drafts.contains { matches(item, $0) }
        }
        return matched.isEmpty ? added : matched
    }

    /// The bubble for an alarms-only turn. An added alarm is said from the question, not from a sentence about a reminder.
    /// A count stays a count. Another Apple source in the same turn keeps its own sentence.
    static func speech(_ text: String, readings: [AskAppleReading], question: String = "") -> String {
        let others = readings.contains { $0.name != "alarms" && !$0.lines.isEmpty }
        guard !others else { return text }
        let intent = AskAlarmCommand.intent(in: question)
        if case .needsTime = intent { return "Say a time." }
        let lines = readings.filter { $0.name == "alarms" }.flatMap(\.lines)
        if case .list = intent {
            if lines.isEmpty { return "You have no alarms on." }
            return listSpeech(kept(lines, matching: question))
        }
        if case .remove = intent {
            if let spoken = removalSpeech(lines) { return spoken }
            let status = lines.filter(isStatus)
            if !status.isEmpty { return status.joined(separator: " ") }
            return text
        }
        guard !lines.isEmpty else { return text }
        let keptLines = kept(lines, matching: question)
        let drafts = AskAlarmCommand.drafts(in: question)
        if !drafts.isEmpty, covers(keptLines, drafts: drafts), let spoken = spoken(drafts.map(line)) {
            return spoken
        }
        if let spoken = spoken(keptLines) { return spoken }
        let status = keptLines.filter(isStatus)
        if !status.isEmpty, status.count == keptLines.count {
            return status.joined(separator: " ")
        }
        return text
    }

    private static func listSpeech(_ lines: [String]) -> String {
        if let spoken = AskAlarmList.spoken(lines: lines) { return spoken }
        let status = lines.filter(isStatus)
        if !status.isEmpty { return status.joined(separator: " ") }
        return "You have no alarms on."
    }

    private static func removalSpeech(_ lines: [String]) -> String? {
        let times = lines.compactMap { line -> String? in
            guard line.hasPrefix(AskAppleCopy.removedPrefix) else { return nil }
            let time = line.dropFirst(AskAppleCopy.removedPrefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return time.isEmpty ? nil : time
        }
        if times.count == 1 {
            let time = times[0]
            if time.hasPrefix("in ") { return "Removed the timer." }
            return "Removed the \(time) alarm."
        }
        if times.count > 1 { return "Removed \(times.count) alarms." }
        return nil
    }

    private static func matches(_ item: Item, _ draft: AskAlarmDraft) -> Bool {
        item.time == time(draft)
    }

    private static func covers(_ lines: [String], drafts: [AskAlarmDraft]) -> Bool {
        let items = lines.compactMap(item(from:))
        guard !items.isEmpty, items.count >= drafts.count else { return false }
        return drafts.allSatisfy { draft in
            items.contains { matches($0, draft) }
        }
    }

    private static func isStatus(_ line: String) -> Bool {
        line == AskAppleCopy.denied
            || line == "Alarm isn't available."
            || line == "Too many alarms."
            || line == "A title is needed."
            || line == "Say a time."
            || line == "Say which alarm to change."
            || line == "No alarm at that time."
            || line == "Use an hour from 0 to 23, or a timer from 1 to 720 minutes."
    }

    static func time(_ draft: AskAlarmDraft) -> String {
        if draft.hour == nil, let minutes = draft.afterMinutes {
            return minutes == 1 ? "in 1 minute" : "in \(minutes) minutes"
        }
        return clock(hour: draft.hour ?? 0, minute: draft.minute)
    }

    private static func when(_ item: Item) -> String {
        if item.time.hasPrefix("in ") {
            return "\(item.title) \(item.time)"
        }
        return "\(item.title) at \(item.time)"
    }
}

struct AskAlarmCard: View {
    var item: AskAlarmLine.Item

    private var customized: Bool {
        if let label = item.label, !label.isEmpty { return true }
        if let symbol = item.symbol, !symbol.isEmpty { return true }
        return false
    }

    private var buttonSymbol: String {
        item.symbol ?? "bell.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.time)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AskCardBadge(
                    title: customized ? "Custom" : "Alarm",
                    symbol: customized ? buttonSymbol : "alarm.fill",
                    tint: .orange
                )
            }
            Text(item.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            if item.repeats != "once" {
                Text(item.repeats)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if item.state == "paused" {
                Text("paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let label = item.label, !label.isEmpty {
                Label(label, systemImage: buttonSymbol)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .accessibilityLabel("Alarm button, \(label)")
            } else if let symbol = item.symbol, !symbol.isEmpty {
                Label("Custom", systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .accessibilityLabel("Alarm button, custom symbol \(symbol)")
            }
        }
        .askCardSurface(tint: .orange)
        .accessibilityElement(children: .combine)
    }
}

/// A scheduled alarm, as a line the card can show. Building a row does not open AlarmManager.
enum AskAlarmList {
    static func row(
        schedule: Alarm.Schedule?,
        countdown: TimeInterval?,
        state: Alarm.State,
        calendar: Calendar = .current
    ) -> String {
        let word = stateWord(state)
        if let schedule, let clock = AskAlarmClock.clock(schedule, calendar: calendar) {
            let repeats: String
            if case .relative(let relative) = schedule {
                repeats = AskAlarmClock.phrase(relative.repeats)
            } else {
                repeats = "once"
            }
            let time = AskAlarmLine.clock(hour: clock.hour, minute: clock.minute)
            return "\(time) · \(repeats) · \(word)"
        }
        if let countdown {
            let minutes = max(1, Int((countdown / 60).rounded()))
            let time = minutes == 1 ? "in 1 minute" : "in \(minutes) minutes"
            return "\(time) · once · \(word)"
        }
        return "Alarm · once · \(word)"
    }

    static func item(from line: String) -> AskAlarmLine.Item? {
        let parts = line.components(separatedBy: " · ")
        guard parts.count == 3 else { return nil }
        let state = parts[2]
        guard state == "on" || state == "paused" else { return nil }
        let time = parts[0]
        let repeats = parts[1]
        guard !time.isEmpty, !repeats.isEmpty else { return nil }
        if time.hasPrefix(AskAppleCopy.addedPrefix)
            || time.hasPrefix(AskAppleCopy.updatedPrefix)
            || time.hasPrefix(AskAppleCopy.removedPrefix) {
            return nil
        }
        return AskAlarmLine.Item(title: "Alarm", time: time, repeats: repeats, label: nil, symbol: nil, state: state)
    }

    static func spoken(lines: [String]) -> String? {
        let items = lines.compactMap(item(from:))
        if items.isEmpty {
            return lines.contains("No alarms.") ? "You have no alarms on." : nil
        }
        if items.count == 1 {
            return "You have 1 alarm on, \(clause(items[0]))."
        }
        let list = items.map { clause($0) }.joined(separator: ", ")
        return "You have \(items.count) alarms on: \(list)."
    }

    private static func clause(_ item: AskAlarmLine.Item) -> String {
        var parts: [String] = []
        if item.time.hasPrefix("in ") {
            parts.append(item.time)
        } else {
            parts.append("at \(item.time)")
        }
        if item.repeats != "once" { parts.append(item.repeats) }
        if item.state == "paused" { parts.append("paused") }
        return parts.joined(separator: ", ")
    }

    private static func stateWord(_ state: Alarm.State) -> String {
        switch state {
        case .paused: "paused"
        case .scheduled, .countdown, .alerting: "on"
        @unknown default: "on"
        }
    }
}

@Generable
struct AskAlarmToolDraft {
    @Guide(description: "Short alarm name, such as Wake up.")
    var title: String
    @Guide(description: "Hour from 0 to 23 for a clock alarm. Leave empty for a timer.", .range(0...23))
    var hour: Int?
    @Guide(description: "Minute from 0 to 59. Use 0 when only the hour was said.", .range(0...59))
    var minute: Int?
    @Guide(description: "0 is today. Leave empty for the next time that hour comes, for a repeating alarm, or for a timer.", .range(0...AskCalendarWindow.maximumOffset))
    var day: Int?
    @Guide(description: "Minutes from now for a timer, from 1 to 720. Leave empty for a clock alarm.", .range(1...720))
    var after: Int?
    @Guide(description: "never, daily, weekdays, weekends, or a weekday name such as monday. Leave empty for once.", .anyOf(AskAlarmRepeat.choices))
    var repeats: String?
    @Guide(description: "Button title the person asked for, such as Awesome or Garage. Leave empty for no custom button.")
    var label: String?
    @Guide(description: "SF Symbol for that button, such as fork.knife or sunrise.fill. Everyday words such as food are fine. Leave empty for no custom button.")
    var symbol: String?
    @Guide(description: "Registered action id from the tool's list, such as open. Do not put the button title here. Leave empty when only the label or symbol was asked for.")
    var action: String?
}

struct AskAlarmTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    /// The question this turn asked. An alarm whose time is not in it is not scheduled.
    var question = ""
    let name = "alarms"

    var description: String {
        let menu = AskCalendarWindow.dayMenu(now: Date(), calendar: .current)
        let actions = AskAlarms.menu()
        return """
        Read, change, remove, or schedule alarms with one call. \
        For a count or a list, pass action read and leave alarms empty. Do not add an alarm. \
        To change one, pass action update, the current hour, and the new hour or repeats. \
        To make alarms recurring, pass repeats daily, weekdays, weekends, or a weekday name. \
        To remove one, pass action delete and its hour. Leave the hour empty only when every alarm should go. \
        To set alarms, pass action add and one entry per alarm, at most 8. \
        For a clock alarm pass the title, the hour from 0 to 23, and the minute. \
        Copy a day number from this list when the person names a day: \(menu). Leave the day empty for the next time that hour comes, or for a repeating alarm. \
        For a timer pass after as the minutes from now and leave the hour empty. \
        Pass label for the button title the person asked for, and symbol for its icon. \
        symbol is an SF Symbol name such as fork.knife or sunrise.fill; everyday words such as food map to a symbol. \
        The action inside an alarm entry is a registered button id, one of: \(actions). \
        Do not put the button title in action. An id that is not in the list is ignored; label and symbol still make an Open button. \
        A set alarm starts with Added. A list line is the time, how it repeats, and on or paused. \
        If the result is Not allowed, say you cannot see the alarms. Do not invent an alarm.
        """
    }

    @Generable
    struct Arguments {
        @Guide(description: "read, add, update, or delete. Use read to list alarms that are on. Use add only when this question asks to set an alarm.", .anyOf(["read", "add", "update", "delete"]))
        var action: String?
        @Guide(description: "Alarms to add, or the one alarm to change or remove. Leave empty for a read.", .maximumCount(8))
        var alarms: [AskAlarmToolDraft]
    }

    func call(arguments: Arguments) async throws -> String {
        let model = modelDrafts(arguments.alarms)
        switch AskAlarmCommand.intent(in: question) {
        case .list:
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "read") {
                await AskAlarmRead.listing()
            }
        case .remove(let removal):
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "delete") {
                await AskAlarmRead.remove(removal)
            }
        case .change(let change):
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "update") {
                await AskAlarmRead.change(change)
            }
        case .needsTime:
            return "Say a time."
        case .set(let asked):
            let chosen = AskAlarmCommand.matching(model, asked: asked)
            let scheduling = chosen.isEmpty ? asked : chosen
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: summary(scheduling)) {
                await AskAlarms.schedule(scheduling)
            }
        case .none:
            return try await modelAction(arguments.action, drafts: model)
        }
    }

    private func modelDrafts(_ alarms: [AskAlarmToolDraft]) -> [AskAlarmDraft] {
        let fields = alarms.map {
            AskAlarmCommand.Field(
                title: $0.title,
                hour: $0.hour,
                minute: $0.minute,
                day: $0.day,
                after: $0.after,
                repeats: $0.repeats,
                label: $0.label,
                symbol: $0.symbol,
                action: $0.action
            )
        }
        guard case .drafts(let drafts) = AskAlarmCommand.parse(fields) else { return [] }
        return drafts
    }

    /// The question named no alarm action. A read, update, or delete from the model can run. An add does not.
    private func modelAction(_ action: String?, drafts: [AskAlarmDraft]) async throws -> String {
        let word = action?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch word {
        case "read":
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "read") {
                await AskAlarmRead.listing()
            }
        case "delete":
            guard let hour = drafts.first?.hour else { return "Say which alarm to change." }
            let removal = AskAlarmRemoval(hour: hour, minute: drafts.first?.minute ?? 0)
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "delete") {
                await AskAlarmRead.remove(removal)
            }
        case "update":
            guard let draft = drafts.first else { return "Say which alarm to change." }
            let change = AskAlarmChange(
                hour: draft.hour,
                minute: draft.minute,
                repeats: draft.repeats == .never ? nil : draft.repeats
            )
            guard change.hour != nil || change.repeats != nil else { return "Say which alarm to change." }
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "update") {
                await AskAlarmRead.change(change)
            }
        default:
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "skip") { "" }
        }
    }

    private func summary(_ drafts: [AskAlarmDraft]) -> String {
        drafts.map { draft in
            if draft.hour == nil, let minutes = draft.afterMinutes {
                return "\(draft.title) \(minutes)m"
            }
            return "\(draft.title) \(draft.hour ?? 0):\(draft.minute)"
        }.joined(separator: " | ")
    }
}

struct AskAlarmMetadata: AlarmMetadata {}

enum AskAlarmRead {
    static func listing() async -> String {
        switch await load() {
        case .denied:
            return AskAppleCopy.denied
        case .unavailable:
            return "Alarm isn't available."
        case .alarms(let alarms):
            if alarms.isEmpty { return "No alarms." }
            let calendar = Calendar.current
            return alarms.map { alarm in
                AskAlarmList.row(
                    schedule: alarm.schedule,
                    countdown: alarm.countdownDuration?.preAlert ?? alarm.countdownDuration?.postAlert,
                    state: alarm.state,
                    calendar: calendar
                )
            }.joined(separator: "\n")
        }
    }

    static func change(_ request: AskAlarmChange) async -> String {
        switch await load() {
        case .denied:
            return AskAppleCopy.denied
        case .unavailable:
            return "Alarm isn't available."
        case .alarms(let alarms):
            let calendar = Calendar.current
            let described = alarms.compactMap { alarm -> (Alarm, Int, Int, AskAlarmRepeat)? in
                guard let clock = AskAlarmClock.clock(alarm.schedule, calendar: calendar) else { return nil }
                return (alarm, clock.hour, clock.minute, clock.repeats)
            }
            let matches: [(Alarm, Int, Int, AskAlarmRepeat)]
            if let hour = request.matchHour {
                let minute = request.matchMinute ?? 0
                matches = described.filter { $0.1 == hour && $0.2 == minute }
                if matches.isEmpty { return "No alarm at that time." }
            } else {
                let updatesAll = request.hour == nil && request.repeats != nil
                if !updatesAll && described.count != 1 {
                    return described.isEmpty ? "No alarm at that time." : "Say which alarm to change."
                }
                if described.isEmpty { return "No alarm at that time." }
                matches = described
            }
            var lines: [String] = []
            for (alarm, hour, minute, repeats) in matches {
                let draft = AskAlarmDraft(
                    title: request.title ?? "Alarm",
                    hour: request.hour ?? hour,
                    minute: request.hour == nil ? minute : (request.minute ?? 0),
                    repeats: request.repeats ?? repeats
                )
                guard let configuration = configuration(for: draft, id: alarm.id) else {
                    lines.append("Use an hour from 0 to 23, or a timer from 1 to 720 minutes.")
                    continue
                }
                do {
                    // The same id replaces the alarm. Cancelling first would drop it if the new schedule fails.
                    _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
                    lines.append(AskAlarmLine.updated(draft))
                } catch let error as AlarmManager.AlarmError {
                    lines.append(error == .maximumLimitReached ? "Too many alarms." : "Alarm isn't available.")
                    if error == .maximumLimitReached { break }
                } catch {
                    lines.append("Alarm isn't available.")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    static func remove(_ request: AskAlarmRemoval) async -> String {
        switch await load() {
        case .denied:
            return AskAppleCopy.denied
        case .unavailable:
            return "Alarm isn't available."
        case .alarms(let alarms):
            let calendar = Calendar.current
            let targets: [Alarm]
            if let hour = request.hour {
                let minute = request.minute ?? 0
                targets = alarms.filter { alarm in
                    guard let clock = AskAlarmClock.clock(alarm.schedule, calendar: calendar) else { return false }
                    return clock.hour == hour && clock.minute == minute
                }
                if targets.isEmpty { return "No alarm at that time." }
            } else {
                targets = alarms
                if targets.isEmpty { return "No alarms." }
            }
            var lines: [String] = []
            for alarm in targets {
                let time = AskAlarmClock.clock(alarm.schedule, calendar: calendar).map {
                    AskAlarmLine.clock(hour: $0.hour, minute: $0.minute)
                } ?? timerPhrase(alarm)
                do {
                    try AlarmManager.shared.cancel(id: alarm.id)
                    lines.append(AskAlarmLine.removed(time: time))
                } catch {
                    lines.append("Alarm isn't available.")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    static func schedule(_ drafts: [AskAlarmDraft]) async -> String {
        guard await allowed() else { return AskAppleCopy.denied }
        var lines: [String] = []
        for draft in drafts {
            let id = UUID()
            guard let configuration = configuration(for: draft, id: id) else {
                lines.append("Use an hour from 0 to 23, or a timer from 1 to 720 minutes.")
                continue
            }
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                lines.append(AskAlarmLine.line(shown(draft)))
            } catch let error as AlarmManager.AlarmError {
                lines.append(error == .maximumLimitReached ? "Too many alarms." : "Alarm isn't available.")
                if error == .maximumLimitReached { break }
            } catch {
                lines.append("Alarm isn't available.")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func configuration(
        for draft: AskAlarmDraft,
        id: UUID
    ) -> AlarmManager.AlarmConfiguration<AskAlarmMetadata>? {
        guard let when = AskAlarmCommand.schedule(for: draft) else { return nil }
        let registered = AskAlarms.action(id: draft.actionID)
        let choice = AskAlarmButtonPlan.choice(
            draft: draft,
            registered: registered.map { ($0.id, $0.label, $0.symbol) }
        )
        let secondary = choice.map {
            AlarmButton(
                text: LocalizedStringResource(stringLiteral: $0.label),
                textColor: .white,
                systemImageName: $0.symbol
            )
        }
        let title = LocalizedStringResource(stringLiteral: draft.title)
        let alert = AlarmPresentation.Alert(
            title: title,
            secondaryButton: secondary,
            secondaryButtonBehavior: secondary == nil ? nil : .custom
        )
        let presentation: AlarmPresentation
        if case .timer = when {
            presentation = AlarmPresentation(
                alert: alert,
                countdown: .init(
                    title: title,
                    pauseButton: AlarmButton(text: "Pause", textColor: .white, systemImageName: "pause.fill")
                ),
                paused: .init(
                    title: title,
                    resumeButton: AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.fill")
                )
            )
        } else {
            presentation = AlarmPresentation(alert: alert)
        }
        let attributes = AlarmAttributes<AskAlarmMetadata>(presentation: presentation, tintColor: .orange)
        let intent: (any LiveActivityIntent)? = choice.flatMap { choice in
            if let action = AskAlarms.action(id: choice.actionID) {
                return action.intent(id, draft.title)
            }
            return AskAlarmOpenIntent(alarmID: id.uuidString)
        }
        switch when {
        case .timer(let minutes):
            return .timer(duration: TimeInterval(minutes * 60), attributes: attributes, secondaryIntent: intent)
        case .fixed(let day, let hour, let minute):
            guard let date = AskAlarmClock.date(day: day, hour: hour, minute: minute) else { return nil }
            return .alarm(schedule: .fixed(date), attributes: attributes, secondaryIntent: intent)
        case .relative(let hour, let minute, let repeats):
            let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
            let schedule = Alarm.Schedule.relative(
                .init(time: time, repeats: AskAlarmClock.recurrence(repeats))
            )
            return .alarm(schedule: schedule, attributes: attributes, secondaryIntent: intent)
        }
    }

    private static func shown(_ draft: AskAlarmDraft) -> AskAlarmDraft {
        let registered = AskAlarms.action(id: draft.actionID)
        let choice = AskAlarmButtonPlan.choice(
            draft: draft,
            registered: registered.map { ($0.id, $0.label, $0.symbol) }
        )
        var copy = draft
        copy.label = choice?.label
        copy.symbol = choice?.symbol
        copy.repeats = draft.hour == nil ? .never : draft.repeats
        return copy
    }

    private enum Loaded {
        case denied
        case unavailable
        case alarms([Alarm])
    }

    private static func load() async -> Loaded {
        guard await allowed() else { return .denied }
        do {
            return .alarms(try AlarmManager.shared.alarms)
        } catch {
            return .unavailable
        }
    }

    private static func timerPhrase(_ alarm: Alarm) -> String {
        let seconds = alarm.countdownDuration?.preAlert ?? alarm.countdownDuration?.postAlert
        guard let seconds else { return "alarm" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return minutes == 1 ? "in 1 minute" : "in \(minutes) minutes"
    }

    private static func allowed() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        @unknown default:
            return false
        }
    }
}

enum AskAlarmClock {
    static func clock(
        _ schedule: Alarm.Schedule?,
        calendar: Calendar = .current
    ) -> (hour: Int, minute: Int, repeats: AskAlarmRepeat)? {
        guard let schedule else { return nil }
        switch schedule {
        case .fixed(let date):
            return (calendar.component(.hour, from: date), calendar.component(.minute, from: date), .never)
        case .relative(let relative):
            return (relative.time.hour, relative.time.minute, repeats(relative.repeats))
        @unknown default:
            return nil
        }
    }

    static func phrase(_ recurrence: Alarm.Schedule.Relative.Recurrence) -> String {
        switch recurrence {
        case .never:
            return "once"
        case .weekly(let days):
            let set = Set(days)
            if set == everyDay { return "daily" }
            if set == weekdays { return "weekdays" }
            if set == weekends { return "weekends" }
            if set.count == 1, let day = set.first, let name = weekdayName(day) {
                return AskAlarmRepeat.weekday(name).phrase
            }
            return "weekly"
        @unknown default:
            return "weekly"
        }
    }

    static func repeats(_ recurrence: Alarm.Schedule.Relative.Recurrence) -> AskAlarmRepeat {
        switch recurrence {
        case .never:
            return .never
        case .weekly(let days):
            let set = Set(days)
            if set == everyDay { return .daily }
            if set == weekdays { return .weekdays }
            if set == weekends { return .weekends }
            if set.count == 1, let day = set.first, let name = weekdayName(day) {
                return .weekday(name)
            }
            return .never
        @unknown default:
            return .never
        }
    }

    static func date(day: Int, hour: Int, minute: Int, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let window = AskCalendarWindow.day(offset: day, now: now, calendar: calendar) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: window.start)
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)
    }

    static func recurrence(_ repeats: AskAlarmRepeat) -> Alarm.Schedule.Relative.Recurrence {
        switch repeats {
        case .never:
            return .never
        case .daily:
            return .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        case .weekdays:
            return .weekly([.monday, .tuesday, .wednesday, .thursday, .friday])
        case .weekends:
            return .weekly([.saturday, .sunday])
        case .weekday(let name):
            guard let day = weekday(name) else { return .never }
            return .weekly([day])
        }
    }

    private static let everyDay: Set<Locale.Weekday> = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday
    ]
    private static let weekdays: Set<Locale.Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    private static let weekends: Set<Locale.Weekday> = [.saturday, .sunday]

    private static func weekday(_ name: String) -> Locale.Weekday? {
        switch name {
        case "sunday": .sunday
        case "monday": .monday
        case "tuesday": .tuesday
        case "wednesday": .wednesday
        case "thursday": .thursday
        case "friday": .friday
        case "saturday": .saturday
        default: nil
        }
    }

    private static func weekdayName(_ day: Locale.Weekday) -> String? {
        switch day {
        case .sunday: "sunday"
        case .monday: "monday"
        case .tuesday: "tuesday"
        case .wednesday: "wednesday"
        case .thursday: "thursday"
        case .friday: "friday"
        case .saturday: "saturday"
        @unknown default: nil
        }
    }
}

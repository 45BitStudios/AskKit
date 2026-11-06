import AppIntents
import AskKitSurface
#if canImport(Contacts)
import Contacts
#endif
import CoreLocation
#if canImport(EventKit)
import EventKit
#endif
import Foundation
#if ASK_FOUNDATION_MODELS
import FoundationModels
#endif
#if canImport(HealthKit)
import HealthKit
#endif
import MapKit
import SwiftUI
import os

/// Apple sources a reply may use. Calendar and reminders can add, change, and remove. Contacts can add. Music can pause, skip, and go back. Alarms can add.
/// Nothing is on until the app sets it.
/// The host app still owns the usage strings and entitlements.
public struct AskAppleAccess: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let calendar = AskAppleAccess(rawValue: 1 << 0)
    public static let reminders = AskAppleAccess(rawValue: 1 << 1)
    public static let contacts = AskAppleAccess(rawValue: 1 << 2)
    public static let location = AskAppleAccess(rawValue: 1 << 3)
    public static let health = AskAppleAccess(rawValue: 1 << 4)
    public static let music = AskAppleAccess(rawValue: 1 << 5)
    public static let weather = AskAppleAccess(rawValue: 1 << 6)
    public static let alarms = AskAppleAccess(rawValue: 1 << 7)
}

extension AskAppleAccess {
    /// The sources this platform can read. The others are never offered to the model or the composer.
    /// Apple TV has no Calendar, Reminders, Contacts, or Health. Alarms are iPhone and iPad only.
    public static var available: AskAppleAccess {
        var access: AskAppleAccess = [.location, .music, .weather]
#if canImport(EventKit)
        access.formUnion([.calendar, .reminders])
#endif
#if canImport(Contacts)
        access.insert(.contacts)
#endif
#if canImport(HealthKit)
        access.insert(.health)
#endif
#if canImport(AlarmKit)
        access.insert(.alarms)
#endif
        return access
    }
}

/// One Apple source the composer can list.
package struct AskAppleSource: Identifiable, Sendable {
    package var id: String { name }
    var name: String
    package var access: AskAppleAccess
    package var title: String
    package var symbol: String
    package var detail: String

    /// The sources this platform can read, in composer order.
    package static let catalog: [AskAppleSource] = everySource.filter { AskAppleAccess.available.contains($0.access) }

    private static let everySource: [AskAppleSource] = [
        AskAppleSource(
            name: "calendar",
            access: .calendar,
            title: "Calendar",
            symbol: "calendar",
            detail: "Read, add, change, or remove events"
        ),
        AskAppleSource(
            name: "reminders",
            access: .reminders,
            title: "Reminders",
            symbol: "checklist",
            detail: "Read, add, change, complete, or remove"
        ),
        AskAppleSource(
            name: "contacts",
            access: .contacts,
            title: "Contacts",
            symbol: "person.crop.circle",
            detail: "Look up, add, change, or remove"
        ),
        AskAppleSource(
            name: "location",
            access: .location,
            title: "Location",
            symbol: "location",
            detail: "Where you are and where a place is"
        ),
        AskAppleSource(
            name: "health",
            access: .health,
            title: "Health",
            symbol: "heart",
            detail: "Steps, heart rate, and activity"
        ),
        AskAppleSource(
            name: "music",
            access: .music,
            title: "Music",
            symbol: "music.note",
            detail: "Songs, albums, playlists, and what is playing"
        ),
        AskAppleSource(
            name: "weather",
            access: .weather,
            title: "Weather",
            symbol: "cloud.sun",
            detail: "Hourly and daily forecast"
        ),
        AskAppleSource(
            name: "alarms",
            access: .alarms,
            title: "Alarms",
            symbol: "alarm",
            detail: "List, change, and set alarms"
        )
    ]
}

/// Which allowed Apple sources the next reply may use.
///
/// The key is `AskKit.appleAccess.<assistant name>` in the defaults you pass.
/// A missing key means the app's set. The person can turn sources on or off in the composer.
/// Every allowed source may stay on. Each matching source still runs in its own session.
public enum AskAppleSelection: Sendable {
    public static func storageKey(for assistantName: String) -> String {
        "AskKit.appleAccess.\(assistantName)"
    }

    private static let lock = OSAllocatedUnfairLock()

    /// The saved subset, or `allowed` when this assistant has no saved choice.
    public static func active(
        allowed: AskAppleAccess,
        for assistantName: String,
        defaults: UserDefaults = .standard
    ) -> AskAppleAccess {
        lock.withLockUnchecked { stored(allowed: allowed, assistantName: assistantName, defaults: defaults) }
    }

    /// Saves `selection` only when this assistant has no saved choice yet.
    public static func rememberIfNeeded(
        _ selection: AskAppleAccess,
        allowed: AskAppleAccess,
        for assistantName: String,
        defaults: UserDefaults = .standard
    ) {
        lock.withLockUnchecked {
            let key = storageKey(for: assistantName)
            guard defaults.object(forKey: key) == nil else { return }
            defaults.set(selection.intersection(allowed).rawValue, forKey: key)
        }
    }

    /// Saves a subset of `allowed`.
    @discardableResult
    public static func update(
        _ selection: AskAppleAccess,
        allowed: AskAppleAccess,
        for assistantName: String,
        defaults: UserDefaults = .standard
    ) -> AskAppleAccess {
        lock.withLockUnchecked {
            let next = selection.intersection(allowed)
            defaults.set(next.rawValue, forKey: storageKey(for: assistantName))
            return next
        }
    }

    private static func stored(
        allowed: AskAppleAccess,
        assistantName: String,
        defaults: UserDefaults
    ) -> AskAppleAccess {
        guard let raw = defaults.object(forKey: storageKey(for: assistantName)) as? Int else {
            return allowed
        }
        return AskAppleAccess(rawValue: raw).intersection(allowed)
    }
}

/// One tool result from a reply. `name` is the tool. `lines` are what it returned.
public struct AskAppleReading: Sendable, Equatable {
    public var name: String
    public var lines: [String]

    public init(name: String, lines: [String]) {
        self.name = name
        self.lines = lines
    }
}

/// The reply string plus every tool that ran while it was written.
public struct AskWrittenReply: Sendable, Equatable {
    public var text: String
    public var readings: [AskAppleReading]

    public init(text: String, readings: [AskAppleReading] = []) {
        self.text = text
        self.readings = readings
    }
}

enum AskAppleCopy {
    static let denied = "Not allowed."
    /// A source this device has no framework for.
    static let unavailable = "Not available on this device."
    /// Apple Watch reads Calendar, Reminders, and Contacts but cannot change them.
    static let readOnly = "Make that change on your iPhone."
    /// A line that created an event, reminder, or contact. A later repair must not replace it with a read.
    static let addedPrefix = "Added "
    /// A line that changed or removed an event or reminder. Repair leaves it in place.
    static let updatedPrefix = "Updated "
    static let removedPrefix = "Removed "

    static func keepsWrite(_ line: String) -> Bool {
        line.hasPrefix(addedPrefix) || line.hasPrefix(updatedPrefix) || line.hasPrefix(removedPrefix)
    }

    /// User text on a tool line. Equals signs fail the reply check, and the dot is the field separator.
    static func plain(_ text: String, limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: "=", with: " ")
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(limit))
    }
    /// A routed miss that still reads the Apple sources the person turned on.
    static let missSkillID = "ask.apple"
    static let toolOnlySentence = "Only a tool result may be stated."
    static let missFacts = "No skill matched. \(toolOnlySentence)"
    /// Added to the reply instructions only when the reply session has tools.
    static let replyRule = """
    Use a tool when the question needs the person's calendar, reminders, contacts, location, health, music, weather, or alarms. \
    A tool result counts as FACTS. Say it. If a tool says Not allowed, say you cannot see that. Do not invent it.
    Call each tool once. After the result, write the answer. Do not call that tool again.
    CONVERSATION is not a source of events, reminders, contacts, places, health numbers, songs, or the forecast. \
    A different day needs its own calendar call. Say the weekday and date the tool returned. \
    Do not reuse an earlier day's events. \
    For a weekday, pass the number listed beside that weekday on the calendar tool. Do not count the days yourself.
    A named place uses the location tool. Pass the place name. Pass here for where the person is. \
    Name the place and the address. Do not mention coordinates, latitude, or longitude unless the person asked for them. \
    Set the location tool's coordinates argument only then.
    To add an event or a reminder, call that tool with action add and the title. Pass a place or notes when the person named them. A reminder can also take priority high, medium, or low. \
    To change one, call action update with its title. To remove one, call action delete with its title. \
    Say it was added only when the line starts with Added, changed when it starts with Updated, and removed when it starts with Removed. \
    To add a contact, call the contacts tool with action add and the name. Pass the phone or email when they were said. \
    To change a contact, call the contacts tool with action update and the current name. To remove one, pass action delete. \
    For contacts that begin with letters, call the contacts tool with action look, those letters, and beginsWith true. \
    For contacts added recently, call the contacts tool with action look and daysBack. 7 is last week. 30 is last month. Leave the name empty.
    For a reminder list, say how many are open in one short sentence. Do not list the titles. The card lists them.
    A calendar question calls the calendar tool only. A contact question calls the contacts tool only. \
    Pass nearby to the location tool for places around the person. \
    For a week, pass span week to the health tool. For a month, pass span month. For a year, pass span year. \
    For workouts pass kind workouts. For sleep pass kind sleep. \
    When the person asks for an email, say the email the contacts tool returned.
    For the forecast, pass span hourly or span daily to the weather tool, the day number, and the city when one is named. 0 is today. \
    Leave the city empty for where the person is. Say it in one or two short sentences. The card lists each day or each hour.
    A song, album, or playlist uses the music tool. Pass song, album, or playlist and the title. Pass play and the title to start playback. Pass now for what is playing. \
    Pass recent for the last song played, and for songs the person listened to, including top songs and the past week. Do not search the catalog for those. \
    Pass pause to pause, next to skip, and previous to go back. Say the title and the artist. Do not say a song is playing unless its line starts with Song.
    To read alarms, call the alarms tool with action read and do not add one. Say how many are on. \
    To change an alarm, call action update with its current time and the new time or repeats. Recurring is daily, weekdays, weekends, or a weekday name. \
    To remove an alarm, call action delete with its time. \
    To set alarms, call the alarms tool once and pass every alarm this question asked for. Each one needs a title and a time. \
    Pass a label for the button title and an SF Symbol when the person wants a custom button. \
    Everyday symbol words such as food are fine. Pass an action id only when it is on that tool's list. \
    Say an alarm was set only when its line starts with Added.
    """

    /// A tool-only skill must call when a specialist was attached. A greeting has no specialist, so the count is 0. A catalog miss stays optional.
    static func replyMustCallTool(facts: String, skillID: String, toolCount: Int) -> Bool {
        toolCount > 0 && skillID != missSkillID && facts.contains(toolOnlySentence)
    }

    /// Calendar, reminders, contacts, location, health, music, weather, or a day the calendar should read.
    static func questionNeedsATool(_ question: String) -> Bool {
        let folded = folded(question)
        if toolPhrases.contains(where: { folded.localizedStandardContains($0) }) { return true }
        let tokens = foldedTokens(question)
        if tokens.contains(where: { toolWords.contains($0) }) { return true }
        guard tokens.contains(where: { dayWords.contains($0) }) else { return false }
        let extra = tokens.filter { !greetingWords.contains($0) && !dayWords.contains($0) }
        if !extra.isEmpty { return true }
        return !tokens.contains { greetingWords.contains($0) }
    }

    static func folded(_ question: String) -> String {
        question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func foldedTokens(_ question: String) -> [String] {
        folded(question).split { !$0.isLetter && !$0.isNumber }.map { String($0) }
    }

    /// The bubble when the model called tools and then wrote nothing.
    static func sentence(from readings: [AskAppleReading]) -> String? {
        guard let reading = AskAppleCards.first(readings) else { return nil }
        if reading.name == "weather" {
            let lines = readings.filter { $0.name == "weather" }.flatMap(\.lines)
            if let spoken = AskWeatherLine.spoken(lines) { return spoken }
        }
        if reading.name == "music" {
            let lines = readings.filter { $0.name == "music" }.flatMap(\.lines)
            if let spoken = AskMusicLine.spoken(lines) { return spoken }
        }
        if reading.name == "alarms" {
            let lines = readings.filter { $0.name == "alarms" }.flatMap(\.lines)
            if let spoken = AskAlarmLine.spoken(lines) { return spoken }
        }
        if reading.name == "photos" {
            let lines = readings.filter { $0.name == "photos" }.flatMap(\.lines)
            if let spoken = AskPhotosLine.spoken(lines) { return spoken }
        }
        if reading.name == "calendar" {
            let lines = readings.filter { $0.name == "calendar" }.flatMap(\.lines).map(AskCalendarItem.plain)
            var spoken = ""
            for line in lines where !line.isEmpty {
                let next = spoken.isEmpty ? line : spoken + " " + line
                if next.count > 600 { break }
                spoken = next
            }
            if !spoken.isEmpty { return spoken }
        }
        let lines = AskLocationPin.labels(in: reading.lines)
        var spoken = ""
        for line in lines {
            let next = spoken.isEmpty ? line : spoken + " " + line
            if next.count > 600 { break }
            spoken = next
        }
        return spoken.isEmpty ? nil : spoken
    }

    private static let toolPhrases = [
        "to do", "to-do", "phone number", "where am i", "where i am", "where is", "where are", "where's", "where’s",
        "near me", "nearby", "around me", "address of", "e-mail", "remind me", "add a reminder", "add an event", "add a calendar",
        "create a reminder", "create an event", "blood pressure", "resting heart", "body fat",
        "pause the music", "skip this song", "next song", "previous song", "add a contact",
        "set an alarm", "set a timer", "wake me", "alarm for"
    ]
    private static let toolWords: Set<String> = [
        "calendar", "schedule", "scheduled", "event", "events", "appointment", "appointments", "agenda", "birthday", "birthdays",
        "reminder", "reminders", "todo", "contact", "contacts", "email", "emails", "location", "nearby", "health", "steps", "heart", "calorie", "calories",
        "weight", "height", "glucose", "oxygen", "temperature", "vo2", "exercise", "flight", "flights", "workout", "workouts", "sleep",
        "music", "song", "songs", "pause", "skip",
        "playlist", "album", "playing", "weather", "forecast", "forecasts", "rain", "raining", "rainy", "snow", "snowing",
        "umbrella", "humidity", "precipitation", "sunny", "cloudy", "windy", "storm", "storms",
        "alarm", "alarms", "timer", "timers"
    ]
    static let dayWords: Set<String> = [
        "today", "tomorrow", "tonight", "yesterday", "morning", "afternoon", "evening", "weekend",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]
    private static let greetingWords: Set<String> = [
        "hi", "hello", "hey", "hiya", "thanks", "thank", "you", "how", "are", "good", "what", "whats", "up", "there", "ya", "yeah", "ok", "okay", "please"
    ]
}

/// A place question. "here" is the device. Nil when the question is not asking where something is.
enum AskPlaceQuery {
    static func lookup(in question: String) -> String? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isNearby(trimmed) { return "nearby" }
        if isDeviceQuestion(trimmed) { return "here" }
        for prefix in ["where is ", "where are ", "where's ", "where’s ", "address of "] {
            if let name = remainder(trimmed, after: prefix) { return name }
        }
        return nil
    }

    static func isNearby(_ question: String) -> Bool {
        let folded = AskAppleCopy.folded(question)
        return folded.localizedStandardContains("nearby")
            || folded.localizedStandardContains("near me")
            || folded.localizedStandardContains("around me")
    }

    static func isDevice(_ place: String) -> Bool {
        let folded = place.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folded.isEmpty || folded == "here" || folded == "current" || folded == "me" || folded == "now" || folded == "device"
    }

    private static func isDeviceQuestion(_ question: String) -> Bool {
        let folded = question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.localizedStandardContains("where am i") || folded.localizedStandardContains("where i am")
    }

    private static func remainder(_ question: String, after prefix: String) -> String? {
        guard let range = question.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive]),
              question[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let rest = question[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.count >= 2, rest.count <= 120 else { return nil }
        return rest
    }
}

/// Which Apple sources the question actually asks for. An empty set means the question named none.
enum AskSourceFocus {
    static func named(in question: String) -> Set<String> {
        var found: Set<String> = []
        if asksCalendar(question) { found.insert("calendar") }
        if asksReminders(question) { found.insert("reminders") }
        if asksContacts(question) { found.insert("contacts") }
        if asksLocation(question) { found.insert("location") }
        if AskHealthCatalog.kind(in: question) != nil { found.insert("health") }
        if asksMusic(question) { found.insert("music") }
        if asksWeather(question) {
            found.insert("weather")
            found.remove("health")
        }
        if asksAlarms(question) { found.insert("alarms") }
        if AskWebMetadata.url(in: question) != nil { found.insert("web") }
        // A host specialist. Naming it keeps a photo-library question off the calendar day fallback.
        if AskPhotos.matches(question) { found.insert("photos") }
        return found
    }

    static func asksAlarms(_ question: String) -> Bool {
        if hits(question, words: ["alarm", "alarms", "timer", "timers"]) { return true }
        return AskAppleCopy.folded(question).localizedStandardContains("wake me")
    }

    static func asksCalendar(_ question: String) -> Bool {
        hits(question, words: [
            "calendar", "schedule", "scheduled", "event", "events", "appointment", "appointments",
            "agenda", "birthday", "birthdays"
        ])
    }

    static func asksBirthdays(_ question: String) -> Bool {
        hits(question, words: ["birthday", "birthdays"])
    }

    static func asksReminders(_ question: String) -> Bool {
        if hits(question, words: ["reminder", "reminders", "todo"]) { return true }
        let folded = AskAppleCopy.folded(question)
        return folded.localizedStandardContains("to do")
            || folded.localizedStandardContains("to-do")
            || folded.localizedStandardContains("remind me")
    }

    static func asksContacts(_ question: String) -> Bool {
        if hits(question, words: ["contact", "contacts", "email", "emails"]) { return true }
        let folded = AskAppleCopy.folded(question)
        return folded.localizedStandardContains("phone number") || folded.localizedStandardContains("e-mail")
    }

    static func asksLocation(_ question: String) -> Bool {
        if hits(question, words: ["location", "nearby"]) { return true }
        let folded = AskAppleCopy.folded(question)
        let phrases = ["where am i", "where i am", "where is", "where are", "where's", "where’s", "near me", "around me", "address of"]
        return phrases.contains { folded.localizedStandardContains($0) }
    }

    static func asksMusic(_ question: String) -> Bool {
        hits(question, words: ["music", "song", "songs", "playlist", "album", "playing", "pause", "skip"])
    }

    /// Forecast words, or an outside temperature. A body-temperature question stays on health.
    static func asksWeather(_ question: String) -> Bool {
        if hits(question, words: [
            "weather", "forecast", "forecasts", "rain", "raining", "rainy", "snow", "snowing", "umbrella",
            "humidity", "precipitation", "sunny", "cloudy", "windy", "wind", "storm", "storms",
            "thunderstorm", "thunderstorms"
        ]) {
            return true
        }
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        let outside = tokens.contains("outside") || tokens.contains("outdoors")
        let temperature = tokens.contains("temperature") || tokens.contains("temp") || tokens.contains("degrees")
        return outside && temperature
    }

    private static func hits(_ question: String, words: [String]) -> Bool {
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        return words.contains { tokens.contains($0) }
    }
}

/// A person named in a contact question. Nil when the question is not asking about one name.
enum AskContactQuery {
    /// A lookup name, and whether the question asked for names that begin with it.
    struct Request: Equatable {
        var name: String
        var prefix: Bool
    }

    static func asksEmail(_ question: String) -> Bool {
        let folded = AskAppleCopy.folded(question)
        return folded.localizedStandardContains("email") || folded.localizedStandardContains("e-mail")
    }

    static func asksCount(_ question: String) -> Bool {
        let folded = AskAppleCopy.folded(question)
        return folded.localizedStandardContains("how many") || folded.localizedStandardContains("number of")
    }

    static func asksPrefix(_ question: String) -> Bool {
        request(in: question)?.prefix == true
    }

    static func name(in question: String) -> String? {
        request(in: question)?.name
    }

    /// Days back for contacts added recently. Nil when the question is not a recent-add list.
    static func recentDays(in question: String) -> Int? {
        let folded = AskAppleCopy.folded(question)
        guard folded.localizedStandardContains("contact") else { return nil }
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        let writing = (tokens.contains("add") || tokens.contains("create"))
            && !tokens.contains("added")
            && !folded.localizedStandardContains("added")
        if writing { return nil }
        let looksRecent =
            tokens.contains("added")
            || tokens.contains("recent")
            || tokens.contains("recently")
            || folded.localizedStandardContains("new contacts")
            || folded.localizedStandardContains("contacts i added")
            || folded.localizedStandardContains("contacts ive added")
            || folded.localizedStandardContains("contacts i have added")
        guard looksRecent else { return nil }
        if let days = numberedDays(in: folded) { return days }
        if folded.localizedStandardContains("last week") || folded.localizedStandardContains("past week") {
            return 7
        }
        if folded.localizedStandardContains("last month") || folded.localizedStandardContains("past month") {
            return 30
        }
        if tokens.contains("yesterday") { return 1 }
        if tokens.contains("today") { return 1 }
        return 7
    }

    static func recentWindowPhrase(_ days: Int) -> String {
        switch days {
        case 1: return "in the last day"
        case 7: return "in the last week"
        case 30: return "in the last month"
        default: return "in the last \(days) days"
        }
    }

    static func request(in question: String) -> Request? {
        if recentDays(in: question) != nil { return nil }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns: [(pattern: String, prefix: Bool)] = [
            (#"(?i)contacts?\s+(?:that\s+)?(?:begin|begins|beginning|start|starts|starting)\s+with\s+(\S+)"#, true),
            (#"(?i)(?:begin|begins|beginning|start|starts|starting)\s+with\s+(\S+)"#, true),
            (#"(?i)contacts?\s+(?:named|name|called)\s+(.+?)(?:\s+do\s+i\b.*)?$"#, false),
            (#"(?i)^what(?:'s|’s|s| is)?\s+(.+?)(?:'s|’s)?\s+e-?mail(?:\s+address)?\??$"#, false),
            (#"(?i)^e-?mail(?:\s+address)?\s+(?:for|of)\s+(.+?)\??$"#, false),
            (#"(?i)^(.+?)(?:'s|’s)\s+e-?mail(?:\s+address)?\??$"#, false),
        ]
        for entry in patterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: trimmed) else { continue }
            let name = String(trimmed[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .punctuationCharacters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let minimum = entry.prefix ? 1 : 2
            if (minimum...80).contains(name.count) {
                return Request(name: name, prefix: entry.prefix)
            }
        }
        return nil
    }

    private static func numberedDays(in folded: String) -> Int? {
        let patterns = [
            #"\blast\s+(\d+)\s+days?\b"#,
            #"\bpast\s+(\d+)\s+days?\b"#,
            #"\bin\s+the\s+last\s+(\d+)\s+days?\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: folded),
                  let value = Int(folded[range]),
                  (1...3_650).contains(value) else { continue }
            return value
        }
        if folded.localizedStandardContains("7 days") || folded.localizedStandardContains("seven days") {
            return 7
        }
        return nil
    }
}

/// One contact line: name, phone, and email. A fuzzy Contacts hit that does not match the name is dropped.
package enum AskContactLine {
    package struct Person: Equatable {
        package var name: String
        package var phone: String
        package var email: String

        package var isPerson: Bool {
            let folded = AskAppleCopy.folded(name).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folded.isEmpty else { return false }
            let status = [
                "no matching contacts.", "no matching contacts", "no contacts.", "no contacts",
                "no recently added contacts.", "no recently added contacts",
                "not allowed.", "not allowed", "contact"
            ]
            return !status.contains(folded)
        }

        var shareLine: String { AskContactLine.line(name: name, phone: phone, email: email) }
    }

    package static func line(name: String, phone: String, email: String) -> String {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [who.isEmpty ? "Contact" : who]
        let number = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty { parts.append(number) }
        if !address.isEmpty { parts.append(address) }
        return parts.joined(separator: " · ")
    }

    package static func person(from line: String) -> Person {
        let parts = line.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard let name = parts.first else { return Person(name: "", phone: "", email: "") }
        var phone = ""
        var email = ""
        for part in parts.dropFirst() {
            if part.contains("@") {
                if email.isEmpty { email = part }
            } else if phone.isEmpty {
                phone = part
            }
        }
        return Person(name: name, phone: phone, email: email)
    }

    static func filtered(_ lines: [String], query: String, prefix: Bool = false) -> [String] {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return lines }
        return lines.filter { line in
            let person = person(from: line)
            return person.isPerson && matches(name: person.name, query: wanted, prefix: prefix)
        }
    }

    static func matches(name: String, query: String, prefix: Bool = false) -> Bool {
        let minimum = prefix ? 1 : 2
        let wanted = AskAppleCopy.foldedTokens(query).filter { $0.count >= minimum }
        guard !wanted.isEmpty else { return true }
        let have = AskAppleCopy.foldedTokens(name)
        if prefix {
            return wanted.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
        }
        return wanted.allSatisfy { word in have.contains { close($0, word) } }
    }

    /// A count, or the email the question asked for. The cards list each person.
    static func speech(_ text: String, question: String, readings: [AskAppleReading]) -> String {
        let lines = readings.filter { $0.name == "contacts" }.flatMap(\.lines)
        guard !lines.isEmpty else { return text }
        let people = lines.map { person(from: $0) }.filter(\.isPerson)
        if AskContactQuery.asksEmail(question) {
            let query = AskContactQuery.name(in: question) ?? ""
            let match = people.first { query.isEmpty || matches(name: $0.name, query: query) }
            guard let match else { return status(lines) ?? text }
            if match.email.isEmpty { return "\(match.name) has no email." }
            return "\(match.name)'s email is \(match.email)."
        }
        if let days = AskContactQuery.recentDays(in: question) {
            let window = AskContactQuery.recentWindowPhrase(days)
            if people.isEmpty {
                if lines.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == AskAppleCopy.denied }) {
                    return status(lines) ?? text
                }
                return "No contacts were added \(window)."
            }
            if people.count == 1 { return "You added 1 contact \(window)." }
            return "You added \(people.count) contacts \(window)."
        }
        if people.isEmpty { return status(lines) ?? text }
        guard let request = AskContactQuery.request(in: question) else { return text }
        let counting = AskContactQuery.asksCount(question) || people.count > 1 || request.prefix
        guard counting else { return text }
        let label = spokenName(request.name)
        if request.prefix {
            if people.count == 1 { return "You have 1 contact that begins with \(label)." }
            return "You have \(people.count) contacts that begin with \(label)."
        }
        if people.count == 1 { return "You have 1 contact named \(label)." }
        return "You have \(people.count) contacts named \(label)."
    }

    private static func status(_ lines: [String]) -> String? {
        guard let line = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
        return line.hasSuffix(".") ? line : line + "."
    }

    private static func spokenName(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased() + trimmed.dropFirst()
    }

    /// April matches April and Aprill. It does not match a different name the Contacts predicate included.
    private static func close(_ have: String, _ want: String) -> Bool {
        if have == want { return true }
        let shorter = have.count <= want.count ? have : want
        let longer = have.count <= want.count ? want : have
        guard shorter.count >= 4 else { return false }
        return longer.hasPrefix(shorter) && longer.count - shorter.count <= 1
    }
}

/// Read a day, or add, change, or remove one event. Parsing does not touch EventKit.
enum AskCalendarCommand: Equatable {
    case read(Int)
    case birthdays(Int)
    case add(title: String, day: Int, hour: Int?, minute: Int, place: String, notes: String)
    case update(title: String, day: Int, hour: Int?, minute: Int?, place: String?, notes: String?, newTitle: String?)
    case delete(title: String, day: Int)
    case needsTitle
    case needsChange
    case badTime

    static func parse(
        action: String?,
        day: Int,
        title: String?,
        hour: Int?,
        minute: Int?,
        place: String? = nil,
        notes: String? = nil,
        newTitle: String? = nil
    ) -> AskCalendarCommand {
        let name = clip(title)
        let verb = verb(action)
        if verb == "birthday" || verb == "birthdays" {
            return .birthdays(day)
        }
        if verb == "delete" || verb == "remove" || verb == "cancel" {
            guard !name.isEmpty else { return .needsTitle }
            return .delete(title: name, day: day)
        }
        if verb == "update" || verb == "edit" || verb == "change" || verb == "move" || verb == "reschedule" {
            guard !name.isEmpty else { return .needsTitle }
            let clock = clock(hour: hour, minute: minute)
            if clock.bad { return .badTime }
            let whereTo = optional(place)
            let about = optional(notes)
            let renamed = optional(newTitle)
            let timed = clock.hour
            guard timed != nil || whereTo != nil || about != nil || renamed != nil else { return .needsChange }
            return .update(title: name, day: day, hour: timed, minute: clock.minute, place: whereTo, notes: about, newTitle: renamed)
        }
        guard verb == "add" || verb == "create" || verb == "new" else { return .read(day) }
        guard !name.isEmpty else { return .needsTitle }
        let clock = clock(hour: hour, minute: minute)
        if clock.bad { return .badTime }
        return .add(
            title: name,
            day: day,
            hour: clock.hour,
            minute: clock.minute ?? 0,
            place: optional(place) ?? "",
            notes: optional(notes) ?? ""
        )
    }

    private static func verb(_ action: String?) -> String {
        action?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func clip(_ text: String?) -> String {
        String((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    private static func optional(_ text: String?) -> String? {
        let trimmed = clip(text)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clock(hour: Int?, minute: Int?) -> (hour: Int?, minute: Int?, bad: Bool) {
        guard let hour else { return (nil, nil, false) }
        guard (0...23).contains(hour) else { return (nil, nil, true) }
        let minute = minute ?? 0
        guard (0...59).contains(minute) else { return (nil, nil, true) }
        return (hour, minute, false)
    }
}

/// List reminders, or add, change, or remove one. Parsing does not touch EventKit.
enum AskReminderCommand: Equatable {
    case list(Int)
    case add(title: String, day: Int?, hour: Int?, minute: Int, notes: String, priority: String)
    case update(title: String, day: Int?, hour: Int?, minute: Int?, notes: String?, priority: String?, newTitle: String?)
    case delete(title: String)
    case needsTitle
    case needsChange
    case badTime

    static func parse(
        action: String?,
        limit: Int,
        title: String?,
        day: Int?,
        hour: Int?,
        minute: Int?,
        notes: String? = nil,
        priority: String? = nil,
        newTitle: String? = nil
    ) -> AskReminderCommand {
        let name = clip(title)
        let verb = verb(action)
        let due = (day != nil && (day ?? -1) >= 0) ? day : nil
        if verb == "delete" || verb == "remove" {
            guard !name.isEmpty else { return .needsTitle }
            return .delete(title: name)
        }
        if verb == "update" || verb == "edit" || verb == "change" {
            guard !name.isEmpty else { return .needsTitle }
            let clock = clock(hour: hour, minute: minute)
            if clock.bad { return .badTime }
            let about = optional(notes)
            let rank = rank(priority)
            let renamed = optional(newTitle)
            guard clock.hour != nil || due != nil || about != nil || rank != nil || renamed != nil else { return .needsChange }
            return .update(
                title: name,
                day: due,
                hour: clock.hour,
                minute: clock.minute,
                notes: about,
                priority: rank,
                newTitle: renamed
            )
        }
        let adding = verb == "add" || verb == "create" || verb == "new"
        guard adding else { return .list(limit) }
        guard !name.isEmpty else { return .needsTitle }
        let clock = clock(hour: hour, minute: minute)
        if clock.bad { return .badTime }
        return .add(
            title: name,
            day: due,
            hour: clock.hour,
            minute: clock.minute ?? 0,
            notes: optional(notes) ?? "",
            priority: rank(priority) ?? ""
        )
    }

    private static func verb(_ action: String?) -> String {
        action?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func clip(_ text: String?) -> String {
        String((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    private static func optional(_ text: String?) -> String? {
        let trimmed = clip(text)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Empty stays unset. none, low, medium, and high are the ranks the tool accepts.
    private static func rank(_ text: String?) -> String? {
        switch clip(text).lowercased() {
        case "none", "low", "medium", "high":
            return clip(text).lowercased()
        default:
            return nil
        }
    }

    private static func clock(hour: Int?, minute: Int?) -> (hour: Int?, minute: Int?, bad: Bool) {
        guard let hour else { return (nil, nil, false) }
        guard (0...23).contains(hour) else { return (nil, nil, true) }
        let minute = minute ?? 0
        guard (0...59).contains(minute) else { return (nil, nil, true) }
        return (hour, minute, false)
    }
}

/// Look up a person, or add, change, or remove one contact. Parsing does not touch Contacts.
enum AskContactCommand: Equatable {
    case lookup(name: String, prefix: Bool)
    case recent(days: Int)
    case add(name: String, phone: String, email: String)
    case update(name: String, phone: String?, email: String?, newName: String?)
    case delete(name: String)
    case needsName
    case needsChange

    static func parse(
        action: String?,
        name: String,
        phone: String?,
        email: String?,
        beginsWith: Bool? = nil,
        newName: String? = nil,
        daysBack: Int? = nil
    ) -> AskContactCommand {
        let who = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let verb = action?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if verb == "delete" || verb == "remove" {
            guard !who.isEmpty else { return .needsName }
            return .delete(name: who)
        }
        if verb == "update" || verb == "edit" || verb == "change" {
            guard !who.isEmpty else { return .needsName }
            let number = optional(phone)
            let address = optional(email)
            let renamed = optional(newName)
            guard number != nil || address != nil || renamed != nil else { return .needsChange }
            return .update(name: who, phone: number, email: address, newName: renamed)
        }
        if verb == "add" || verb == "create" || verb == "new" {
            guard !who.isEmpty else { return .needsName }
            return .add(name: who, phone: clip(phone), email: clip(email))
        }
        if let daysBack, (1...3_650).contains(daysBack), who.isEmpty {
            return .recent(days: daysBack)
        }
        return .lookup(name: who, prefix: beginsWith == true)
    }

    private static func clip(_ text: String?) -> String {
        String((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private static func optional(_ text: String?) -> String? {
        let trimmed = clip(text)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum AskAppleFacts {
    /// Tool lines join the skill facts before the 600-character and equals-sign checks.
    static func appending(_ facts: String, readings: [AskAppleReading]) -> String {
        let extra = readings.compactMap { reading -> String? in
            let lines = reading.lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return nil }
            return ([reading.name] + lines).joined(separator: "\n")
        }.joined(separator: "\n")
        guard !extra.isEmpty else { return facts }
        let base = facts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return extra }
        return base + "\n" + extra
    }
}

package enum AskAppleCards {
    static let names: Set<String> = ["calendar", "reminders", "contacts", "location", "health", "music", "weather", "alarms", "web", "photos"]

    /// The first Apple source that ran. Later calls to that same source stay on the card, in order.
    static func first(_ readings: [AskAppleReading]) -> AskAppleReading? {
        sources(readings).first
    }

    /// One card per Apple source, in the order they ran. Later calls to the same source stay on that card.
    /// Contacts, songs, albums, and alarms are the exception: each one is its own card.
    /// A forecast stays one card. Hours stay on that day's card.
    static func sources(_ readings: [AskAppleReading]) -> [AskAppleReading] {
        var order: [String] = []
        var lines: [String: [String]] = [:]
        for reading in readings where names.contains(reading.name) {
            if lines[reading.name] == nil {
                order.append(reading.name)
                lines[reading.name] = []
            }
            lines[reading.name, default: []].append(contentsOf: reading.lines)
        }
        return order.flatMap { name -> [AskAppleReading] in
            guard let kept = lines[name], !kept.isEmpty else { return [] }
            if name == "contacts", kept.count > 1 {
                return kept.map { AskAppleReading(name: name, lines: [$0]) }
            }
            if name == "music" {
                let songs = kept.filter { AskMusicLine.item(from: $0) != nil }
                if songs.count > 1 {
                    return songs.map { AskAppleReading(name: name, lines: [$0]) }
                }
            }
            if name == "alarms" {
                let made = kept.filter { AskAlarmLine.item(from: $0) != nil }
                if made.count > 1 {
                    return made.map { AskAppleReading(name: name, lines: [$0]) }
                }
                if made.count == 1 {
                    return [AskAppleReading(name: name, lines: made)]
                }
            }
            return [AskAppleReading(name: name, lines: kept)]
        }
    }

    static func title(for name: String) -> String {
        switch name {
        case "calendar": "Calendar"
        case "reminders": "Reminders"
        case "contacts": "Contacts"
        case "location": "Location"
        case "health": "Health"
        case "music": "Music"
        case "weather": "Weather"
        case "alarms": "Alarm"
        case "web": "Web"
        case "photos": "Photos"
        default: name
        }
    }

    /// Keeps the skill card and places the Apple lines under it.
    @MainActor
    static func under(
        _ card: AskIntentCard,
        reading: AskAppleReading?,
        showsCoordinates: Bool = false,
        playedBy: String = "",
        custom: ((String, [String]) -> AskIntentCard?)?
    ) -> AskIntentCard {
        guard let reading else { return card }
        let lines = AskLocationPin.labels(in: reading.lines)
        guard !lines.isEmpty else { return card }
        let fact = make(
            reading,
            spoken: card.spoken,
            showsCoordinates: showsCoordinates,
            playedBy: playedBy,
            custom: custom
        )
        var combined = card
        combined.content = .stack([card.content, fact.content])
        let extra = lines.joined(separator: "\n")
        if !combined.shareText.localizedCaseInsensitiveContains(extra) {
            combined.shareText = combined.shareText.isEmpty ? extra : combined.shareText + "\n" + extra
        }
        combined.expands = card.expands || fact.expands
        combined.zoomTransition = card.zoomTransition || fact.zoomTransition
        return combined
    }

    /// The host card wins when it returns one. Nil keeps the built-in fact card.
    @MainActor
    package static func make(
        _ reading: AskAppleReading,
        spoken: String,
        showsCoordinates: Bool = false,
        playedBy: String = "",
        custom: ((String, [String]) -> AskIntentCard?)?
    ) -> AskIntentCard {
        let visible = AskLocationPin.labels(in: reading.lines)
        if let card = custom?(reading.name, visible) {
            return card
        }
        let title = title(for: reading.name)
        let calendarEvents = AskCalendarItem.events(in: reading.lines)
        if reading.name == "calendar", !calendarEvents.isEmpty {
            var card = AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                action: AskAction(id: AskPinPhrase.actionID, title: "Pin this"),
                content: .builtIn(.calendar(title: title, items: calendarEvents))
            )
            card.shareText = calendarEvents.map(\.shareLine).joined(separator: "\n")
            card.expands = true
            return card
        }
        let reminders = AskReminderItem.tasks(in: reading.lines)
        if reading.name == "reminders", !reminders.isEmpty {
            var card = AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.reminders(title: title, items: reminders))
            )
            card.shareText = reminders.map(\.shareLine).joined(separator: "\n")
            return card
        }
        let places = AskLocationPin.places(in: reading.lines)
        if reading.name == "location", !places.isEmpty {
            var card = AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.places(title: title, places: places, showsCoordinates: showsCoordinates))
            )
            card.expands = true
            return card
        }
        if reading.name == "contacts", let line = visible.first {
            let person = AskContactLine.person(from: line)
            if person.isPerson {
                var card = AskIntentCard(
                    title: person.name,
                    spoken: spoken,
                    text: spoken,
                    content: .builtIn(.contact(person))
                )
                card.shareText = person.shareLine
                card.expands = true
                return card
            }
        }
        if reading.name == "health", let chart = AskHealthChartModel.parse(visible) {
            var card = AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.health(metric: chart.metric, range: chart.range, lines: visible))
            )
            card.expands = true
            return card
        }
        if reading.name == "music", let item = AskMusicLine.item(from: visible.first ?? "") {
            if item.nowPlaying {
                var card = AskIntentCard(
                    title: "Now Playing",
                    spoken: spoken,
                    text: spoken,
                    content: .builtIn(.nowPlaying(item, playedBy: playedBy))
                )
                card.shareText = item.shareText
                card.expands = true
                return card
            }
            var card = AskIntentCard(
                title: item.title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.music(item))
            )
            card.shareText = item.shareText
            card.expands = true
            return card
        }
        if reading.name == "alarms",
           let line = visible.first(where: { AskAlarmLine.item(from: $0) != nil }),
           let item = AskAlarmLine.item(from: line) {
            var card = AskIntentCard(
                title: item.title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.alarm(item))
            )
            card.shareText = [item.title, item.time, item.repeats, item.label, item.symbol]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            card.expands = true
            return card
        }
        if reading.name == "weather", let forecast = AskWeatherLine.forecast(from: visible) {
            var card = AskIntentCard(
                title: forecast.days.count > 1 ? "Weather" : forecast.day.title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.weather(forecast))
            )
            card.shareText = forecast.shareText
            card.expands = true
            return card
        }
        if reading.name == "web" {
            var card = AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.web(lines: visible))
            )
            card.shareText = visible.joined(separator: "\n")
            card.expands = true
            return card
        }
        if reading.name == "photos", let grid = AskPhotosLine.grid(from: visible) {
            var card = AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                content: .builtIn(.photos(title: grid.title, photos: grid.photos, shareText: grid.shareText))
            )
            card.shareText = grid.shareText
            card.coveredPhrases = grid.coveredPhrases
            card.zoomTransition = true
            return card
        }
        let value = visible.first ?? "Nothing to show."
        let detail = visible.dropFirst().joined(separator: "\n")
        var card = AskGeneratedCard.card(
            title: title,
            spoken: spoken,
            text: spoken,
            root: AskGeneratedCard.factTree(title: title, value: value, detail: detail)
        )
        card.shareText = [value, detail].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return card
    }
}

/// A place the location tool found. The map coordinate stays off the spoken line unless the person asked.
package enum AskLocationPin {
    /// Splits a stored line into the address and the map coordinate.
    static let marker = "\u{1E}"

    package struct Place: Identifiable, Equatable {
        package var label: String
        package var latitude: Double
        package var longitude: Double

        package var id: String { "\(latitude),\(longitude),\(label)" }
        package var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        package var shortName: String {
            label.split(separator: ",", maxSplits: 1).first.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? label
        }

        /// The rest of the label after the place name. Empty when the label is only a name.
        package var address: String {
            let parts = label.split(separator: ",", maxSplits: 1)
            guard parts.count == 2 else { return "" }
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Joins a name and an address without repeating a street that the longer line already contains.
    static func addressLine(_ parts: [String]) -> String {
        var kept: [String] = []
        for raw in parts {
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            let folded = piece.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            if let index = kept.firstIndex(where: { existing in
                let have = existing.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                return have == folded || have.contains(folded) || folded.contains(have)
            }) {
                let have = kept[index].folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                if folded.count > have.count { kept[index] = piece }
                continue
            }
            kept.append(piece)
        }
        return kept.joined(separator: ", ")
    }

    package static func line(label: String, latitude: Double, longitude: Double) -> String {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = name.isEmpty ? "Current location" : name
        return "\(shown)\(marker)\(String(format: "%.4f", latitude)),\(String(format: "%.4f", longitude))"
    }

    static func parse(_ line: String) -> (label: String, place: Place?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: marker) else { return (trimmed, nil) }
        let label = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed[range.upperBound...]
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return (label.isEmpty ? trimmed : String(label), nil)
        }
        let shown = label.isEmpty ? "Current location" : String(label)
        return (shown, Place(label: shown, latitude: latitude, longitude: longitude))
    }

    package static func places(in lines: [String]) -> [Place] {
        lines.compactMap { parse($0).place }
    }

    static func labels(in lines: [String]) -> [String] {
        lines.map { AskReminderItem.plain(parse($0).label) }.filter { !$0.isEmpty }
    }

    package static func format(_ place: Place) -> String {
        String(format: "%.4f, %.4f", place.latitude, place.longitude)
    }

    /// What the model is allowed to read. Coordinates stay out unless this lookup asked for them.
    static func forModel(_ output: String, includeCoordinates: Bool) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .map { row -> String in
                let parsed = parse(String(row))
                guard includeCoordinates, let place = parsed.place else { return parsed.label }
                return "\(parsed.label). Coordinates \(format(place))"
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func asks(_ question: String) -> Bool {
        let folded = question.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return ["coordinate", "latitude", "longitude", "lat long", "gps"].contains {
            folded.localizedStandardContains($0)
        }
    }

    /// Drops a coordinates clause. Leaves the place and the address.
    static func omittingCoordinates(from text: String) -> String {
        var cleaned = text
        let patterns = [
            #"(?i)[,.]?\s*(?:with\s+)?coordinates?\s+[+-]?\d{1,3}\.\d{3,}\s*(?:,|and)\s*[+-]?\d{1,3}\.\d{3,}"#,
            #"\s*·\s*[+-]?\d{1,3}\.\d{3,}\s*,\s*[+-]?\d{1,3}\.\d{3,}"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix(",") || cleaned.hasSuffix("·") {
            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !cleaned.isEmpty, let last = cleaned.last, !".!?".contains(last) {
            cleaned += "."
        }
        return cleaned
    }

    static func adjust(_ text: String, question: String, readings: [AskAppleReading]) -> String {
        let lines = readings.filter { $0.name == "location" }.flatMap(\.lines)
        let found = places(in: lines)
        guard !found.isEmpty else { return text }
        if asks(question) {
            if hasCoordinatePair(text) { return text }
            let coords = found.map(format).joined(separator: "; ")
            let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty { return "Coordinates \(coords)." }
            if let last = base.last, ".!?".contains(last) {
                return base + " Coordinates \(coords)."
            }
            return base + ". Coordinates \(coords)."
        }
        let stripped = omittingCoordinates(from: text)
        if !stripped.isEmpty { return stripped }
        let spoken = labels(in: lines).joined(separator: ". ")
        guard !spoken.isEmpty else { return text }
        return spoken.hasSuffix(".") ? spoken : spoken + "."
    }

    /// Places around the person. A copied health or reminder sentence is replaced with those names.
    static func nearbySpeech(_ text: String, question: String, readings: [AskAppleReading]) -> String {
        guard AskPlaceQuery.lookup(in: question) == "nearby" else { return text }
        let raw = readings.filter { $0.name == "location" }.flatMap(\.lines)
        let labels = raw.map { parse($0).label }.filter { label in
            let folded = AskAppleCopy.folded(label)
            let skipped = ["no matching place.", "not allowed.", "nothing nearby.", "location is unavailable.", ""]
            return !skipped.contains(folded)
        }
        guard !labels.isEmpty else {
            guard let line = raw.first?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return text }
            return line.hasSuffix(".") ? line : line + "."
        }
        let shown = Array(labels.prefix(5))
        if shown.count == 1 { return "You are near \(shown[0])." }
        if shown.count == 2 { return "You are near \(shown[0]) and \(shown[1])." }
        let head = shown.dropLast().joined(separator: ", ")
        return "You are near \(head), and \(shown[shown.count - 1])."
    }

    private static func hasCoordinatePair(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: #"[+-]?\d{1,3}\.\d{3,}\s*(?:,|and)\s*[+-]?\d{1,3}\.\d{3,}"#
        ) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}

/// The region a location card frames. The chat map and the shortcut snapshot use the same one.
package enum AskLocationRegion {
    package static func region(for places: [AskLocationPin.Place]) -> MKCoordinateRegion {
        let coordinates = places.map(\.coordinate)
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: first,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? first.latitude
        let maxLat = latitudes.max() ?? first.latitude
        let minLon = longitudes.min() ?? first.longitude
        let maxLon = longitudes.max() ?? first.longitude
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.6, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.6, 0.02)
            )
        )
    }
}

/// One reminder on the card. The EventKit identifier stays off the line the model reads.
package enum AskReminderItem {
    static let marker = "\u{1F}"

    package struct Item: Identifiable, Equatable {
        package var id: String
        package var title: String
        package var due: String

        var isTask: Bool { !id.isEmpty }
        var shareLine: String { due.isEmpty ? title : "\(title) · \(due)" }
    }

    package static func line(title: String, due: String, id: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let when = due.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = when.isEmpty ? name : "\(name) · \(when)"
        guard !id.isEmpty else { return body }
        return body + marker + id
    }

    static func plain(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: marker) else { return trimmed }
        return trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ line: String) -> Item? {
        let body = plain(line)
        guard !body.isEmpty else { return nil }
        let id: String
        if let range = line.range(of: marker) {
            id = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            id = ""
        }
        let parts = body.split(separator: "·", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = parts.first ?? body
        guard !title.isEmpty else { return nil }
        let due = parts.count > 1 ? parts[1] : ""
        return Item(id: id, title: title, due: due)
    }

    package static func tasks(in lines: [String]) -> [Item] {
        lines.compactMap(parse).filter(\.isTask)
    }

    /// What the model may say. A list is a count. An added reminder keeps its title.
    static func forModel(_ output: String) -> String {
        let rows = output.split(whereSeparator: \.isNewline).map { String($0) }
        let parsed = rows.compactMap(parse)
        let tasks = parsed.filter(\.isTask)
        if tasks.isEmpty {
            return rows.map(plain).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if tasks.allSatisfy({ $0.title.hasPrefix(AskAppleCopy.addedPrefix) }) {
            return tasks.map(\.title).joined(separator: "\n")
        }
        let count = tasks.count
        return count == 1 ? "1 open reminder." : "\(count) open reminders."
    }

    /// The bubble next to the card. The card already lists each reminder.
    /// Another Apple source in the same turn keeps its own sentence.
    /// A next or when question names the first reminder. The read lists the soonest first.
    static func speech(_ text: String, readings: [AskAppleReading], question: String = "") -> String {
        let others = readings.contains { $0.name != "reminders" && !$0.lines.isEmpty }
        guard !others else { return text }
        let lines = readings.filter { $0.name == "reminders" }.flatMap(\.lines)
        guard !lines.isEmpty else { return text }
        let parsed = lines.compactMap(parse)
        let tasks = parsed.filter(\.isTask)
        if tasks.isEmpty {
            let status = parsed.map(\.title).joined(separator: " ")
            return status.isEmpty ? text : status
        }
        if tasks.allSatisfy({ $0.title.hasPrefix(AskAppleCopy.addedPrefix) }) {
            let spoken = tasks.map(\.title).joined(separator: ". ")
            return spoken.hasSuffix(".") ? spoken : spoken + "."
        }
        if asksNext(question), let next = tasks.first {
            return nextSentence(next)
        }
        return tasks.count == 1 ? "You have 1 open reminder." : "You have \(tasks.count) open reminders."
    }

    private static func asksNext(_ question: String) -> Bool {
        let folded = AskAppleCopy.folded(question)
        return folded.localizedStandardContains("next") || folded.localizedStandardContains("when")
    }

    private static func nextSentence(_ item: Item) -> String {
        let name = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = item.due.replacingOccurrences(of: " · ", with: ", ")
        if due.isEmpty { return "Your next reminder is \(name)." }
        return "Your next reminder is \(name), \(due)."
    }
}

/// Stops a reply that calls the same tool again. The session transcript can omit those calls, so the lines live here too.
final class AskToolLedger: @unchecked Sendable {
    static let maximumCalls = 8

    private let lock = NSLock()
    private var calls = 0
    private var seen = Set<String>()
    private var readings: [AskAppleReading] = []

    func claim(name: String, arguments: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let key = name + "\n" + arguments
        if seen.contains(key) || calls >= Self.maximumCalls {
            throw AskToolLoop.stopped
        }
        seen.insert(key)
        calls += 1
    }

    func finish(name: String, output: String) {
        lock.lock()
        defer { lock.unlock() }
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        readings.append(AskAppleReading(name: name, lines: lines))
    }

    func snapshot() -> [AskAppleReading] {
        lock.lock()
        defer { lock.unlock() }
        return readings
    }
}

enum AskToolLoop: Error {
    case stopped
}

protocol AskToolReadingSource {
    var toolLedger: AskToolLedger { get }
}

enum AskAppleTools {
    static func make(_ access: AskAppleAccess, question: String = "") -> [any AskTool] {
#if ASK_FOUNDATION_MODELS
        let access = access.intersection(.available)
        let ledger = AskToolLedger()
        var tools: [any AskTool] = []
        if access.contains(.calendar) { tools.append(AskCalendarTool(toolLedger: ledger)) }
        if access.contains(.reminders) { tools.append(AskRemindersTool(toolLedger: ledger)) }
        if access.contains(.contacts) { tools.append(AskContactsTool(toolLedger: ledger)) }
        if access.contains(.location) { tools.append(AskLocationTool(toolLedger: ledger)) }
        if access.contains(.health) { tools.append(AskHealthTool(toolLedger: ledger)) }
        if access.contains(.music) { tools.append(AskMusicTool(toolLedger: ledger)) }
        if access.contains(.weather) { tools.append(AskWeatherTool(toolLedger: ledger)) }
        if access.contains(.alarms) { tools.append(AskAlarmTool(toolLedger: ledger, question: question)) }
        return tools
#else
        return []
#endif
    }

    static func readings(in tools: [any AskTool]) -> [AskAppleReading] {
        for tool in tools {
            if let source = tool as? AskToolReadingSource {
                return source.toolLedger.snapshot()
            }
        }
        return []
    }
}

#if ASK_FOUNDATION_MODELS
func boundedAppleCall(
    ledger: AskToolLedger,
    name: String,
    arguments: String,
    trace: String? = nil,
    present: ((String) -> String)? = nil,
    body: () async -> String
) async throws -> String {
    try ledger.claim(name: name, arguments: arguments)
    let output = try await AskTrace.tool(name, arguments: trace ?? arguments) {
        await body()
    }
    ledger.finish(name: name, output: output)
    return present?(output) ?? output
}
#endif

#if ASK_FOUNDATION_MODELS
private struct AskCalendarTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "calendar"

    var description: String {
        let calendar = Calendar.current
        let today = AskCalendarWindow.heading(for: Date(), calendar: calendar, includingYear: true)
        let menu = AskCalendarWindow.dayMenu(now: Date(), calendar: calendar)
        return "Today is \(today). Read one calendar day, upcoming birthdays, or add, change, or remove one event. Copy one number from this list: \(menu). Negative numbers are past days. Do not count the days yourself. For a read, pass action read and that day. For birthdays, pass action birthdays and that day as the start. For an add, pass action add, the title, that day, and the hour and minute. Leave the hour empty for an all-day event. Pass place and notes when the person named them. To change an event, pass action update, its current title, that day, and only the fields that change. newTitle renames it. To remove it, pass action delete and its title. Call once for each day. Each line names that weekday and date. An added event starts with Added. A changed event starts with Updated. A removed event starts with Removed. If the result is Not allowed, say you cannot see the calendar. Do not invent an event. Do not say an event was added, changed, or removed unless the line says so."
    }

    @Generable
    struct Arguments {
        @Guide(description: "Copy the number listed for that weekday. 0 is today. Negative numbers are past days. Do not count the days yourself. Use 0 when adding an event with no day.", .range(AskCalendarWindow.minimumOffset...AskCalendarWindow.maximumOffset))
        var day: Int
        @Guide(description: "read, birthdays, add, update, or delete. Use read unless the person asked for birthdays or to create, change, or remove an event.", .anyOf(["read", "birthdays", "add", "update", "delete"]))
        var action: String?
        @Guide(description: "Event title. The current title when updating or deleting. Leave empty when reading.")
        var title: String?
        @Guide(description: "Hour from 0 to 23 for a timed event. Leave empty for an all-day event, a read, or when the time is not changing.", .range(0...23))
        var hour: Int?
        @Guide(description: "Minute from 0 to 59 for a timed event. Leave empty when reading or for an all-day event.", .range(0...59))
        var minute: Int?
        @Guide(description: "Place for the event, such as Apple Park. Leave empty when reading or when the place is not changing.")
        var place: String?
        @Guide(description: "Notes for the event. Leave empty when reading or when the notes are not changing.")
        var notes: String?
        @Guide(description: "New title when action is update. Leave empty when the title is not changing.")
        var newTitle: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch AskCalendarCommand.parse(
            action: arguments.action,
            day: arguments.day,
            title: arguments.title,
            hour: arguments.hour,
            minute: arguments.minute,
            place: arguments.place,
            notes: arguments.notes,
            newTitle: arguments.newTitle
        ) {
        case .read(let day):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "day \(day)",
                present: AskCalendarItem.forModel
            ) {
                await AskCalendarRead.lines(day: day)
            }
        case .birthdays(let day):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "birthdays \(day)",
                present: AskCalendarItem.forModel
            ) {
                await AskCalendarRead.birthdays(from: day)
            }
        case .add(let title, let day, let hour, let minute, let place, let notes):
            let clock = hour.map { "\($0):\(minute)" } ?? "all day"
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "add \(day) \(title) \(clock)",
                present: AskCalendarItem.forModel
            ) {
                await AskCalendarRead.add(title: title, day: day, hour: hour, minute: minute, place: place, notes: notes)
            }
        case .update(let title, let day, let hour, let minute, let place, let notes, let newTitle):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "update \(day) \(title)",
                present: AskCalendarItem.forModel
            ) {
                await AskCalendarRead.update(
                    title: title,
                    day: day,
                    hour: hour,
                    minute: minute,
                    place: place,
                    notes: notes,
                    newTitle: newTitle
                )
            }
        case .delete(let title, let day):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "delete \(day) \(title)",
                present: AskCalendarItem.forModel
            ) {
                await AskCalendarRead.remove(title: title, day: day)
            }
        case .needsTitle:
            return "A title is needed."
        case .needsChange:
            return "Say what should change."
        case .badTime:
            return "Use an hour from 0 to 23."
        }
    }
}
#endif

#if ASK_FOUNDATION_MODELS
private struct AskRemindersTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "reminders"
    let description = "Read incomplete reminders, or add, change, or remove one reminder. For a read, pass action read and a limit from 1 to 8. The result is a count, not the titles. Say that count in one short sentence. Do not list the titles. The card lists them. For an add, pass action add and the title. Pass notes and priority high, medium, or low when the person named them. Pass a day number when it is due. 0 is today. Leave the day empty when it has no due date. To change one, pass action update and its current title, plus only the fields that change. newTitle renames it. To remove one, pass action delete and its title. An added reminder starts with Added. A changed reminder starts with Updated. A removed reminder starts with Removed. If the result is Not allowed, say you cannot see reminders. Do not invent a reminder. Do not say a reminder was added, changed, or removed unless the line says so."

    @Generable
    struct Arguments {
        @Guide(description: "How many reminders to return, from 1 to 8. Use 8 when adding.", .range(1...8))
        var limit: Int
        @Guide(description: "read, add, update, or delete. Use read unless the person asked to create, change, or remove a reminder.", .anyOf(["read", "add", "update", "delete"]))
        var action: String?
        @Guide(description: "Reminder title. The current title when updating or deleting. Leave empty when reading.")
        var title: String?
        @Guide(description: "Day number when the reminder is due. 0 is today. Leave empty for no due date, when reading, or when the day is not changing.", .range(0...AskCalendarWindow.maximumOffset))
        var day: Int?
        @Guide(description: "Hour from 0 to 23 when the reminder is due at a time. Leave empty for a date-only reminder or when the time is not changing.", .range(0...23))
        var hour: Int?
        @Guide(description: "Minute from 0 to 59 when the reminder is due at a time. Leave empty when the time is not changing.", .range(0...59))
        var minute: Int?
        @Guide(description: "Notes for the reminder. Leave empty when reading or when the notes are not changing.")
        var notes: String?
        @Guide(description: "none, low, medium, or high. Leave empty when reading or when the priority is not changing.", .anyOf(["none", "low", "medium", "high"]))
        var priority: String?
        @Guide(description: "New title when action is update. Leave empty when the title is not changing.")
        var newTitle: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch AskReminderCommand.parse(
            action: arguments.action,
            limit: arguments.limit,
            title: arguments.title,
            day: arguments.day,
            hour: arguments.hour,
            minute: arguments.minute,
            notes: arguments.notes,
            priority: arguments.priority,
            newTitle: arguments.newTitle
        ) {
        case .list(let limit):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "limit \(limit)",
                present: AskReminderItem.forModel
            ) {
                await AskRemindersRead.lines(limit: limit)
            }
        case .add(let title, let day, let hour, let minute, let notes, let priority):
            let due = day.map { "day \($0)" } ?? "none"
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "add \(title) \(due)",
                present: AskReminderItem.forModel
            ) {
                await AskRemindersRead.add(title: title, day: day, hour: hour, minute: minute, notes: notes, priority: priority)
            }
        case .update(let title, let day, let hour, let minute, let notes, let priority, let newTitle):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "update \(title)",
                present: AskReminderItem.forModel
            ) {
                await AskRemindersRead.update(
                    title: title,
                    day: day,
                    hour: hour,
                    minute: minute,
                    notes: notes,
                    priority: priority,
                    newTitle: newTitle
                )
            }
        case .delete(let title):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: name,
                arguments: "delete \(title)",
                present: AskReminderItem.forModel
            ) {
                await AskRemindersRead.remove(title: title)
            }
        case .needsTitle:
            return "A title is needed."
        case .needsChange:
            return "Say what should change."
        case .badTime:
            return "Use an hour from 0 to 23."
        }
    }
}
#endif

#if ASK_FOUNDATION_MODELS
private struct AskContactsTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "contacts"
    let description = "Look up a contact by name, list contacts added recently, or add, change, or remove one contact. For a lookup, pass action look and the name. For contacts that begin with letters, pass those letters and set beginsWith to true. For contacts added recently, pass action look and daysBack. 7 is last week. 30 is last month. Leave the name empty for a recent list. Leave the name empty only for a short list when daysBack is empty. Each line is one person, with the phone and the email when they exist. To add a contact, pass action add, the name, and the phone or email when they were said. To change one, pass action update, the current name, and only the fields that change. newName renames it. To remove one, pass action delete and the name. An added contact starts with Added. A changed contact starts with Updated. A removed contact starts with Removed. If the result is Not allowed, say you cannot see contacts. Do not invent a phone number or email. When the person asks for an email, say the email on the line. Do not say a contact was added, changed, or removed unless the line says so."

    @Generable
    struct Arguments {
        @Guide(description: "look, add, update, or delete. Use look unless the person asked to create, change, or remove a contact.", .anyOf(["look", "add", "update", "delete"]))
        var action: String?
        @Guide(description: "The person's name, or the letters a name begins with. The current name when updating or deleting. Leave empty for a recent list or a short list.")
        var name: String
        @Guide(description: "True when the person asked for names that begin with the letters in name. Otherwise false.")
        var beginsWith: Bool?
        @Guide(description: "How many days back for contacts added recently. 7 is last week. 30 is last month. Leave empty for a name lookup.", .range(1...3_650))
        var daysBack: Int?
        @Guide(description: "Phone number when adding or updating a contact. Leave empty when looking up or when the phone is not changing.")
        var phone: String?
        @Guide(description: "Email address when adding or updating a contact. Leave empty when looking up or when the email is not changing.")
        var email: String?
        @Guide(description: "New name when action is update. Leave empty when the name is not changing.")
        var newName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        switch AskContactCommand.parse(
            action: arguments.action,
            name: arguments.name,
            phone: arguments.phone,
            email: arguments.email,
            beginsWith: arguments.beginsWith,
            newName: arguments.newName,
            daysBack: arguments.daysBack
        ) {
        case .lookup(let name, let prefix):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: self.name,
                arguments: name.isEmpty ? "list" : name,
                trace: name.isEmpty ? "list" : (prefix ? "prefix" : "name")
            ) {
                await AskContactsRead.lines(matching: name, prefix: prefix)
            }
        case .recent(let days):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: self.name,
                arguments: "recent \(days)",
                trace: "recent"
            ) {
                await AskContactsRead.lines(addedWithinDays: days)
            }
        case .add(let name, let phone, let email):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: self.name,
                arguments: "add \(name)",
                trace: "add"
            ) {
                await AskContactsRead.add(name: name, phone: phone, email: email)
            }
        case .update(let name, let phone, let email, let newName):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: self.name,
                arguments: "update \(name)",
                trace: "update"
            ) {
                await AskContactsRead.update(name: name, phone: phone, email: email, newName: newName)
            }
        case .delete(let name):
            return try await boundedAppleCall(
                ledger: toolLedger,
                name: self.name,
                arguments: "delete \(name)",
                trace: "delete"
            ) {
                await AskContactsRead.remove(name: name)
            }
        case .needsName:
            return "A name is needed."
        case .needsChange:
            return "Say what should change."
        }
    }
}
#endif

#if ASK_FOUNDATION_MODELS
private struct AskLocationTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "location"
    let description = "Look up where the person is, where a named place is, or what is nearby. Pass here for the device. Pass nearby for places around the person. Pass a place name, such as Apple Park, to geocode that place. Do not pass nearby as a street. The result is a name and an address. The map shows the place. Set coordinates to true only when the person asked for coordinates, latitude, or longitude. Otherwise leave it false and do not state coordinates. If the result is Not allowed, say you cannot see the location. Do not invent a place."

    @Generable
    struct Arguments {
        @Guide(description: "here for the device. nearby for places around the person. Otherwise the place name, such as Apple Park.")
        var place: String
        @Guide(description: "True only when the person asked for coordinates, latitude, or longitude. Otherwise false.")
        var coordinates: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        let raw = arguments.place.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = raw.isEmpty || AskPlaceQuery.isDevice(raw) ? "here" : raw
        let include = arguments.coordinates == true
        return try await boundedAppleCall(
            ledger: toolLedger,
            name: name,
            arguments: query,
            present: { AskLocationPin.forModel($0, includeCoordinates: include) }
        ) {
            await AskLocationRead.lines(place: query)
        }
    }
}
#endif

#if ASK_FOUNDATION_MODELS
private struct AskHealthTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "health"
    let description = "Read steps, heart rate, active energy, walking distance, flights, exercise, weight, height, body fat, resting heart rate, blood pressure, blood glucose, oxygen, temperature, breathing rate, VO2 max, workouts, and sleep. Pass kind workouts for workouts and kind sleep for sleep. Pass span week for this week or the last 7 days, span month for this month, and span year for this year. Otherwise pass span today. If the result is Not allowed, say you cannot see health data. Do not invent a number. Say the number the question asks about in one or two short sentences. A week, month, or year answer uses that period's total. The lines are shown on the card."

    @Generable
    struct Arguments {
        @Guide(description: "all, steps, heart, energy, distance, flights, exercise, weight, height, body fat, resting heart, blood pressure, glucose, oxygen, temperature, breathing, vo2, workouts, or sleep. Use all unless the question names one. Use workouts for workouts and sleep for sleep.", .anyOf(AskHealthCatalog.kindChoices))
        var kind: String
        @Guide(description: "today, week, month, or year. Use week for this week or the last 7 days, month for this month, and year for this year.", .anyOf(["today", "week", "month", "year"]))
        var span: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let kind = arguments.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let span = AskHealthCatalog.span(named: arguments.span)
        return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "\(kind) \(span)") {
            await AskHealthRead.lines(kind: kind, span: span)
        }
    }
}
#endif

#if ASK_FOUNDATION_MODELS
private struct AskMusicTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "music"
    let description = "Read what is playing, the last song played, or search songs, albums, or playlists. Play, pause, skip, or go back when the person asks. Pass which now for what is playing. Pass which recent for the last song played, and for songs the person listened to, including top songs and the past week. Do not pass those words as a search title. Pass which song, album, or playlist and the title to search. Pass which play and the title to start playback. Pass which pause to pause, which next to skip, and which previous to go back. Each line is one song, album, or playlist. A line that starts with Now is what is playing. A line that starts with Recent is play history, not the song playing now. Say the title and the artist. The card shows the rest. Do not say a web address. If the result is Not allowed, say you cannot see the music. Do not invent a song, album, or playlist. Do not say the song changed unless the tool says so."

    @Generable
    struct Arguments {
        @Guide(description: "now, recent, song, album, playlist, play, pause, next, or previous. Use now for what is playing. Use recent for the last song played and for songs the person listened to. Use play to start a song or album. Use pause to pause, next to skip, and previous to go back.", .anyOf(["now", "recent", "song", "album", "playlist", "play", "pause", "next", "previous"]))
        var which: String
        @Guide(description: "The song, album, or playlist title, or the artist. Leave empty when which is now.")
        var query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let request = AskMusicQuery.request(which: arguments.which, query: arguments.query)
        let label = request.term.isEmpty ? "\(request.kind)" : "\(request.kind) \(request.term)"
        return try await boundedAppleCall(
            ledger: toolLedger,
            name: name,
            arguments: label,
            present: AskMusicLine.forModel
        ) {
            await AskMusicRead.lines(request)
        }
    }
}
#endif

#if ASK_FOUNDATION_MODELS
private struct AskWeatherTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "weather"
    let description = "Read the forecast for a city, or where the person is when no city is named. Pass span hourly for the hours of one day, or span daily for each day. Pass day 0 for today, 1 for tomorrow, or the weekday number listed on the calendar tool. Pass days 7 for a week. Pass place with the city, such as Brookfield. Leave place empty for where the person is. A daily result is one line per day. An hourly result lists the hours of that one day. Say it in one or two short sentences. The card lists each day or each hour. If the result is Not allowed, say you cannot see the weather. Do not invent a temperature."

    @Generable
    struct Arguments {
        @Guide(description: "hourly or daily. Use hourly only when the person asked for hours.", .anyOf(["hourly", "daily"]))
        var span: String?
        @Guide(description: "0 is today. 1 is tomorrow. Use the weekday number from the calendar tool when a weekday is named.", .range(0...AskWeatherQuery.maximumOffset))
        var day: Int?
        @Guide(description: "How many days for a daily forecast, from 1 to 7. Use 1 for one named day and 7 for a week. Ignored for hourly.", .range(1...7))
        var days: Int?
        @Guide(description: "The city or place, such as Brookfield. Leave empty for where the person is.")
        var place: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let request = AskWeatherQuery.request(
            span: arguments.span,
            day: arguments.day,
            days: arguments.days,
            place: arguments.place
        )
        let label = "\(request.span) \(request.dayOffset) \(request.dayCount)"
        return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: label) {
            await AskWeatherRead.lines(request)
        }
    }
}
#endif

/// One calendar day. Offset 0 is today. Negative offsets are past days. The end is the start of the next day and is not included.
struct AskCalendarWindow: Equatable {
    static let minimumOffset = -13
    static let maximumOffset = 13

    var start: Date
    var end: Date
    var title: String

    static func day(offset: Int, now: Date, calendar: Calendar) -> AskCalendarWindow? {
        let clamped = min(max(offset, minimumOffset), maximumOffset)
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: clamped, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return AskCalendarWindow(start: start, end: end, title: heading(for: start, calendar: calendar))
    }

    /// The one day named in the question, from -13 through 13. Nil when none or more than one is named.
    static func offset(namedIn question: String, now: Date, calendar: Calendar) -> Int? {
        let tokens = dayTokens(in: question)
        var offsets: [Int] = []
        if tokens.contains("today") || tokens.contains("tonight") { offsets.append(0) }
        if tokens.contains("tomorrow") { offsets.append(1) }
        if tokens.contains("yesterday") { offsets.append(-1) }
        let symbols = calendar.weekdaySymbols.map { foldedDay($0) }
        let todayWeekday = calendar.component(.weekday, from: now)
        for (index, name) in symbols.enumerated() where tokens.contains(name) {
            var delta = (index + 1) - todayWeekday
            if delta < 0 { delta += 7 }
            offsets.append(delta)
        }
        let unique = Array(Set(offsets)).filter { (minimumOffset...maximumOffset).contains($0) }
        guard unique.count == 1 else { return nil }
        return unique[0]
    }

    /// A calendar result for a different weekday than the question asked. Nil when the lines already match, or when no single day was named.
    static func calendarRereadOffset(question: String, readings: [AskAppleReading], now: Date, calendar: Calendar) -> Int? {
        guard let offset = offset(namedIn: question, now: now, calendar: calendar),
              let window = day(offset: offset, now: now, calendar: calendar) else { return nil }
        let lines = readings.filter { $0.name == "calendar" }.flatMap(\.lines)
        if lines.contains(where: AskAppleCopy.keepsWrite) { return nil }
        if lines.isEmpty { return AskSourceFocus.asksCalendar(question) ? offset : nil }
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: window.start) - 1]
        let matches = lines.contains { line in
            let head = AskCalendarItem.plain(line).split(separator: "·").first.map(String.init) ?? AskCalendarItem.plain(line)
            return head.localizedStandardContains(weekday)
        }
        return matches ? nil : offset
    }

    /// `-1 Tuesday, Oct 6; 0 Wednesday, Oct 7; 1 Thursday, Oct 8` so the model copies a number instead of counting.
    static func dayMenu(now: Date, calendar: Calendar) -> String {
        (minimumOffset...maximumOffset).compactMap { offset in
            guard let window = day(offset: offset, now: now, calendar: calendar) else { return nil }
            return "\(offset) \(window.title)"
        }.joined(separator: "; ")
    }

    private static func dayTokens(in question: String) -> Set<String> {
        Set(question.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter }
            .map { foldedDay(String($0)) })
    }

    private static func foldedDay(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func heading(for date: Date, calendar: Calendar, includingYear: Bool = false) -> String {
        var style = Date.FormatStyle(
            locale: calendar.locale ?? .autoupdatingCurrent,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        .weekday(.wide)
        .month(.abbreviated)
        .day()
        if includingYear {
            style = style.year()
        }
        return date.formatted(style)
    }
}

/// What a repair would read. Tests use this so they do not open EventKit, Contacts, HealthKit, or the geocoder.
struct AskAppleRepairPlan: Equatable {
    var keep: Set<String>?
    var calendarDay: Int?
    var healthKind: String?
    var healthSpan: String
    var place: String?
    var contactQuery: String?
    /// True when the question asked for names that begin with `contactQuery`.
    var contactPrefix: Bool
    /// Days back when the question asked for contacts added recently.
    var contactRecentDays: Int?
    var rereadContact: Bool
    var music: AskMusicQuery.Request?
    var weather: AskWeatherRequest?
    /// Read the open reminders when that tool never ran.
    var readReminders: Bool
    /// List the alarms that are on. A count does not schedule one.
    var alarmList: Bool
    /// Change an existing alarm. Nil when this question is not an edit.
    var alarmChange: AskAlarmChange?
    /// Remove an existing alarm, or every alarm when the hour is nil.
    var alarmRemoval: AskAlarmRemoval?
    /// Alarms parsed from the question when that tool never scheduled one.
    var alarmDrafts: [AskAlarmDraft]
    /// Search the photo library when that tool never ran.
    var readPhotos: Bool
}

/// Replaces a calendar result for the wrong weekday, reads health when that tool never ran, and looks up a place on a tool-only skill.
enum AskAppleRepair {
    static func plan(
        question: String,
        readings: [AskAppleReading],
        toolNames: Set<String>,
        lookupPlaces: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AskAppleRepairPlan {
        let focus = AskSourceFocus.named(in: question)
        let healthSpan = AskHealthCatalog.span(in: question)
        var healthKind: String?
        if toolNames.contains("health"), !AskSourceFocus.asksWeather(question), let kind = AskHealthCatalog.kind(in: question) {
            let lines = readings.filter { $0.name == "health" }.flatMap(\.lines)
            if AskHealthCatalog.isActivity(kind) {
                let marker = kind == "sleep" ? "Sleep:" : "Workouts:"
                if !lines.contains(where: { $0.hasPrefix(marker) }) {
                    healthKind = kind
                }
            } else {
                let metric = AskHealthCatalog.metrics(matching: kind).first
                let phrase = AskHealthCatalog.periodPhrase(healthSpan)
                let periodApplies = phrase != nil && metric?.latestSample == false
                let already = phrase.map { phrase in
                    lines.contains { $0.localizedStandardContains(phrase) }
                } ?? false
                if lines.isEmpty || (periodApplies && !already) {
                    healthKind = kind
                }
            }
        }
        var place: String?
        if lookupPlaces, toolNames.contains("location"), let found = AskPlaceQuery.lookup(in: question) {
            let existing = readings.filter { $0.name == "location" }.flatMap(\.lines)
            let covered: Bool
            if found == "here" {
                covered = existing.contains { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !trimmed.isEmpty
                        && trimmed != "No matching place."
                        && trimmed != AskAppleCopy.denied
                        && trimmed != "Location is unavailable."
                }
            } else if found == "nearby" {
                covered = AskLocationPin.places(in: existing).count >= 2
            } else {
                covered = existing.contains { $0.localizedStandardContains(found) }
            }
            if !covered { place = found }
        }
        var contactQuery: String?
        var contactPrefix = false
        var contactRecentDays: Int?
        var rereadContact = false
        if toolNames.contains("contacts") {
            let lines = readings.filter { $0.name == "contacts" }.flatMap(\.lines)
            if !lines.contains(where: AskAppleCopy.keepsWrite) {
                if let days = AskContactQuery.recentDays(in: question) {
                    contactRecentDays = days
                    let people = lines.map { AskContactLine.person(from: $0) }.filter(\.isPerson)
                    rereadContact = people.isEmpty && !lines.contains {
                        $0 == AskAppleCopy.denied || $0 == "No recently added contacts."
                    }
                } else if let request = AskContactQuery.request(in: question) {
                    contactQuery = request.name
                    contactPrefix = request.prefix
                    let matched = AskContactLine.filtered(lines, query: request.name, prefix: request.prefix)
                    let hasEmail = matched.contains { AskContactLine.person(from: $0).email.contains("@") }
                    rereadContact = matched.isEmpty || (AskContactQuery.asksEmail(question) && !hasEmail)
                }
            }
        }
        var music: AskMusicQuery.Request?
        if toolNames.contains("music"), AskSourceFocus.asksMusic(question) {
            let request = AskMusicQuery.request(in: question)
            let lines = readings.filter { $0.name == "music" }.flatMap(\.lines)
            if AskMusicQuery.needsReread(request, lines: lines) {
                music = request
            }
        }
        var weather: AskWeatherRequest?
        if toolNames.contains("weather"), AskSourceFocus.asksWeather(question) {
            let request = AskWeatherQuery.request(in: question, now: now, calendar: calendar)
            let lines = readings.filter { $0.name == "weather" }.flatMap(\.lines)
            if AskWeatherQuery.needsReread(request, lines: lines) {
                weather = request
            }
        }
        let alarmOnly = AskSourceFocus.asksAlarms(question) && !AskSourceFocus.asksCalendar(question)
        let reminderLines = readings.filter { $0.name == "reminders" }.flatMap(\.lines)
        let readReminders = toolNames.contains("reminders")
            && reminderLines.isEmpty
            && wantsReminderList(question)
        let alarmIntent = AskAlarmCommand.intent(in: question, now: now, calendar: calendar)
        let alarmLines = readings.filter { $0.name == "alarms" }.flatMap(\.lines)
        let alarmBlocked = alarmLines.contains { line in
            line == AskAppleCopy.denied
                || line == "Alarm isn't available."
                || line == "Too many alarms."
        }
        let alarmListed = alarmLines.contains { AskAlarmList.item(from: $0) != nil || $0 == "No alarms." }
        let asksList: Bool
        if case .list = alarmIntent {
            asksList = true
        } else {
            asksList = false
        }
        let alarmList = toolNames.contains("alarms") && !alarmBlocked && !alarmListed && asksList
        let alarmChanged = alarmLines.contains { line in
            line.hasPrefix(AskAppleCopy.updatedPrefix)
                || line == "No alarm at that time."
                || line == "Say which alarm to change."
        }
        let alarmChange: AskAlarmChange?
        if toolNames.contains("alarms"), !alarmBlocked, !alarmChanged, case .change(let change) = alarmIntent {
            alarmChange = change
        } else {
            alarmChange = nil
        }
        let alarmRemoved = alarmLines.contains { line in
            line.hasPrefix(AskAppleCopy.removedPrefix)
                || line == "No alarm at that time."
                || line == "No alarms."
        }
        let alarmRemoval: AskAlarmRemoval?
        if toolNames.contains("alarms"), !alarmBlocked, !alarmRemoved, case .remove(let removal) = alarmIntent {
            alarmRemoval = removal
        } else {
            alarmRemoval = nil
        }
        let alarmWritten = alarmLines.contains { line in
            AskAppleCopy.keepsWrite(line)
                || line == "Say a time."
                || line == "A title is needed."
                || line.hasPrefix("Use an hour")
        }
        let alarmDrafts: [AskAlarmDraft]
        if toolNames.contains("alarms"), !alarmBlocked, !alarmWritten, case .set(let drafts) = alarmIntent {
            alarmDrafts = drafts
        } else {
            alarmDrafts = []
        }
        let photoLines = readings.filter { $0.name == "photos" }.flatMap(\.lines)
        let readPhotos = toolNames.contains(AskPhotos.toolName)
            && AskPhotos.matches(question)
            && photoLines.isEmpty
        return AskAppleRepairPlan(
            keep: focus.isEmpty ? nil : focus,
            calendarDay: toolNames.contains("calendar") && !alarmOnly
                ? AskCalendarWindow.calendarRereadOffset(question: question, readings: readings, now: now, calendar: calendar)
                : nil,
            healthKind: healthKind,
            healthSpan: healthSpan,
            place: place,
            contactQuery: contactQuery,
            contactPrefix: contactPrefix,
            contactRecentDays: contactRecentDays,
            rereadContact: rereadContact,
            music: music,
            weather: weather,
            readReminders: readReminders,
            alarmList: alarmList,
            alarmChange: alarmChange,
            alarmRemoval: alarmRemoval,
            alarmDrafts: alarmDrafts,
            readPhotos: readPhotos
        )
    }

    static func apply(
        question: String,
        readings: [AskAppleReading],
        toolNames: Set<String>,
        lookupPlaces: Bool = false
    ) async -> (readings: [AskAppleReading], didChange: Bool) {
        let plan = plan(question: question, readings: readings, toolNames: toolNames, lookupPlaces: lookupPlaces)
        var readings = readings
        var didChange = false
        if let keep = plan.keep {
            let before = readings.count
            readings.removeAll { AskAppleCards.names.contains($0.name) && !keep.contains($0.name) }
            if readings.count != before { didChange = true }
        }
        if let offset = plan.calendarDay {
            let output = await AskCalendarRead.lines(day: offset)
            readings.removeAll { $0.name == "calendar" }
            readings.insert(AskAppleReading(name: "calendar", lines: lines(output)), at: 0)
            didChange = true
            AskTrace.decision("calendar day corrected")
            AskTrace.attribute("calendarDay", String(offset))
        }
        if let kind = plan.healthKind {
            let output = await AskHealthRead.lines(kind: kind, span: plan.healthSpan)
            readings.removeAll { $0.name == "health" }
            readings.append(AskAppleReading(name: "health", lines: lines(output)))
            didChange = true
            AskTrace.decision(AskHealthCatalog.readDecision(plan.healthSpan))
            AskTrace.attribute("healthKind", kind)
        }
        if let place = plan.place {
            let output = await AskLocationRead.lines(place: place)
            readings.removeAll { $0.name == "location" }
            readings.append(AskAppleReading(name: "location", lines: lines(output)))
            didChange = true
            AskTrace.decision("place read")
            let label = place == "here" || place == "nearby" ? place : String(place.prefix(80))
            AskTrace.attribute("place", label)
        }
        if let days = plan.contactRecentDays {
            if plan.rereadContact {
                let contactLines = lines(await AskContactsRead.lines(addedWithinDays: days))
                readings.removeAll { $0.name == "contacts" }
                readings.append(AskAppleReading(name: "contacts", lines: contactLines))
                didChange = true
                AskTrace.decision("contact recent read")
                AskTrace.attribute("contactRecentDays", String(days))
            }
        } else if let query = plan.contactQuery {
            var contactLines = readings.filter { $0.name == "contacts" }.flatMap(\.lines)
            if plan.rereadContact {
                contactLines = lines(await AskContactsRead.lines(matching: query, prefix: plan.contactPrefix))
            }
            let filtered = AskContactLine.filtered(contactLines, query: query, prefix: plan.contactPrefix)
            let kept = contactLinesKept(filtered, raw: contactLines)
            if plan.rereadContact || kept != contactLines {
                readings.removeAll { $0.name == "contacts" }
                readings.append(AskAppleReading(name: "contacts", lines: kept))
                didChange = true
                AskTrace.decision(plan.rereadContact ? "contact read" : "contacts filtered")
            }
        }
        if let music = plan.music {
            switch music.kind {
            case .pause, .next, .previous, .play:
                break
            case .now, .recent, .song, .album, .playlist:
                let output = await AskMusicRead.lines(music)
                readings.removeAll { $0.name == "music" }
                readings.append(AskAppleReading(name: "music", lines: lines(output)))
                didChange = true
                let musicDecision = switch music.kind {
                case .now: "music now"
                case .recent: "music recent"
                case .song, .album, .playlist: "music search"
                case .play, .pause, .next, .previous: "music search"
                }
                AskTrace.decision(musicDecision)
            }
        }
        if let weather = plan.weather {
            let output = await AskWeatherRead.lines(weather)
            readings.removeAll { $0.name == "weather" }
            readings.append(AskAppleReading(name: "weather", lines: lines(output)))
            didChange = true
            AskTrace.decision(weather.span == .hourly ? "weather hourly" : "weather daily")
        }
#if canImport(Photos)
        if plan.readPhotos {
            let output = await photoReading(question)
            readings.removeAll { $0.name == "photos" }
            readings.append(AskAppleReading(name: "photos", lines: lines(output)))
            didChange = true
            AskTrace.decision(AskPhotosQuery.listsAlbums(question) ? "photo albums" : "photo read")
        }
#endif
        if plan.readReminders {
            let output = await AskRemindersRead.lines(limit: 8)
            readings.removeAll { $0.name == "reminders" }
            readings.append(AskAppleReading(name: "reminders", lines: lines(output)))
            didChange = true
            AskTrace.decision("reminder read")
        }
        if plan.alarmList {
            let output = await AskAlarmRead.listing()
            readings.removeAll { $0.name == "alarms" }
            readings.append(AskAppleReading(name: "alarms", lines: lines(output)))
            didChange = true
            AskTrace.decision("alarm list")
        }
        if let change = plan.alarmChange {
            let output = await AskAlarmRead.change(change)
            readings.removeAll { $0.name == "alarms" }
            readings.append(AskAppleReading(name: "alarms", lines: lines(output)))
            didChange = true
            AskTrace.decision("alarm change")
        }
        if let removal = plan.alarmRemoval {
            let output = await AskAlarmRead.remove(removal)
            readings.removeAll { $0.name == "alarms" }
            readings.append(AskAppleReading(name: "alarms", lines: lines(output)))
            didChange = true
            AskTrace.decision("alarm remove")
        }
        if !plan.alarmDrafts.isEmpty {
            let output = await AskAlarms.schedule(plan.alarmDrafts)
            readings.removeAll { $0.name == "alarms" }
            readings.append(AskAppleReading(name: "alarms", lines: lines(output)))
            didChange = true
            AskTrace.decision("alarm set")
        }
        let alarmLines = readings.filter { $0.name == "alarms" }.flatMap(\.lines)
        let keptAlarms = AskAlarmLine.kept(alarmLines, matching: question)
        if keptAlarms != alarmLines {
            readings.removeAll { $0.name == "alarms" }
            if !keptAlarms.isEmpty {
                readings.append(AskAppleReading(name: "alarms", lines: keptAlarms))
            }
            didChange = true
        }
        return (readings, didChange)
    }

    /// A list question. Adding, changing, or removing a reminder stays with the model.
    private static func wantsReminderList(_ question: String) -> Bool {
        guard AskSourceFocus.asksReminders(question) else { return false }
        let folded = AskAppleCopy.folded(question)
        let writes = [
            "add a reminder", "add reminder", "create a reminder", "new reminder", "remind me",
            "delete the reminder", "delete a reminder", "remove the reminder", "remove a reminder",
            "change the reminder", "update the reminder"
        ]
        if writes.contains(where: { folded.localizedStandardContains($0) }) { return false }
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        if tokens.contains("add") || tokens.contains("create") { return false }
        return true
    }

    private static func contactLinesKept(_ filtered: [String], raw: [String]) -> [String] {
        if !filtered.isEmpty { return filtered }
        if raw.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == AskAppleCopy.denied }) {
            return [AskAppleCopy.denied]
        }
        return ["No matching contacts."]
    }

#if canImport(Photos)
    private static func photoReading(_ question: String) async -> String {
        if AskPhotosQuery.listsAlbums(question) {
            return await AskPhotosRead.albums()
        }
        let parsed = AskPhotosQuery.fromQuestion(question)
        return await AskPhotosRead.lines(await AskPhotosQuery.resolvePlace(parsed, question: question))
    }

#endif
    private static func lines(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// A photo coordinate turned into a map pin. `unnamed` means the lookup could not name the place.
enum AskPhotoLocation {
    static let unnamed = "Saved location"

    static func pin(latitude: Double, longitude: Double) async -> String {
        await AskLocationRead.photoPin(latitude: latitude, longitude: longitude)
    }
}

enum AskLocationRead {
    static func deviceFix() async -> AskLocationOutcome {
        let reader = await MainActor.run { AskLocationReader() }
        return await reader.read()
    }

    static func lines(place: String) async -> String {
        let query = place.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.caseInsensitiveCompare("nearby") == .orderedSame {
            return await nearby()
        }
        if AskPlaceQuery.isDevice(query) {
            return await device()
        }
        if let found = await named(query) { return found }
        return "No matching place."
    }

    private static func device() async -> String {
        let reader = await MainActor.run { AskLocationReader() }
        let outcome = await reader.read()
        switch outcome {
        case .denied:
            return AskAppleCopy.denied
        case .unavailable:
            return "Location is unavailable."
        case .fix(let location):
            return await reverse(location)
        }
    }

    /// Places around the device. The map shows them. Coordinates stay off the spoken line.
    @MainActor
    private static func nearby() async -> String {
        let outcome = await AskLocationReader().read()
        switch outcome {
        case .denied:
            return AskAppleCopy.denied
        case .unavailable:
            return "Location is unavailable."
        case .fix(let location):
            let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 1600)
            request.pointOfInterestFilter = .includingAll
            guard let response = try? await MKLocalSearch(request: request).start() else {
                return "Nothing nearby."
            }
            let lines = response.mapItems.prefix(5).map(describe)
            return lines.isEmpty ? "Nothing nearby." : lines.joined(separator: "\n")
        }
    }

    /// A city from a weather question. The forecast uses the coordinate. Tests do not call this.
    @MainActor
    static func coordinate(forPlace query: String) async -> CLLocation? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let response = try? await MKLocalSearch(request: request).start(),
           let item = response.mapItems.first {
            return CLLocation(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
        }
        guard let geocode = MKGeocodingRequest(addressString: trimmed),
              let items = try? await geocode.mapItems,
              let item = items.first else {
            return nil
        }
        return CLLocation(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
    }

    /// Place name to a map pin and a street address. A second lookup runs when the name search is empty.
    @MainActor
    private static func named(_ query: String) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let response = try? await MKLocalSearch(request: request).start() {
            let lines = response.mapItems.prefix(3).map(describe)
            if !lines.isEmpty { return lines.joined(separator: "\n") }
        }
        guard let geocode = MKGeocodingRequest(addressString: query),
              let items = try? await geocode.mapItems,
              !items.isEmpty else {
            return nil
        }
        return items.prefix(3).map(describe).joined(separator: "\n")
    }

    /// The photo's own coordinate, named when a lookup succeeds. Not where the person is now.
    static func photoPin(latitude: Double, longitude: Double) async -> String {
        let line = await reverse(CLLocation(latitude: latitude, longitude: longitude))
        let parsed = AskLocationPin.parse(line)
        let label = parsed.place == nil || parsed.label == "Current location" ? AskPhotoLocation.unnamed : parsed.label
        return AskLocationPin.line(label: label, latitude: latitude, longitude: longitude)
    }

    /// Coordinates to a place name and address. The map pin stays on the stored line.
    @MainActor
    private static func reverse(_ location: CLLocation) async -> String {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else {
            return AskLocationPin.line(
                label: "Current location",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
        return describe(item)
    }

    private static func describe(_ item: MKMapItem) -> String {
        var parts: [String] = []
        if let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            parts.append(name)
        }
        if let address = item.address?.shortAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty,
           !parts.contains(where: { $0.localizedStandardCompare(address) == .orderedSame }) {
            parts.append(address)
        } else if let full = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !full.isEmpty,
           !parts.contains(where: { $0.localizedStandardCompare(full) == .orderedSame }) {
            parts.append(full)
        } else if let city = item.addressRepresentations?.cityName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !city.isEmpty,
                  !parts.contains(where: { $0.localizedStandardCompare(city) == .orderedSame }) {
            parts.append(city)
        }
        let joined = AskLocationPin.addressLine(parts)
        let label = joined.isEmpty ? "Current location" : joined
        return AskLocationPin.line(
            label: label,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude
        )
    }
}

enum AskLocationOutcome {
    case fix(CLLocation)
    case denied
    case unavailable
}

@MainActor
private final class AskLocationReader: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<AskLocationOutcome, Never>?
    private var requested = false

    func read() async -> AskLocationOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.manager.delegate = self
            self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.requestFix()
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                self.finish(.denied)
            @unknown default:
                self.finish(.denied)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                self.finish(.unavailable)
            }
        }
    }

    private func requestFix() {
        guard !requested else { return }
        requested = true
        manager.requestLocation()
    }

    private func finish(_ outcome: AskLocationOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.requestFix()
            case .notDetermined:
                break
            case .denied, .restricted:
                self.finish(.denied)
            @unknown default:
                self.finish(.denied)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            if let location {
                self.finish(.fix(location))
            } else {
                self.finish(.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError _: Error) {
        Task { @MainActor in
            self.finish(.unavailable)
        }
    }
}

package enum AskHealthCatalog {
    /// Words the health tool accepts for `kind`. The guide uses this list.
    static let kindChoices = [
        "all", "steps", "heart", "energy", "distance", "flights", "exercise",
        "weight", "height", "body fat", "resting heart", "blood pressure", "glucose", "oxygen",
        "temperature", "breathing", "vo2", "workouts", "sleep"
    ]

    /// Workouts and sleep are their own reads. They are not quantity metrics, so a chart does not claim them.
    static func isActivity(_ kind: String) -> Bool {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sleep", "workout", "workouts": true
        default: false
        }
    }

    package enum Metric: CaseIterable, Sendable {
        case steps, heart, energy, distance, flights, exercise
        case weight, height, bodyFat, restingHeart, bloodPressure, glucose, oxygen, temperature, breathing, vo2

        package var title: String {
            switch self {
            case .steps: "Steps"
            case .heart: "Heart rate"
            case .energy: "Active energy"
            case .distance: "Walking distance"
            case .flights: "Flights climbed"
            case .exercise: "Exercise"
            case .weight: "Weight"
            case .height: "Height"
            case .bodyFat: "Body fat"
            case .restingHeart: "Resting heart rate"
            case .bloodPressure: "Blood pressure"
            case .glucose: "Blood glucose"
            case .oxygen: "Oxygen"
            case .temperature: "Temperature"
            case .breathing: "Breathing rate"
            case .vo2: "VO2 max"
            }
        }

        var words: [String] {
            switch self {
            case .steps: ["steps", "step"]
            case .heart: ["heart rate", "heartrate", "heart"]
            case .energy: ["active energy", "calories", "kilocalories", "energy"]
            case .distance: ["walking distance", "distance", "miles", "kilometers"]
            case .flights: ["flights", "stairs"]
            case .exercise: ["exercise minutes", "exercise"]
            case .weight: ["body mass", "weight", "pounds", "kilograms"]
            case .height: ["height"]
            case .bodyFat: ["body fat", "fat"]
            case .restingHeart: ["resting heart", "resting"]
            case .bloodPressure: ["blood pressure", "systolic", "diastolic"]
            case .glucose: ["blood sugar", "glucose", "sugar"]
            case .oxygen: ["oxygen", "spo2", "saturation"]
            case .temperature: ["temperature", "temp"]
            case .breathing: ["breathing", "respiratory", "respiration"]
            case .vo2: ["vo2max", "vo2"]
            }
        }

#if canImport(HealthKit)
        var identifier: HKQuantityTypeIdentifier {
            switch self {
            case .steps: .stepCount
            case .heart: .heartRate
            case .energy: .activeEnergyBurned
            case .distance: .distanceWalkingRunning
            case .flights: .flightsClimbed
            case .exercise: .appleExerciseTime
            case .weight: .bodyMass
            case .height: .height
            case .bodyFat: .bodyFatPercentage
            case .restingHeart: .restingHeartRate
            case .bloodPressure: .bloodPressureSystolic
            case .glucose: .bloodGlucose
            case .oxygen: .oxygenSaturation
            case .temperature: .bodyTemperature
            case .breathing: .respiratoryRate
            case .vo2: .vo2Max
            }
        }
#endif

        /// Today's total or average. Latest is the newest sample, which is how weight is stored.
        var latestSample: Bool {
            switch self {
            case .steps, .heart, .energy, .distance, .flights, .exercise: false
            case .weight, .height, .bodyFat, .restingHeart, .bloodPressure, .glucose, .oxygen, .temperature, .breathing, .vo2: true
            }
        }

        var averageToday: Bool { self == .heart }

        var percent: Bool { self == .bodyFat || self == .oxygen }

        package var measurement: AskHealthMeasurement {
            switch self {
            case .steps: .steps
            case .heart: .heart
            case .energy: .energy
            case .distance: .distance
            case .flights: .flights
            case .exercise: .exercise
            case .weight: .weight
            case .height: .height
            case .bodyFat: .bodyFat
            case .restingHeart: .restingHeart
            case .bloodPressure: .bloodPressure
            case .glucose: .glucose
            case .oxygen: .oxygen
            case .temperature: .temperature
            case .breathing: .breathing
            case .vo2: .vo2
            }
        }

        package var key: String { measurement.rawValue }
    }

    /// Bars for totals. A line for heart rate and for the newest sample.
    package static func chartKind(for metric: Metric) -> AskHealthChartKind {
        if metric.latestSample || metric.averageToday { return .line }
        return .bar
    }

    package static func axisLabel(for metric: Metric) -> String {
        let metricSystem = Locale.current.measurementSystem == .metric
        switch metric {
        case .steps: return "Steps"
        case .heart, .restingHeart: return "bpm"
        case .energy: return "kcal"
        case .distance: return metricSystem ? "km" : "mi"
        case .flights: return "Flights"
        case .exercise: return "min"
        case .weight: return metricSystem ? "kg" : "lb"
        case .height: return metricSystem ? "cm" : "in"
        case .bodyFat, .oxygen: return "%"
        case .bloodPressure: return "mmHg"
        case .glucose: return "mg/dL"
        case .temperature: return metricSystem ? "°C" : "°F"
        case .breathing: return "breaths"
        case .vo2: return "VO2"
        }
    }

    /// Tool line. Today has no suffix, so an older steps line still matches.
    static func summary(title: String, value: String, span: String) -> String {
        switch span {
        case "week": "\(title): \(value) this week"
        case "month": "\(title): \(value) this month"
        case "year": "\(title): \(value) this year"
        default: "\(title): \(value)"
        }
    }

    package static func headline(value: String, unit: String, range: AskHealthRange) -> String {
        let base = "\(value) \(unit)"
        switch range {
        case .day: return base
        case .week: return "\(base) this week"
        case .month: return "\(base) this month"
        case .year: return "\(base) this year"
        }
    }

    static func missingValue(span: String) -> String {
        switch span {
        case "week": "Nothing recorded this week."
        case "month": "Nothing recorded this month."
        case "year": "Nothing recorded this year."
        default: "Nothing recorded today."
        }
    }

    static func periodPhrase(_ span: String) -> String? {
        switch span {
        case "week": "this week"
        case "month": "this month"
        case "year": "this year"
        default: nil
        }
    }

    static func readDecision(_ span: String) -> String {
        switch span {
        case "week": "health week"
        case "month": "health month"
        case "year": "health year"
        default: "health read"
        }
    }

    /// A named measurement, or every measurement when the question does not name one.
    static func metrics(matching kind: String) -> [Metric] {
        let folded = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if folded.isEmpty || folded == "all" || folded == "health" || folded == "info" || folded == "everything" {
            return Metric.allCases
        }
        let hits: [(Metric, String)] = Metric.allCases.compactMap { metric in
            let best = metric.words
                .filter { folded == $0 || folded.contains($0) }
                .max { $0.count < $1.count }
            return best.map { (metric, $0) }
        }
        guard !hits.isEmpty else { return Metric.allCases }
        let kept = Set(hits.filter { hit in
            !hits.contains { other in
                other.0 != hit.0
                    && other.1.count > hit.1.count
                    && hit.0.words.contains { other.1.contains($0) }
            }
        }.map(\.0))
        return Metric.allCases.filter { kept.contains($0) }
    }

    /// The measurement named in a question, such as "steps". Sleep and workouts win over a quantity word. Nil when the question names none.
    static func kind(in question: String) -> String? {
        let folded = AskAppleCopy.folded(question)
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        if tokens.contains("sleep") || tokens.contains("slept") || tokens.contains("asleep") || folded.localizedStandardContains("sleep") {
            return "sleep"
        }
        if tokens.contains("workout") || tokens.contains("workouts") {
            return "workouts"
        }
        let hits: [(Metric, String)] = Metric.allCases.compactMap { metric in
            let best = metric.words.filter { folded.contains($0) }.max { $0.count < $1.count }
            return best.map { (metric, $0) }
        }
        return hits.max { $0.1.count < $1.1.count }?.1
    }

    /// Year, then month, then the last seven days. Weekend stays today.
    static func span(in question: String) -> String {
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        if tokens.contains("year") || tokens.contains("years") || tokens.contains("yearly") { return "year" }
        if tokens.contains("month") || tokens.contains("months") || tokens.contains("monthly") { return "month" }
        if tokens.contains("week") || tokens.contains("weeks") || tokens.contains("weekly") { return "week" }
        let folded = AskAppleCopy.folded(question)
        if folded.localizedStandardContains("7 days") || folded.localizedStandardContains("seven days") { return "week" }
        return "today"
    }

    static func span(named raw: String?) -> String {
        span(in: raw ?? "")
    }

    /// A week, month, or year question says that period. Today's number is not that total.
    static func weekSpeech(_ text: String, question: String, readings: [AskAppleReading]) -> String {
        let span = span(in: question)
        guard let phrase = periodPhrase(span) else { return text }
        guard let line = readings.filter({ $0.name == "health" }).flatMap(\.lines).first(where: {
            $0.localizedStandardContains(phrase)
        }) else { return text }
        let folded = AskAppleCopy.folded(text)
        if folded.localizedStandardContains(span), !folded.localizedStandardContains("not available") {
            return text
        }
        let spoken = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return spoken.hasSuffix(".") ? spoken : spoken + "."
    }
}

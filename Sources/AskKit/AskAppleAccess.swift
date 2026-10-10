import AppIntents
import Contacts
import CoreLocation
import EventKit
import Foundation
import FoundationModels
import HealthKit
import MapKit
import os
import SwiftUI

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

/// One Apple source the composer can list.
struct AskAppleSource: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var access: AskAppleAccess
    var title: String
    var symbol: String
    var detail: String

    static let catalog: [AskAppleSource] = [
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
    For contacts that begin with letters, call the contacts tool with action look, those letters, and beginsWith true.
    For a reminder list, say how many are open in one short sentence. Do not list the titles. The card lists them.
    A calendar question calls the calendar tool only. A contact question calls the contacts tool only. \
    Pass nearby to the location tool for places around the person. \
    For a week, pass span week to the health tool. For a month, pass span month. For a year, pass span year. \
    For workouts pass kind workouts. For sleep pass kind sleep. \
    When the person asks for an email, say the email the contacts tool returned.
    For the forecast, pass span hourly or span daily to the weather tool, the day number, and the city when one is named. 0 is today. \
    Leave the city empty for where the person is. Say it in one or two short sentences. The card lists each day or each hour.
    A song, album, or playlist uses the music tool. Pass song, album, or playlist and the title. Pass play and the title to start playback. Pass now for what is playing. \
    Pass recent for the last song played. Pass pause to pause, next to skip, and previous to go back. Say the title and the artist. Do not say a song is playing unless its line starts with Song.
    To read alarms, call the alarms tool with action read and do not add one. Say how many are on. \
    To change an alarm, call action update with its current time and the new time or repeats. Recurring is daily, weekdays, weekends, or a weekday name. \
    To remove an alarm, call action delete with its time. \
    To set alarms, call the alarms tool once and pass every alarm this question asked for. Each one needs a title and a time. \
    Pass a label, an SF Symbol, and an action id from that tool's list when the person wants a custom button. \
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
    private static let dayWords: Set<String> = [
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

    static func request(in question: String) -> Request? {
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
}

/// One contact line: name, phone, and email. A fuzzy Contacts hit that does not match the name is dropped.
enum AskContactLine {
    struct Person: Equatable {
        var name: String
        var phone: String
        var email: String

        var isPerson: Bool {
            let folded = AskAppleCopy.folded(name).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folded.isEmpty else { return false }
            let status = [
                "no matching contacts.", "no matching contacts", "no contacts.", "no contacts",
                "not allowed.", "not allowed", "contact"
            ]
            return !status.contains(folded)
        }

        var shareLine: String { AskContactLine.line(name: name, phone: phone, email: email) }
    }

    static func line(name: String, phone: String, email: String) -> String {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [who.isEmpty ? "Contact" : who]
        let number = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !number.isEmpty { parts.append(number) }
        if !address.isEmpty { parts.append(address) }
        return parts.joined(separator: " · ")
    }

    static func person(from line: String) -> Person {
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
        newName: String? = nil
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
        guard verb == "add" || verb == "create" || verb == "new" else {
            return .lookup(name: who, prefix: beginsWith == true)
        }
        guard !who.isEmpty else { return .needsName }
        return .add(name: who, phone: clip(phone), email: clip(email))
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

enum AskAppleCards {
    static let names: Set<String> = ["calendar", "reminders", "contacts", "location", "health", "music", "weather", "alarms", "web", "photos"]

    /// The first Apple source that ran. Later calls to that same source stay on the card, in order.
    static func first(_ readings: [AskAppleReading]) -> AskAppleReading? {
        sources(readings).first
    }

    /// One card per Apple source, in the order they ran. Later calls to the same source stay on that card.
    /// Contacts, songs, albums, forecast days, and alarms are the exception: each one is its own card.
    /// Hours stay on that day's card.
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
            if name == "weather" {
                let days = kept.filter { AskWeatherLine.day(from: $0) != nil }
                let hours = kept.contains { AskWeatherLine.hour(from: $0) != nil }
                if days.count > 1, !hours {
                    return days.map { AskAppleReading(name: name, lines: [$0]) }
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
        custom: ((String, [String]) -> AskIntentCard?)?
    ) -> AskIntentCard {
        guard let reading else { return card }
        let lines = AskLocationPin.labels(in: reading.lines)
        guard !lines.isEmpty else { return card }
        let fact = make(reading, spoken: card.spoken, showsCoordinates: showsCoordinates, custom: custom)
        var combined = card
        let skillView = card.view
        let factView = fact.view
        combined.view = AnyView(
            VStack(alignment: .leading, spacing: 8) {
                skillView
                factView
            }
        )
        let extra = lines.joined(separator: "\n")
        if !combined.shareText.localizedCaseInsensitiveContains(extra) {
            combined.shareText = combined.shareText.isEmpty ? extra : combined.shareText + "\n" + extra
        }
        return combined
    }

    /// The host card wins when it returns one. Nil keeps the built-in fact card.
    @MainActor
    static func make(
        _ reading: AskAppleReading,
        spoken: String,
        showsCoordinates: Bool = false,
        custom: ((String, [String]) -> AskIntentCard?)?
    ) -> AskIntentCard {
        let visible = AskLocationPin.labels(in: reading.lines)
        if let card = custom?(reading.name, visible) {
            return card
        }
        let title = title(for: reading.name)
        let reminders = AskReminderItem.tasks(in: reading.lines)
        if reading.name == "reminders", !reminders.isEmpty {
            var card = AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                view: AskReminderCard(title: title, items: reminders)
            )
            card.shareText = reminders.map(\.shareLine).joined(separator: "\n")
            return card
        }
        let places = AskLocationPin.places(in: reading.lines)
        if reading.name == "location", !places.isEmpty {
            return AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                view: AskLocationMapCard(title: title, places: places, showsCoordinates: showsCoordinates)
            )
        }
        if reading.name == "contacts", let line = visible.first {
            let person = AskContactLine.person(from: line)
            if person.isPerson {
                var card = AskIntentCard(
                    title: person.name,
                    spoken: spoken,
                    text: spoken,
                    view: AskContactCard(person: person)
                )
                card.shareText = person.shareLine
                return card
            }
        }
        if reading.name == "health", let chart = AskHealthChartModel.parse(visible) {
            return AskIntentCard(
                title: title,
                spoken: spoken,
                text: spoken,
                view: AskHealthChartCard(metric: chart.metric, initial: chart.range, lines: visible)
            )
        }
        if reading.name == "music", let item = AskMusicLine.item(from: visible.first ?? "") {
            var card = AskIntentCard(
                title: item.title,
                spoken: spoken,
                text: spoken,
                view: AskMusicCard(item: item)
            )
            card.shareText = item.shareText
            return card
        }
        if reading.name == "alarms",
           let line = visible.first(where: { AskAlarmLine.item(from: $0) != nil }),
           let item = AskAlarmLine.item(from: line) {
            var card = AskIntentCard(
                title: item.title,
                spoken: spoken,
                text: spoken,
                view: AskAlarmCard(item: item)
            )
            card.shareText = [item.title, item.time, item.repeats, item.label, item.symbol]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return card
        }
        if reading.name == "weather", let forecast = AskWeatherLine.forecast(from: visible) {
            var card = AskIntentCard(
                title: forecast.day.title,
                spoken: spoken,
                text: spoken,
                view: AskWeatherCard(forecast: forecast)
            )
            card.shareText = forecast.shareText
            return card
        }
        let value = visible.first ?? "Nothing to show."
        let detail = visible.dropFirst().joined(separator: "\n")
        var card = AskIntentCard(
            title: title,
            spoken: spoken,
            text: spoken,
            view: AskAppleFactCard(title: title, value: value, detail: detail)
        )
        card.shareText = [value, detail].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return card
    }
}

/// Title, value, and detail. Same shape as the sample fact cards.
struct AskAppleFactCard: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AskCardBadge(
                    title: title,
                    symbol: AskCardSymbol.symbol(for: title),
                    tint: AskCardSymbol.tint(for: title)
                )
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .askCardSurface(tint: AskCardSymbol.tint(for: title))
    }
}

/// One person. Phone and email both stay on the card.
struct AskContactCard: View {
    var person: AskContactLine.Person

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(initials)
                .font(.headline)
                .foregroundStyle(monogram)
                .frame(width: 56, height: 56)
                .background(monogram.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(person.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AskCardBadge(title: "Contact", symbol: "person.fill", tint: monogram)
                }
                if !person.phone.isEmpty {
                    contactAction(
                        title: person.phone,
                        symbol: "phone.fill",
                        intent: AskCallTap(phone: person.phone),
                        accessibilityLabel: "Call \(person.name)",
                        secondary: false
                    )
                }
                if !person.email.isEmpty {
                    contactAction(
                        title: person.email,
                        symbol: "envelope.fill",
                        intent: AskEmailTap(email: person.email),
                        accessibilityLabel: "Email \(person.name)",
                        secondary: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .askCardSurface(tint: monogram)
    }

    private func contactAction<I: AppIntent>(
        title: String,
        symbol: String,
        intent: I,
        accessibilityLabel: Text,
        secondary: Bool
    ) -> some View {
        Button(intent: intent) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(secondary ? Color.secondary : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var initials: String {
        let letters = person.name.split(separator: " ").prefix(2).compactMap(\.first)
        let text = String(letters).uppercased()
        return text.isEmpty ? "?" : text
    }

    /// Stable across launches. `hashValue` is not.
    private var monogram: Color {
        let palette: [Color] = [.blue, .teal, .indigo, .purple, .orange, .pink]
        let sum = person.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// A place the location tool found. The map coordinate stays off the spoken line unless the person asked.
enum AskLocationPin {
    /// Splits a stored line into the address and the map coordinate.
    static let marker = "\u{1E}"

    struct Place: Identifiable, Equatable {
        var label: String
        var latitude: Double
        var longitude: Double

        var id: String { "\(latitude),\(longitude),\(label)" }
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        var shortName: String {
            label.split(separator: ",", maxSplits: 1).first.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? label
        }

        /// The rest of the label after the place name. Empty when the label is only a name.
        var address: String {
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

    static func line(label: String, latitude: Double, longitude: Double) -> String {
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

    static func places(in lines: [String]) -> [Place] {
        lines.compactMap { parse($0).place }
    }

    static func labels(in lines: [String]) -> [String] {
        lines.map { AskReminderItem.plain(parse($0).label) }.filter { !$0.isEmpty }
    }

    static func format(_ place: Place) -> String {
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
enum AskLocationRegion {
    static func region(for places: [AskLocationPin.Place]) -> MKCoordinateRegion {
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

/// The location card. The map is the answer. Coordinates stay hidden until the question asked for them.
struct AskLocationMapCard: View {
    var title: String
    var places: [AskLocationPin.Place]
    var showsCoordinates: Bool

    @Environment(\.askSnippet) private var snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AskCardBadge(title: "Place", symbol: "mappin.and.ellipse", tint: .green)
            }
            map
            ForEach(places) { place in
                AskLocationPlaceRow(
                    place: place,
                    showsCoordinates: showsCoordinates,
                    inlineDirections: places.count > 1
                )
            }
        }
        .askCardSurface(tint: .green)
    }

    @ViewBuilder
    private var map: some View {
        let label = places.map(\.shortName).joined(separator: ", ")
        if snippet.isSnippet {
            // A MapKit snapshot here never returns to Siri, so the dialog disappears with it.
            AskSnippetMapPicture(label: label)
        } else {
            Map(initialPosition: .region(AskLocationRegion.region(for: places))) {
                ForEach(places) { place in
                    Marker(place.shortName, coordinate: place.coordinate)
                }
            }
            .mapStyle(.standard)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel(label)
        }
    }
}

/// Place row for the shortcut. MapKit's snapshot call does not return while Siri is waiting, so this stays a symbol and the name.
struct AskSnippetMapPicture: View {
    var label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One place under the map, with its own directions button. Several places keep the button beside the name.
struct AskLocationPlaceRow: View {
    var place: AskLocationPin.Place
    var showsCoordinates: Bool
    var inlineDirections: Bool

    var body: some View {
        if inlineDirections {
            HStack(alignment: .center, spacing: 12) {
                AskLocationPlaceText(place: place, showsCoordinates: showsCoordinates, splitsAddress: true)
                directions(title: "Directions", expands: false, showsTitle: false)
                    .layoutPriority(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                AskLocationPlaceText(place: place, showsCoordinates: showsCoordinates, splitsAddress: false)
                directions(title: "Get Directions", expands: true, showsTitle: true)
            }
        }
    }

    private func directions(title: LocalizedStringKey, expands: Bool, showsTitle: Bool) -> some View {
        AskCardCTA(
            title: title,
            symbol: "arrow.triangle.turn.up.right.diamond.fill",
            tint: .green,
            intent: AskDirectionsTap(
                place: place.shortName,
                latitude: place.latitude,
                longitude: place.longitude
            ),
            accessibilityLabel: Text("Get directions to \(place.shortName)"),
            expands: expands,
            showsTitle: showsTitle
        )
    }
}

/// Place name, and the address under it when a card lists more than one place.
private struct AskLocationPlaceText: View {
    var place: AskLocationPin.Place
    var showsCoordinates: Bool
    var splitsAddress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(splitsAddress ? place.shortName : place.label)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if splitsAddress, !place.address.isEmpty {
                Text(place.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsCoordinates {
                Text(AskLocationPin.format(place))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One reminder on the card. The EventKit identifier stays off the line the model reads.
enum AskReminderItem {
    static let marker = "\u{1F}"

    struct Item: Identifiable, Equatable {
        var id: String
        var title: String
        var due: String

        var isTask: Bool { !id.isEmpty }
        var shareLine: String { due.isEmpty ? title : "\(title) · \(due)" }
    }

    static func line(title: String, due: String, id: String) -> String {
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

    static func tasks(in lines: [String]) -> [Item] {
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

/// Each reminder. A circle completes it. The filled check opens it again.
struct AskReminderCard: View {
    var title: String
    var items: [AskReminderItem.Item]
    /// Sample cards skip Reminders. A live card reads which rows are already complete.
    var readsCompletion: Bool = true

    var body: some View {
        let _ = AskReminderChecks.shared.completed
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AskCardBadge(title: "Reminders", symbol: "checklist", tint: .orange)
            }
            ForEach(items) { item in
                AskReminderRow(item: item)
            }
        }
        .askCardSurface(tint: .orange)
        .task(id: items.map(\.id)) {
            guard readsCompletion else { return }
            let found = await AskRemindersRead.completedIDs(items.map(\.id))
            guard !found.isEmpty else { return }
            AskReminderChecks.shared.adopt(found)
        }
    }
}

private struct AskReminderRow: View {
    var item: AskReminderItem.Item

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.askSnippet) private var snippet

    private var done: Bool {
        if snippet.isSnippet {
            return snippet.completedReminders.contains(item.id)
        }
        return AskReminderChecks.shared.completed.contains(item.id)
    }

    private var reminder: AskReminderEntity {
        AskReminderEntity(id: item.id, title: item.title)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(done ? .secondary : .primary)
                    .overlay { AskStrike(shown: done) }
                    .accessibilityLabel(done ? "\(item.title), completed" : item.title)
                if !item.due.isEmpty {
                    Text(item.due)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if done {
                Button(intent: AskReminderReopenTap(reminder: reminder)) {
                    reminderMark(systemName: "checkmark.circle.fill", tint: AnyShapeStyle(.green))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(item.title) incomplete")
            } else {
                Button(intent: AskReminderCompleteTap(reminder: reminder)) {
                    reminderMark(systemName: "circle", tint: AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(item.title)")
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: done)
    }

    private func reminderMark(systemName: String, tint: AnyShapeStyle) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(tint)
            .symbolEffect(.bounce, value: done)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

/// Draws across the title from the leading edge. Layout stays put, so the row does not shift.
private struct AskStrike: View {
    var shown: Bool

    var body: some View {
        Rectangle()
            .frame(maxWidth: .infinity)
            .frame(height: 1.5)
            .scaleEffect(x: shown ? 1 : 0.001, anchor: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    static func make(_ access: AskAppleAccess, question: String = "") -> [any Tool] {
        let ledger = AskToolLedger()
        var tools: [any Tool] = []
        if access.contains(.calendar) { tools.append(AskCalendarTool(toolLedger: ledger)) }
        if access.contains(.reminders) { tools.append(AskRemindersTool(toolLedger: ledger)) }
        if access.contains(.contacts) { tools.append(AskContactsTool(toolLedger: ledger)) }
        if access.contains(.location) { tools.append(AskLocationTool(toolLedger: ledger)) }
        if access.contains(.health) { tools.append(AskHealthTool(toolLedger: ledger)) }
        if access.contains(.music) { tools.append(AskMusicTool(toolLedger: ledger)) }
        if access.contains(.weather) { tools.append(AskWeatherTool(toolLedger: ledger)) }
        if access.contains(.alarms) { tools.append(AskAlarmTool(toolLedger: ledger, question: question)) }
        return tools
    }

    static func readings(in tools: [any Tool]) -> [AskAppleReading] {
        for tool in tools {
            if let source = tool as? AskToolReadingSource {
                return source.toolLedger.snapshot()
            }
        }
        return []
    }
}

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
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "day \(day)") {
                await AskCalendarRead.lines(day: day)
            }
        case .birthdays(let day):
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "birthdays \(day)") {
                await AskCalendarRead.birthdays(from: day)
            }
        case .add(let title, let day, let hour, let minute, let place, let notes):
            let clock = hour.map { "\($0):\(minute)" } ?? "all day"
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "add \(day) \(title) \(clock)") {
                await AskCalendarRead.add(title: title, day: day, hour: hour, minute: minute, place: place, notes: notes)
            }
        case .update(let title, let day, let hour, let minute, let place, let notes, let newTitle):
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "update \(day) \(title)") {
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
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "delete \(day) \(title)") {
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

private struct AskContactsTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "contacts"
    let description = "Look up a contact by name, or add, change, or remove one contact. For a lookup, pass action look and the name. For contacts that begin with letters, pass those letters and set beginsWith to true. Leave the name empty only for a short list. Each line is one person, with the phone and the email when they exist. To add a contact, pass action add, the name, and the phone or email when they were said. To change one, pass action update, the current name, and only the fields that change. newName renames it. To remove one, pass action delete and the name. An added contact starts with Added. A changed contact starts with Updated. A removed contact starts with Removed. If the result is Not allowed, say you cannot see contacts. Do not invent a phone number or email. When the person asks for an email, say the email on the line. Do not say a contact was added, changed, or removed unless the line says so."

    @Generable
    struct Arguments {
        @Guide(description: "look, add, update, or delete. Use look unless the person asked to create, change, or remove a contact.", .anyOf(["look", "add", "update", "delete"]))
        var action: String?
        @Guide(description: "The person's name, or the letters a name begins with. The current name when updating or deleting. Leave empty only when the question asks for a short list.")
        var name: String
        @Guide(description: "True when the person asked for names that begin with the letters in name. Otherwise false.")
        var beginsWith: Bool?
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
            newName: arguments.newName
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

private struct AskMusicTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = "music"
    let description = "Read what is playing, the last song played, or search songs, albums, or playlists. Play, pause, skip, or go back when the person asks. Pass which now for what is playing. Pass which recent for the last song played. Pass which song, album, or playlist and the title to search. Pass which play and the title to start playback. Pass which pause to pause, which next to skip, and which previous to go back. Each line is one song, album, or playlist. A line that starts with Recent is the last song played, not the song playing now. Say the title and the artist. The card shows the rest. If the result is Not allowed, say you cannot see the music. Do not invent a song, album, or playlist. Do not say the song changed unless the tool says so."

    @Generable
    struct Arguments {
        @Guide(description: "now, recent, song, album, playlist, play, pause, next, or previous. Use now for what is playing. Use recent for the last song played. Use play to start a song or album. Use pause to pause, next to skip, and previous to go back.", .anyOf(["now", "recent", "song", "album", "playlist", "play", "pause", "next", "previous"]))
        var which: String
        @Guide(description: "The song, album, or playlist title, or the artist. Leave empty when which is now.")
        var query: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let request = AskMusicQuery.request(which: arguments.which, query: arguments.query)
        let label = request.term.isEmpty ? "\(request.kind)" : "\(request.kind) \(request.term)"
        return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: label) {
            await AskMusicRead.lines(request)
        }
    }
}

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
            let head = line.split(separator: "·").first.map(String.init) ?? line
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
        var rereadContact = false
        if toolNames.contains("contacts"), let request = AskContactQuery.request(in: question) {
            let lines = readings.filter { $0.name == "contacts" }.flatMap(\.lines)
            if !lines.contains(where: AskAppleCopy.keepsWrite) {
                contactQuery = request.name
                contactPrefix = request.prefix
                let matched = AskContactLine.filtered(lines, query: request.name, prefix: request.prefix)
                let hasEmail = matched.contains { AskContactLine.person(from: $0).email.contains("@") }
                rereadContact = matched.isEmpty || (AskContactQuery.asksEmail(question) && !hasEmail)
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
            rereadContact: rereadContact,
            music: music,
            weather: weather,
            readReminders: readReminders,
            alarmList: alarmList,
            alarmChange: alarmChange,
            alarmRemoval: alarmRemoval,
            alarmDrafts: alarmDrafts
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
        if let query = plan.contactQuery {
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

    private static func lines(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private enum AskCalendarRead {
    static func add(title: String, day: Int, hour: Int?, minute: Int, place: String, notes: String) async -> String {
        let store = EKEventStore()
        guard await allowEvents(store, writing: true) else { return AskAppleCopy.denied }
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) else {
            return "Could not add the event."
        }
        guard let target = store.defaultCalendarForNewEvents
            ?? store.calendars(for: .event).first(where: \.allowsContentModifications) else {
            return "No calendar to add to."
        }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = AskAppleCopy.plain(title, limit: 200)
        event.timeZone = calendar.timeZone
        let whereTo = AskAppleCopy.plain(place, limit: 200)
        if !whereTo.isEmpty { event.location = whereTo }
        let about = AskAppleCopy.plain(notes, limit: 500)
        if !about.isEmpty { event.notes = about }
        if let hour {
            guard applyTime(hour: hour, minute: minute, on: window.start, to: event, calendar: calendar) else {
                return "Could not add the event."
            }
        } else {
            event.isAllDay = true
            event.startDate = window.start
            event.endDate = window.end
        }
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            return "Could not add the event."
        }
        let saved = line(event, dayTitle: window.title, dayStart: window.start, calendar: calendar)
        return AskAppleCopy.addedPrefix + saved
    }

    /// Changes one event on that day. Write-only access can add, but it cannot find an event to change.
    static func update(
        title: String,
        day: Int,
        hour: Int?,
        minute: Int?,
        place: String?,
        notes: String?,
        newTitle: String?
    ) async -> String {
        let store = EKEventStore()
        guard await allowEvents(store, writing: false) else { return AskAppleCopy.denied }
        guard let found = events(store, day: day) else { return "Could not change the event." }
        switch match(found.events, title: title) {
        case .none:
            return "No matching event."
        case .many:
            return "More than one event is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let event):
            if let newTitle {
                let renamed = AskAppleCopy.plain(newTitle, limit: 200)
                if !renamed.isEmpty { event.title = renamed }
            }
            if let hour {
                guard applyTime(hour: hour, minute: minute ?? 0, on: found.window.start, to: event, calendar: found.calendar) else {
                    return "Could not change the event."
                }
            }
            if let place {
                event.location = AskAppleCopy.plain(place, limit: 200)
            }
            if let notes {
                event.notes = AskAppleCopy.plain(notes, limit: 500)
            }
            do {
                try store.save(event, span: .thisEvent)
            } catch {
                return "Could not change the event."
            }
            let saved = line(event, dayTitle: found.window.title, dayStart: found.window.start, calendar: found.calendar)
            return AskAppleCopy.updatedPrefix + saved
        }
    }

    /// Removes one event on that day. Several matches, or none, leave the calendar unchanged.
    static func remove(title: String, day: Int) async -> String {
        let store = EKEventStore()
        guard await allowEvents(store, writing: false) else { return AskAppleCopy.denied }
        guard let found = events(store, day: day) else { return "Could not remove the event." }
        switch match(found.events, title: title) {
        case .none:
            return "No matching event."
        case .many:
            return "More than one event is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let event):
            let saved = line(event, dayTitle: found.window.title, dayStart: found.window.start, calendar: found.calendar)
            do {
                try store.remove(event, span: .thisEvent)
            } catch {
                return "Could not remove the event."
            }
            return AskAppleCopy.removedPrefix + saved
        }
    }

    static func lines(day: Int) async -> String {
        let store = EKEventStore()
        let granted = await allowEvents(store, writing: false)
        guard granted else { return AskAppleCopy.denied }
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) else {
            return "Nothing scheduled."
        }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.startDate < window.end }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
        guard !events.isEmpty else { return "\(window.title) · Nothing scheduled." }
        return events.map { line($0, dayTitle: window.title, dayStart: window.start, calendar: calendar) }.joined(separator: "\n")
    }

    /// Birthday calendar events from the start day through the next two weeks.
    static func birthdays(from day: Int) async -> String {
        let store = EKEventStore()
        let granted = await allowEvents(store, writing: false)
        guard granted else { return AskAppleCopy.denied }
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar),
              let end = calendar.date(byAdding: .day, value: 14, to: window.start) else {
            return "No birthdays."
        }
        let birthdayCalendars = store.calendars(for: .event).filter { $0.type == .birthday }
        let calendars = birthdayCalendars.isEmpty ? nil : birthdayCalendars
        let predicate = store.predicateForEvents(withStart: window.start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
            .filter { calendars != nil || $0.calendar.type == .birthday }
            .filter { $0.startDate < end }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
        guard !events.isEmpty else { return "No birthdays." }
        return events.map { event in
            let dayStart = calendar.startOfDay(for: event.startDate)
            let dayTitle = AskCalendarWindow.heading(for: dayStart, calendar: calendar)
            let name = AskAppleCopy.plain(event.title ?? "Birthday", limit: 120)
            return "\(dayTitle) · \(name)"
        }.joined(separator: "\n")
    }

    private static func events(_ store: EKEventStore, day: Int) -> (window: AskCalendarWindow, events: [EKEvent], calendar: Calendar)? {
        let calendar = Calendar.current
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) else { return nil }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.startDate < window.end }
            .sorted { $0.startDate < $1.startDate }
        return (window, events, calendar)
    }

    private enum Match {
        case one(EKEvent)
        case none
        case many
    }

    /// One exact title wins. One title that contains the words is next. Several matches change nothing.
    private static func match(_ events: [EKEvent], title: String) -> Match {
        let wanted = folded(title)
        guard !wanted.isEmpty else { return .none }
        let exact = events.filter { folded($0.title ?? "") == wanted }
        if exact.count == 1, let event = exact.first { return .one(event) }
        if exact.count > 1 { return .many }
        let contains = events.filter { folded($0.title ?? "").localizedStandardContains(wanted) }
        if contains.count == 1, let event = contains.first { return .one(event) }
        return contains.isEmpty ? .none : .many
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A timed event lasts one hour. An all-day event becomes timed when an hour is set.
    private static func applyTime(hour: Int, minute: Int, on day: Date, to event: EKEvent, calendar: Calendar) -> Bool {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        guard let start = calendar.date(from: parts),
              let end = calendar.date(byAdding: .hour, value: 1, to: start) else {
            return false
        }
        event.isAllDay = false
        event.timeZone = calendar.timeZone
        event.startDate = start
        event.endDate = end
        return true
    }

    private static func allowEvents(_ store: EKEventStore, writing: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .writeOnly:
            return writing
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func line(_ event: EKEvent, dayTitle: String, dayStart: Date, calendar: Calendar) -> String {
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title?.isEmpty == false) ? title! : "Event"
        let when: String
        if event.isAllDay {
            when = calendar.isDate(event.startDate, inSameDayAs: dayStart)
                ? "all day"
                : event.startDate.formatted(date: .abbreviated, time: .omitted)
        } else if calendar.isDate(event.startDate, inSameDayAs: dayStart) {
            when = event.startDate.formatted(date: .omitted, time: .shortened)
        } else {
            when = event.startDate.formatted(date: .abbreviated, time: .shortened)
        }
        var parts = [dayTitle, name, when]
        let place = AskAppleCopy.plain(event.location ?? "", limit: 80)
        if !place.isEmpty { parts.append(place) }
        let notes = AskAppleCopy.plain(event.notes ?? "", limit: 80)
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }
}

enum AskRemindersRead {
    static func add(
        title: String,
        day: Int?,
        hour: Int?,
        minute: Int,
        notes: String,
        priority: String
    ) async -> String {
        let store = EKEventStore()
        guard await allowReminders(store, writing: true) else { return AskAppleCopy.denied }
        guard let target = store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first(where: \.allowsContentModifications) else {
            return "No list to add to."
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = target
        reminder.title = AskAppleCopy.plain(title, limit: 200)
        let about = AskAppleCopy.plain(notes, limit: 500)
        if !about.isEmpty { reminder.notes = about }
        if let rank = priorityValue(priority) { reminder.priority = rank }
        let calendar = Calendar.current
        if let day, let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) {
            var parts = calendar.dateComponents([.year, .month, .day], from: window.start)
            if let hour {
                parts.hour = hour
                parts.minute = minute
            }
            reminder.dueDateComponents = parts
        }
        do {
            try store.save(reminder, commit: true)
        } catch {
            return "Could not add the reminder."
        }
        return AskReminderItem.line(
            title: AskAppleCopy.addedPrefix + AskAppleCopy.plain(title, limit: 200),
            due: dueText(reminder),
            id: reminder.calendarItemIdentifier
        )
    }

    /// Changes one incomplete reminder. Write-only access can add, but it cannot find one to change.
    static func update(
        title: String,
        day: Int?,
        hour: Int?,
        minute: Int?,
        notes: String?,
        priority: String?,
        newTitle: String?
    ) async -> String {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return AskAppleCopy.denied }
        let found = await match(store, title: title, day: day)
        switch found {
        case .none:
            return "No matching reminder."
        case .many:
            return "More than one reminder is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let reminder):
            if let newTitle {
                let renamed = AskAppleCopy.plain(newTitle, limit: 200)
                if !renamed.isEmpty { reminder.title = renamed }
            }
            if hour != nil || day != nil {
                applyDue(day: day, hour: hour, minute: minute, to: reminder)
            }
            if let notes {
                reminder.notes = AskAppleCopy.plain(notes, limit: 500)
            }
            if let priority, let rank = priorityValue(priority) {
                reminder.priority = rank
            }
            do {
                try store.save(reminder, commit: true)
            } catch {
                return "Could not change the reminder."
            }
            let name = AskAppleCopy.plain(reminder.title ?? title, limit: 200)
            return "\(AskAppleCopy.updatedPrefix)\(name)."
        }
    }

    /// Removes one incomplete reminder. Several matches, or none, leave the list unchanged.
    static func remove(title: String) async -> String {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return AskAppleCopy.denied }
        switch await match(store, title: title, day: nil) {
        case .none:
            return "No matching reminder."
        case .many:
            return "More than one reminder is named \(AskAppleCopy.plain(title, limit: 80))."
        case .one(let reminder):
            let name = AskAppleCopy.plain(reminder.title ?? title, limit: 200)
            do {
                try store.remove(reminder, commit: true)
            } catch {
                return "Could not remove the reminder."
            }
            return "\(AskAppleCopy.removedPrefix)\(name)."
        }
    }

    static func complete(id: String) async throws {
        let store = EKEventStore()
        guard await allowReminders(store, writing: true) else { throw AskReminderIntentError.denied }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw AskReminderIntentError.missing
        }
        if reminder.isCompleted { return }
        reminder.isCompleted = true
        reminder.completionDate = Date()
        try store.save(reminder, commit: true)
    }

    static func reopen(id: String) async throws {
        let store = EKEventStore()
        guard await allowReminders(store, writing: true) else { throw AskReminderIntentError.denied }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw AskReminderIntentError.missing
        }
        if !reminder.isCompleted { return }
        reminder.isCompleted = false
        reminder.completionDate = nil
        try store.save(reminder, commit: true)
    }

    /// Identifiers already completed in Reminders. The card shows a filled check for these.
    static func completedIDs(_ ids: [String]) async -> Set<String> {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        var done: Set<String> = []
        for id in ids {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.isCompleted else { continue }
            done.insert(id)
        }
        return done
    }

    static func entities(ids: [String]) async -> [AskReminderEntity] {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        return ids.compactMap { id in
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return nil }
            return entity(reminder)
        }
    }

    static func completed(matching name: String?, limit: Int) async -> [AskReminderEntity] {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        let predicate = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: nil)
        let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let matched = (reminders ?? []).filter { reminder in
                    guard !wanted.isEmpty else { return true }
                    return (reminder.title ?? "").localizedStandardContains(wanted)
                }
                let entities = matched.prefix(limit).map(Self.entity)
                continuation.resume(returning: Array(entities))
            }
        }
    }

    private static func entity(_ reminder: EKReminder) -> AskReminderEntity {
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title?.isEmpty == false) ? title! : "Reminder"
        return AskReminderEntity(id: reminder.calendarItemIdentifier, title: name)
    }

    static func incomplete(matching name: String?, limit: Int) async -> [AskReminderEntity] {
        let store = EKEventStore()
        guard await allowReminders(store, writing: false) else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let wanted = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let matched = (reminders ?? []).filter { reminder in
                    guard !wanted.isEmpty else { return true }
                    return (reminder.title ?? "").localizedStandardContains(wanted)
                }
                let entities = matched.prefix(limit).map(Self.entity)
                continuation.resume(returning: Array(entities))
            }
        }
    }

    static func lines(limit: Int) async -> String {
        let store = EKEventStore()
        let granted = await allowReminders(store, writing: false)
        guard granted else { return AskAppleCopy.denied }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let cap = min(max(limit, 1), 8)
        let calendar = Calendar.current
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let soonest = (reminders ?? []).sorted { lhs, rhs in
                    switch (Self.dueDate(lhs, calendar: calendar), Self.dueDate(rhs, calendar: calendar)) {
                    case let (left?, right?):
                        return left < right
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return false
                    }
                }
                let lines = soonest.prefix(cap).map(Self.line)
                let text = lines.isEmpty ? "No reminders." : lines.joined(separator: "\n")
                continuation.resume(returning: text)
            }
        }
    }

    private static func dueDate(_ reminder: EKReminder, calendar: Calendar) -> Date? {
        guard let parts = reminder.dueDateComponents else { return nil }
        return calendar.date(from: parts)
    }

    private enum Match {
        case one(EKReminder)
        case none
        case many
    }

    /// One exact title wins. One title that contains the words is next. A day limits the search to that due date.
    private static func match(_ store: EKEventStore, title: String, day: Int?) async -> Match {
        switch await choose(store, title: title, day: day) {
        case .none:
            return .none
        case .many:
            return .many
        case .one(let id):
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return .none }
            return .one(reminder)
        }
    }

    /// The fetch callback stays on EventKit's queue. Only the identifier crosses back.
    private static func choose(_ store: EKEventStore, title: String, day: Int?) async -> Choice {
        let wanted = folded(title)
        guard !wanted.isEmpty else { return .none }
        let calendar = Calendar.current
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let scoped = (reminders ?? []).filter { onDay($0, day: day, calendar: calendar) }
                let exact = scoped.filter { folded($0.title ?? "") == wanted }
                if exact.count == 1, let reminder = exact.first {
                    continuation.resume(returning: .one(reminder.calendarItemIdentifier))
                    return
                }
                if exact.count > 1 {
                    continuation.resume(returning: .many)
                    return
                }
                let contains = scoped.filter { folded($0.title ?? "").localizedStandardContains(wanted) }
                if contains.count == 1, let reminder = contains.first {
                    continuation.resume(returning: .one(reminder.calendarItemIdentifier))
                    return
                }
                continuation.resume(returning: contains.isEmpty ? .none : .many)
            }
        }
    }

    private enum Choice: Sendable {
        case one(String)
        case none
        case many
    }

    private static func onDay(_ reminder: EKReminder, day: Int?, calendar: Calendar) -> Bool {
        guard let day else { return true }
        guard let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar),
              let parts = reminder.dueDateComponents,
              let due = calendar.date(from: parts) else { return false }
        return calendar.isDate(due, inSameDayAs: window.start)
    }

    private static func applyDue(day: Int?, hour: Int?, minute: Int?, to reminder: EKReminder) {
        let calendar = Calendar.current
        let base: Date
        if let day, let window = AskCalendarWindow.day(offset: day, now: Date(), calendar: calendar) {
            base = window.start
        } else if let existing = reminder.dueDateComponents, let date = calendar.date(from: existing) {
            base = date
        } else {
            base = calendar.startOfDay(for: Date())
        }
        var parts = calendar.dateComponents([.year, .month, .day], from: base)
        if let hour {
            parts.hour = hour
            parts.minute = minute ?? 0
        } else if let existing = reminder.dueDateComponents, existing.hour != nil {
            parts.hour = existing.hour
            parts.minute = existing.minute
        }
        reminder.dueDateComponents = parts
    }

    /// 0 none, 1 high, 5 medium, 9 low. An empty rank stays unset.
    private static func priorityValue(_ rank: String) -> Int? {
        switch rank.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none": 0
        case "high": 1
        case "medium": 5
        case "low": 9
        default: nil
        }
    }

    private static func priorityLabel(_ value: Int) -> String {
        switch value {
        case 1...4: "high"
        case 5: "medium"
        case 6...9: "low"
        default: ""
        }
    }

    /// Due, then priority, then notes. They stay after the first separator so the card title is only the name.
    private static func dueText(_ reminder: EKReminder) -> String {
        var parts: [String] = []
        if let components = reminder.dueDateComponents, let due = Calendar.current.date(from: components) {
            let when = components.hour == nil
                ? due.formatted(date: .abbreviated, time: .omitted)
                : due.formatted(date: .abbreviated, time: .shortened)
            parts.append(when)
        }
        let rank = priorityLabel(reminder.priority)
        if !rank.isEmpty { parts.append(rank) }
        let notes = AskAppleCopy.plain(reminder.notes ?? "", limit: 80)
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func allowReminders(_ store: EKEventStore, writing: Bool) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .writeOnly:
            return writing
        case .notDetermined:
            return (try? await store.requestFullAccessToReminders()) ?? false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func line(_ reminder: EKReminder) -> String {
        let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title?.isEmpty == false) ? title! : "Reminder"
        return AskReminderItem.line(title: name, due: dueText(reminder), id: reminder.calendarItemIdentifier)
    }
}

private enum AskContactsRead {
    static func add(name: String, phone: String, email: String) async -> String {
        let store = CNContactStore()
        guard await allow(store) else { return AskAppleCopy.denied }
        let cleaned = AskAppleCopy.plain(name, limit: 120)
        let parts = cleaned.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard let given = parts.first else { return "A name is needed." }
        let contact = CNMutableContact()
        contact.givenName = given
        if parts.count > 1 {
            contact.familyName = parts.dropFirst().joined(separator: " ")
        }
        let number = AskAppleCopy.plain(phone, limit: 40)
        if !number.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: number))]
        }
        let address = AskAppleCopy.plain(email, limit: 120)
        if !address.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: address as NSString)]
        }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(request)
        } catch {
            return "Could not add the contact."
        }
        let saved = AskContactLine.line(name: cleaned, phone: number, email: address)
        return AskAppleCopy.addedPrefix + saved
    }

    static func update(name: String, phone: String?, email: String?, newName: String?) async -> String {
        let store = CNContactStore()
        guard await allow(store) else { return AskAppleCopy.denied }
        switch await match(store, name: name) {
        case .none:
            return "No matching contacts."
        case .many:
            return "More than one contact is named \(AskAppleCopy.plain(name, limit: 80))."
        case .one(let contact):
            let mutable = contact.mutableCopy() as! CNMutableContact
            if let newName {
                let cleaned = AskAppleCopy.plain(newName, limit: 120)
                let parts = cleaned.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
                if let given = parts.first {
                    mutable.givenName = given
                    mutable.familyName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
                }
            }
            if let phone {
                let number = AskAppleCopy.plain(phone, limit: 40)
                mutable.phoneNumbers = number.isEmpty
                    ? []
                    : [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: number))]
            }
            if let email {
                let address = AskAppleCopy.plain(email, limit: 120)
                mutable.emailAddresses = address.isEmpty
                    ? []
                    : [CNLabeledValue(label: CNLabelHome, value: address as NSString)]
            }
            let request = CNSaveRequest()
            request.update(mutable)
            do {
                try store.execute(request)
            } catch {
                return "Could not change the contact."
            }
            return AskAppleCopy.updatedPrefix + line(mutable)
        }
    }

    static func remove(name: String) async -> String {
        let store = CNContactStore()
        guard await allow(store) else { return AskAppleCopy.denied }
        switch await match(store, name: name) {
        case .none:
            return "No matching contacts."
        case .many:
            return "More than one contact is named \(AskAppleCopy.plain(name, limit: 80))."
        case .one(let contact):
            let saved = line(contact)
            let mutable = contact.mutableCopy() as! CNMutableContact
            let request = CNSaveRequest()
            request.delete(mutable)
            do {
                try store.execute(request)
            } catch {
                return "Could not remove the contact."
            }
            return AskAppleCopy.removedPrefix + saved
        }
    }

    private enum Match {
        case one(CNContact)
        case none
        case many
    }

    private static func match(_ store: CNContactStore, name: String) async -> Match {
        let wanted = AskAppleCopy.folded(name)
        guard !wanted.isEmpty else { return .none }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContacts(matchingName: name)
        var found: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let folded = AskAppleCopy.folded(formatted)
                if folded == wanted || AskContactLine.matches(name: formatted, query: name) {
                    found.append(contact)
                }
                if found.count > 1 { stop.pointee = true }
            }
        } catch {
            return .none
        }
        if found.count == 1, let contact = found.first { return .one(contact) }
        return found.isEmpty ? .none : .many
    }

    static func lines(matching name: String, prefix: Bool = false) async -> String {
        let store = CNContactStore()
        let granted = await allow(store)
        guard granted else { return AskAppleCopy.denied }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        // Short prefixes need a full scan. Contacts' name predicate misses many of them.
        let scanAll = prefix && !name.isEmpty && name.count <= 2
        if !name.isEmpty, !scanAll {
            request.predicate = CNContact.predicateForContacts(matchingName: name)
        }
        let cap = name.isEmpty ? 5 : (scanAll ? 200 : 40)
        var lines: [String] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                lines.append(line(contact))
                if lines.count >= cap { stop.pointee = true }
            }
        } catch {
            return AskAppleCopy.denied
        }
        let matched = name.isEmpty ? lines : AskContactLine.filtered(lines, query: name, prefix: prefix)
        let kept = Array(matched.prefix(name.isEmpty ? 5 : 8))
        guard !kept.isEmpty else { return name.isEmpty ? "No contacts." : "No matching contacts." }
        return kept.joined(separator: "\n")
    }

    private static func allow(_ store: CNContactStore) async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return (try? await store.requestAccess(for: .contacts)) ?? false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func line(_ contact: CNContact) -> String {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (formatted?.isEmpty == false) ? formatted! : "Contact"
        let phone = contact.phoneNumbers.first?.value.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = contact.emailAddresses.first.map {
            String($0.value).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        return AskContactLine.line(name: name, phone: phone, email: email)
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

/// One permission prompt for every health read. Parallel tool calls wait here.
/// `authorizationStatus` is the write status. A read-only app is sharingDenied even when reading is allowed.
private actor AskHealthAuthorization {
    static let shared = AskHealthAuthorization()
    private var requested = false

    func prepare() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if requested { return true }
        var types = Set<HKObjectType>()
        for metric in AskHealthCatalog.Metric.allCases {
            if let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) {
                types.insert(type)
            }
        }
        if let diastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(diastolic)
        }
        if let correlation = HKCorrelationType.correlationType(forIdentifier: .bloodPressure) {
            types.insert(correlation)
        }
        types.insert(HKWorkoutType.workoutType())
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        guard !types.isEmpty else { return false }
        do {
            try await HKHealthStore().requestAuthorization(toShare: [], read: types)
            requested = true
            return true
        } catch {
            return false
        }
    }
}

enum AskHealthCatalog {
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

    enum Metric: CaseIterable, Sendable {
        case steps, heart, energy, distance, flights, exercise
        case weight, height, bodyFat, restingHeart, bloodPressure, glucose, oxygen, temperature, breathing, vo2

        var title: String {
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

        /// Today's total or average. Latest is the newest sample, which is how weight is stored.
        var latestSample: Bool {
            switch self {
            case .steps, .heart, .energy, .distance, .flights, .exercise: false
            case .weight, .height, .bodyFat, .restingHeart, .bloodPressure, .glucose, .oxygen, .temperature, .breathing, .vo2: true
            }
        }

        var averageToday: Bool { self == .heart }

        var percent: Bool { self == .bodyFat || self == .oxygen }

        var measurement: AskHealthMeasurement {
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

        var key: String { measurement.rawValue }
    }

    /// Bars for totals. A line for heart rate and for the newest sample.
    static func chartKind(for metric: Metric) -> AskHealthChartKind {
        if metric.latestSample || metric.averageToday { return .line }
        return .bar
    }

    static func axisLabel(for metric: Metric) -> String {
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

    static func headline(value: String, unit: String, range: AskHealthRange) -> String {
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

enum AskHealthRead {
    static func lines(kind: String, span: String = "today") async -> String {
        guard await AskHealthAuthorization.shared.prepare() else { return AskAppleCopy.denied }
        if AskHealthCatalog.isActivity(kind) {
            return await activity(kind: kind, span: span)
        }
        let metrics = AskHealthCatalog.metrics(matching: kind)
        var lines = Array(repeating: "", count: metrics.count)
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, metric) in metrics.enumerated() {
                group.addTask {
                    (index, await reading(metric, span: span))
                }
            }
            for await (index, line) in group {
                lines[index] = line
            }
        }
        return lines.joined(separator: "\n")
    }

    static func series(metric: AskHealthCatalog.Metric, range: AskHealthRange) async -> AskHealthSeriesSnapshot {
        let axis = AskHealthCatalog.axisLabel(for: metric)
        guard await AskHealthAuthorization.shared.prepare(),
              let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) else {
            return .unavailable(axis)
        }
        let calendar = Calendar.current
        let now = Date()
        guard let window = AskHealthBuckets.window(range: range, now: now, calendar: calendar) else {
            return .empty(axis)
        }
        let sample = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: sample)
        let measure = measure(for: metric)
        do {
            if metric.latestSample {
                return try await samples(metric, measure: measure, axis: axis, predicate: predicate)
            }
            return try await buckets(
                metric,
                measure: measure,
                axis: axis,
                predicate: predicate,
                range: range,
                window: window,
                now: now,
                calendar: calendar
            )
        } catch {
            return refusal(error) ? .unavailable(axis) : .empty(axis)
        }
    }

    /// Workouts and sleep. The header is `Workouts:` or `Sleep:`, which is not a chart measurement.
    private static func activity(kind: String, span: String) async -> String {
        let folded = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if folded == "sleep" {
            return await sleep(span: span)
        }
        return await workouts(span: span)
    }

    private static func activitySpan(_ span: String) -> String {
        span == "month" || span == "year" ? span : "week"
    }

    private static func activityPhrase(_ span: String) -> String {
        switch activitySpan(span) {
        case "month": "this month"
        case "year": "this year"
        default: "this week"
        }
    }

    private static func workouts(span: String) async -> String {
        let phrase = activityPhrase(span)
        let calendar = Calendar.current
        let end = Date()
        let start = AskHealthBuckets.start(span: activitySpan(span), now: end, calendar: calendar)
        let sample = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = HKSamplePredicate.workout(sample)
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 8
        )
        let found: [HKWorkout]
        do {
            found = try await descriptor.result(for: HKHealthStore())
        } catch {
            return refusal(error) ? "Workouts: \(AskAppleCopy.denied)" : "Workouts: Nothing recorded \(phrase)."
        }
        guard !found.isEmpty else { return "Workouts: Nothing recorded \(phrase)." }
        let rows = found.map { workoutLine($0) }
        return (["Workouts: \(found.count) \(phrase)"] + rows).joined(separator: "\n")
    }

    private static func workoutLine(_ workout: HKWorkout) -> String {
        let name = AskAppleCopy.plain(workoutName(workout.workoutActivityType), limit: 40)
        let minutes = max(Int((workout.duration / 60).rounded()), 0)
        let length = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        var parts = [name.isEmpty ? "Workout" : name, length]
        if let distance = workoutDistance(workout) {
            parts.append(distance)
        }
        parts.append(workout.startDate.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    private static func workoutDistance(_ workout: HKWorkout) -> String? {
        let metric = Locale.current.measurementSystem == .metric
        let unit: HKUnit = metric ? .meterUnit(with: .kilo) : .mile()
        let label = metric ? "kilometers" : "miles"
        let identifiers: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  let sum = workout.statistics(for: type)?.sumQuantity() else { continue }
            let value = sum.doubleValue(for: unit)
            guard value > 0.05 else { continue }
            let number = value.formatted(.number.precision(.fractionLength(1)))
            return "\(number) \(label)"
        }
        return nil
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .highIntensityIntervalTraining: "Intervals"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing, .stairs: "Stairs"
        case .pilates: "Pilates"
        case .coreTraining: "Core"
        case .cooldown: "Cooldown"
        case .mixedCardio, .crossTraining: "Cardio"
        case .dance, .cardioDance, .socialDance: "Dance"
        default: "Workout"
        }
    }

    /// Asleep stages for each night. A night with no stage falls back to time in bed.
    private static func sleep(span: String) async -> String {
        let phrase = activityPhrase(span)
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return "Sleep: \(AskAppleCopy.denied)"
        }
        let calendar = Calendar.current
        let end = Date()
        let start = AskHealthBuckets.start(span: activitySpan(span), now: end, calendar: calendar)
        let sample = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = HKSamplePredicate.categorySample(type: type, predicate: sample)
        let descriptor = HKSampleQueryDescriptor<HKCategorySample>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 400
        )
        let samples: [HKCategorySample]
        do {
            samples = try await descriptor.result(for: HKHealthStore())
        } catch {
            return refusal(error) ? "Sleep: \(AskAppleCopy.denied)" : "Sleep: Nothing recorded \(phrase)."
        }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues
        var staged: [Date: TimeInterval] = [:]
        var inBed: [Date: TimeInterval] = [:]
        for sample in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            let night = calendar.startOfDay(for: sample.endDate)
            let length = sample.endDate.timeIntervalSince(sample.startDate)
            guard length > 0 else { continue }
            if asleep.contains(value) {
                staged[night, default: 0] += length
            } else if value == .inBed {
                inBed[night, default: 0] += length
            }
        }
        let nights = Set(staged.keys).union(inBed.keys)
        guard !nights.isEmpty else { return "Sleep: Nothing recorded \(phrase)." }
        let total = nights.reduce(0.0) { sum, night in
            if let hours = staged[night], hours > 0 { return sum + hours }
            return sum + (inBed[night] ?? 0)
        }
        let average = total / Double(nights.count) / 3600
        let hours = average.formatted(.number.precision(.fractionLength(1)))
        return "Sleep: \(hours) hours a night \(phrase)"
    }

    private static func reading(_ metric: AskHealthCatalog.Metric, span: String) async -> String {
        if metric == .bloodPressure {
            do {
                return try await bloodPressure()
            } catch {
                let value = refusal(error) ? AskAppleCopy.denied : "Nothing recorded."
                return "\(metric.title): \(value)"
            }
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) else {
            return "\(metric.title): \(AskAppleCopy.denied)"
        }
        let measure = measure(for: metric)
        let covered = metric.latestSample || AskHealthCatalog.periodPhrase(span) == nil ? "today" : span
        do {
            if metric.latestSample {
                return try await latest(metric, type: type, measure: measure)
            }
            return try await period(metric, type: type, measure: measure, span: covered)
        } catch {
            let value = refusal(error) ? AskAppleCopy.denied : (metric.latestSample ? "Nothing recorded." : AskHealthCatalog.missingValue(span: covered))
            return "\(metric.title): \(value)"
        }
    }

    private static func bloodPressure() async throws -> String {
        guard let type = HKCorrelationType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return "Blood pressure: \(AskAppleCopy.denied)"
        }
        let predicate = HKSamplePredicate.correlation(type: type)
        let descriptor = HKSampleQueryDescriptor<HKCorrelation>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: HKHealthStore()).first else {
            return "Blood pressure: Nothing recorded."
        }
        let unit = HKUnit.millimeterOfMercury()
        let systolic = sample.objects(for: systolicType)
            .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
            .first
        let diastolic = sample.objects(for: diastolicType)
            .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
            .first
        guard let systolic, let diastolic else {
            return "Blood pressure: Nothing recorded."
        }
        let sys = formatted(systolic, fraction: 0, percent: false)
        let dia = formatted(diastolic, fraction: 0, percent: false)
        let when = sample.endDate.formatted(date: .abbreviated, time: .omitted)
        return "Blood pressure: \(sys)/\(dia) mmHg · \(when)"
    }

    /// Today, or a longer range when the question asked for one. The end is now.
    private static func period(
        _ metric: AskHealthCatalog.Metric,
        type: HKQuantityType,
        measure: (unit: HKUnit, label: String, fraction: Int),
        span: String
    ) async throws -> String {
        let calendar = Calendar.current
        let end = Date()
        let start = AskHealthBuckets.start(span: span, now: end, calendar: calendar)
        let sample = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: sample)
        let options: HKStatisticsOptions = metric.averageToday ? .discreteAverage : .cumulativeSum
        let descriptor = HKStatisticsQueryDescriptor(predicate: predicate, options: options)
        let statistics = try await descriptor.result(for: HKHealthStore())
        let quantity = metric.averageToday ? statistics?.averageQuantity() : statistics?.sumQuantity()
        guard let quantity else {
            return "\(metric.title): \(AskHealthCatalog.missingValue(span: span))"
        }
        let number = formatted(quantity.doubleValue(for: measure.unit), fraction: measure.fraction, percent: metric.percent)
        return AskHealthCatalog.summary(title: metric.title, value: "\(number) \(measure.label)", span: span)
    }

    private static func buckets(
        _ metric: AskHealthCatalog.Metric,
        measure: (unit: HKUnit, label: String, fraction: Int),
        axis: String,
        predicate: HKSamplePredicate<HKQuantitySample>,
        range: AskHealthRange,
        window: AskHealthWindow,
        now: Date,
        calendar: Calendar
    ) async throws -> AskHealthSeriesSnapshot {
        let average = metric.averageToday
        let options: HKStatisticsOptions = average ? .discreteAverage : .cumulativeSum
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            options: options,
            anchorDate: window.start,
            intervalComponents: range.interval
        )
        let collection = try await descriptor.result(for: HKHealthStore())
        let found = PointBox()
        let unit = measure.unit
        let percent = metric.percent
        collection.enumerateStatistics(from: window.start, to: window.end) { statistics, _ in
            let quantity = average ? statistics.averageQuantity() : statistics.sumQuantity()
            let recorded = quantity != nil
            let raw = quantity?.doubleValue(for: unit) ?? 0
            found.add(AskHealthPoint(
                id: String(statistics.startDate.timeIntervalSinceReferenceDate),
                date: statistics.startDate,
                value: percent ? raw * 100 : raw,
                recorded: recorded
            ))
        }
        let dates = AskHealthBuckets.dates(range: range, now: now, calendar: calendar)
        let collected = found.all()
        let points = dates.map { date in
            if let match = collected.first(where: { calendar.isDate($0.date, equalTo: date, toGranularity: range.bucket) }) {
                return AskHealthPoint(id: match.id, date: date, value: match.value, recorded: match.recorded)
            }
            return AskHealthPoint(id: "empty-\(date.timeIntervalSinceReferenceDate)", date: date, value: 0, recorded: false)
        }
        let statistics = try await HKStatisticsQueryDescriptor(predicate: predicate, options: options).result(for: HKHealthStore())
        let quantity = average ? statistics?.averageQuantity() : statistics?.sumQuantity()
        let recorded = quantity != nil || points.contains(where: \.recorded)
        guard let quantity else {
            return AskHealthSeriesSnapshot(points: points, headline: "Nothing recorded.", axisLabel: axis, denied: false, recorded: recorded)
        }
        let number = formatted(quantity.doubleValue(for: unit), fraction: measure.fraction, percent: percent)
        let headline = AskHealthCatalog.headline(value: number, unit: measure.label, range: range)
        return AskHealthSeriesSnapshot(points: points, headline: headline, axisLabel: axis, denied: false, recorded: true)
    }

    private static func samples(
        _ metric: AskHealthCatalog.Metric,
        measure: (unit: HKUnit, label: String, fraction: Int),
        axis: String,
        predicate: HKSamplePredicate<HKQuantitySample>
    ) async throws -> AskHealthSeriesSnapshot {
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 60
        )
        let found = try await descriptor.result(for: HKHealthStore())
        let ordered = found.sorted { $0.endDate < $1.endDate }
        guard let newest = ordered.last else { return .empty(axis) }
        let points = ordered.enumerated().map { index, sample in
            let raw = sample.quantity.doubleValue(for: measure.unit)
            return AskHealthPoint(
                id: "\(sample.uuid.uuidString)-\(index)",
                date: sample.endDate,
                value: metric.percent ? raw * 100 : raw,
                recorded: true
            )
        }
        let number = formatted(newest.quantity.doubleValue(for: measure.unit), fraction: measure.fraction, percent: metric.percent)
        let when = newest.endDate.formatted(date: .abbreviated, time: .omitted)
        return AskHealthSeriesSnapshot(
            points: points,
            headline: "\(number) \(measure.label) · \(when)",
            axisLabel: axis,
            denied: false,
            recorded: true
        )
    }

    private static func latest(
        _ metric: AskHealthCatalog.Metric,
        type: HKQuantityType,
        measure: (unit: HKUnit, label: String, fraction: Int)
    ) async throws -> String {
        let predicate = HKSamplePredicate.quantitySample(type: type)
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: HKHealthStore()).first else {
            return "\(metric.title): Nothing recorded."
        }
        let number = formatted(sample.quantity.doubleValue(for: measure.unit), fraction: measure.fraction, percent: metric.percent)
        let when = sample.endDate.formatted(date: .abbreviated, time: .omitted)
        return "\(metric.title): \(number) \(measure.label) · \(when)"
    }

    private static func formatted(_ value: Double, fraction: Int, percent: Bool) -> String {
        let number = percent ? value * 100 : value
        return number.formatted(.number.precision(.fractionLength(fraction)))
    }

    private static func measure(for metric: AskHealthCatalog.Metric) -> (unit: HKUnit, label: String, fraction: Int) {
        let metricSystem = Locale.current.measurementSystem == .metric
        switch metric {
        case .steps, .flights:
            return (.count(), metric == .steps ? "steps" : "flights", 0)
        case .heart, .restingHeart:
            return (HKUnit.count().unitDivided(by: .minute()), "beats per minute", 0)
        case .breathing:
            return (HKUnit.count().unitDivided(by: .minute()), "breaths per minute", 0)
        case .energy:
            return (.kilocalorie(), "kilocalories", 0)
        case .distance:
            return metricSystem
                ? (.meterUnit(with: .kilo), "kilometers", 1)
                : (.mile(), "miles", 1)
        case .exercise:
            return (.minute(), "minutes", 0)
        case .weight:
            return metricSystem
                ? (.gramUnit(with: .kilo), "kilograms", 1)
                : (.pound(), "pounds", 1)
        case .height:
            return metricSystem
                ? (.meterUnit(with: .centi), "centimeters", 0)
                : (.inch(), "inches", 0)
        case .bodyFat, .oxygen:
            return (.percent(), "percent", 0)
        case .bloodPressure:
            return (.millimeterOfMercury(), "mmHg", 0)
        case .glucose:
            return (HKUnit(from: "mg/dL"), "milligrams per deciliter", 0)
        case .temperature:
            return metricSystem
                ? (.degreeCelsius(), "degrees Celsius", 1)
                : (.degreeFahrenheit(), "degrees Fahrenheit", 1)
        case .vo2:
            let unit = HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
            return (unit, "milliliters per kilogram per minute", 1)
        }
    }

    private static func refusal(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == HKErrorDomain else { return false }
        switch HKError.Code(rawValue: ns.code) {
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined, .errorRequiredAuthorizationDenied,
             .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return true
        default:
            return false
        }
    }
}

/// Collects chart buckets from a HealthKit enumeration.
private final class PointBox: @unchecked Sendable {
    private let lock = NSLock()
    private var points: [AskHealthPoint] = []

    func add(_ point: AskHealthPoint) {
        lock.lock()
        points.append(point)
        lock.unlock()
    }

    func all() -> [AskHealthPoint] {
        lock.lock()
        defer { lock.unlock() }
        return points
    }
}

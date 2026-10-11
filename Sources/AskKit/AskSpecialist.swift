import Foundation
import FoundationModels

/// A reply profile with its own instructions and tools.
///
/// The package ships one Apple specialist per source. An app adds its own and AskKit runs
/// each match in a separate session, up to three on a turn. A specialist holds at most five tools.
public struct AskSpecialist: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var symbolName: String
    /// Status line while this profile is active, before a tool runs.
    public var workingTitle: String
    public var instructions: String
    public var tools: @MainActor @Sendable () -> [any Tool]
    /// True when this specialist can answer the question.
    public var matches: @Sendable (String) -> Bool

    public init(
        id: String,
        title: String,
        symbolName: String,
        workingTitle: String,
        instructions: String,
        tools: @escaping @MainActor @Sendable () -> [any Tool],
        matches: @escaping @Sendable (String) -> Bool
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.workingTitle = workingTitle
        self.instructions = instructions
        self.tools = tools
        self.matches = matches
    }
}

/// One specialist chosen for a turn. Tests assert this without building tools.
struct AskSpecialistChoice: Equatable, Sendable {
    var id: String
    var title: String
    var workingTitle: String
    /// SF Symbol recorded on the specialist span. Empty keeps the brain.
    var symbolName: String
    var origin: Origin

    init(
        id: String,
        title: String,
        workingTitle: String,
        symbolName: String = "",
        origin: Origin
    ) {
        self.id = id
        self.title = title
        self.workingTitle = workingTitle
        self.symbolName = symbolName
        self.origin = origin
    }

    enum Origin: String, Equatable, Sendable {
        case host
        case domain
        case apple
    }
}

/// Which specialists run for one question.
struct AskSpecialistDecision: Equatable, Sendable {
    var choices: [AskSpecialistChoice]
    var capped: Bool
    var refusedToolCount: Bool
    /// Skill facts, with no tools.
    var usesWriter: Bool
    /// A catalog miss that named nothing. The capabilities card stays.
    var leavesMiss: Bool
}

enum AskTurnSpecialists {
    static let maximum = 3

    static func decide(
        question: String,
        skillID: String,
        facts: String,
        allowsTools: Bool,
        hosts: [AskSpecialistChoice],
        domainToolCount: Int,
        domainID: String,
        domainTitle: String,
        apple: AskAppleAccess
    ) -> AskSpecialistDecision {
        if !allowsTools {
            return AskSpecialistDecision(
                choices: [],
                capped: false,
                refusedToolCount: false,
                usesWriter: true,
                leavesMiss: false
            )
        }
        let needsTool = AskAppleCopy.questionNeedsATool(question)
        let toolOnly = facts.contains(AskAppleCopy.toolOnlySentence)
        let isMiss = skillID == AskAppleCopy.missSkillID
        // A miss that names nothing keeps the capabilities card. A greeting on a real skill uses the writer.
        if toolOnly, !needsTool, hosts.isEmpty, !isMiss {
            return AskSpecialistDecision(
                choices: [],
                capped: false,
                refusedToolCount: false,
                usesWriter: true,
                leavesMiss: false
            )
        }
        let apples = appleChoices(question: question, access: apple)
        var domain: AskSpecialistChoice?
        var refused = false
        if needsTool, !domainID.isEmpty, domainToolCount > 0 {
            if AskSessionPolicy.acceptedSkillToolCount(domainToolCount) == nil {
                refused = true
            } else {
                domain = AskSpecialistChoice(
                    id: "app.\(domainID)",
                    title: domainTitle,
                    workingTitle: "Checking \(domainTitle)",
                    origin: .domain
                )
            }
        }
        var picks = hosts
        if let domain { picks.append(domain) }
        picks.append(contentsOf: apples)
        let capped = picks.count > maximum
        if capped {
            picks = Array(picks.prefix(maximum))
        }
        if picks.isEmpty {
            if skillID == AskAppleCopy.missSkillID {
                return AskSpecialistDecision(
                    choices: [],
                    capped: false,
                    refusedToolCount: refused,
                    usesWriter: false,
                    leavesMiss: true
                )
            }
            if refused {
                return AskSpecialistDecision(
                    choices: [],
                    capped: false,
                    refusedToolCount: true,
                    usesWriter: false,
                    leavesMiss: false
                )
            }
            return AskSpecialistDecision(
                choices: [],
                capped: false,
                refusedToolCount: false,
                usesWriter: true,
                leavesMiss: false
            )
        }
        return AskSpecialistDecision(
            choices: picks,
            capped: capped,
            refusedToolCount: refused,
            usesWriter: false,
            leavesMiss: false
        )
    }

    /// The question names Apple sources and every one of them is turned off. Nil when one of them is on, or the question names none.
    static func closedSentence(question: String, access: AskAppleAccess) -> String? {
        guard AskAppleCopy.questionNeedsATool(question) else { return nil }
        let named = AskSourceFocus.named(in: question)
        let sources = AskAppleSource.catalog.filter { named.contains($0.name) }
        guard !sources.isEmpty, sources.allSatisfy({ !access.contains($0.access) }) else { return nil }
        let titles = sources.map(\.title)
        switch titles.count {
        case 1:
            let verb = titles[0].hasSuffix("s") ? "are" : "is"
            return "\(titles[0]) \(verb) turned off."
        case 2:
            return "\(titles[0]) and \(titles[1]) are turned off."
        default:
            let head = titles.dropLast().joined(separator: ", ")
            return "\(head), and \(titles[titles.count - 1]) are turned off."
        }
    }

    /// Enabled Apple sources the question names, in catalog order.
    /// A single named day selects calendar when the question needs a tool and names no other source.
    static func appleChoices(question: String, access: AskAppleAccess) -> [AskSpecialistChoice] {
        var names = AskSourceFocus.named(in: question)
        if names.isEmpty,
           access.contains(.calendar),
           AskAppleCopy.questionNeedsATool(question),
           AskCalendarWindow.offset(namedIn: question, now: Date(), calendar: .current) != nil {
            names.insert("calendar")
        }
        return AskAppleSource.catalog.compactMap { source in
            guard access.contains(source.access), names.contains(source.name) else { return nil }
            return AskSpecialistChoice(
                id: source.name,
                title: source.title,
                workingTitle: workingTitle(source.name),
                symbolName: source.symbol,
                origin: .apple
            )
        }
    }

    static func workingTitle(_ name: String) -> String {
        switch name {
        case "calendar": "Checking the calendar"
        case "reminders": "Checking reminders"
        case "contacts": "Checking contacts"
        case "location": "Checking the map"
        case "health": "Checking health data"
        case "music": "Checking music"
        case "weather": "Checking the forecast"
        case "alarms": "Checking alarms"
        default: "Checking"
        }
    }
}

/// The part of a compound question that names one Apple source.
/// One question, or parts that name the same source, stay whole.
enum AskSpecialistClause {
    static func question(for source: String, in question: String) -> String {
        let pieces = AskPages.pieces(question)
        guard pieces.count > 1 else { return question }
        let matching = pieces.filter { AskSourceFocus.named(in: $0).contains(source) }
        guard matching.count == 1, let clause = matching.first else { return question }
        let namesAnother = pieces.contains { piece in
            AskSourceFocus.named(in: piece).contains { $0 != source }
        }
        guard namesAnother else { return question }
        return clause
    }
}

enum AskAppleSpecialistNotes {
    static let preamble = """
    A tool result counts as FACTS. Say it. If a tool says Not allowed, say you cannot see that. Do not invent it.
    Call the tool once. After the result, write the answer. Do not call that tool again.
    CONVERSATION is not a source. Do not reuse an earlier result for a different question.
    Do not mention a place, a song, or a forecast from earlier in the chat.
    """

    static let domain = """
    Use these tools for this question. A tool result counts as FACTS. Say it. \
    If a tool says Not allowed, say you cannot see that. Do not invent it.
    Call each tool once. After the result, write the answer.
    """

    static func note(for name: String) -> String {
        let extra: String
        switch name {
        case "calendar":
            extra = """
            A different day needs its own calendar call. Say the weekday and date the tool returned.
            For a weekday, pass the number listed beside that weekday on the calendar tool. Do not count the days yourself.
            To add an event, call the tool with action add and the title. Pass place and notes when the person named them.
            To change an event, call action update with its current title, the day, and only the fields that change. newTitle renames it.
            To remove an event, call action delete with its title.
            Say it was added only when the line starts with Added, changed when it starts with Updated, and removed when it starts with Removed.
            """
        case "reminders":
            extra = """
            To add a reminder, call the tool with action add and the title. Pass notes and priority high, medium, or low when the person named them.
            To change a reminder, call action update with its title and only the fields that change. newTitle renames it.
            To remove a reminder, call action delete with its title.
            Say it was added only when the line starts with Added, changed when it starts with Updated, and removed when it starts with Removed.
            For a reminder list, say how many are open in one short sentence. Do not list the titles. The card lists them.
            When the person asks which reminder is next, say that reminder and when it is due.
            """
        case "contacts":
            extra = """
            When the person asks for an email, say the email the contacts tool returned.
            When the person asks for contacts that begin with letters, call action look with those letters and beginsWith true.
            When the person asks for contacts added recently, call action look with daysBack. 7 is last week. 30 is last month. Leave the name empty.
            To add a contact, call action add with the name. Pass the phone or email when they were said.
            Say it was added only when the line starts with Added.
            """
        case "location":
            extra = """
            A named place uses the location tool. Pass the place name. Pass here for where the person is.
            Pass nearby for places around the person.
            Name the place and the address. Do not mention coordinates, latitude, or longitude unless the person asked for them.
            Set the location tool's coordinates argument only then.
            """
        case "health":
            extra = """
            For a week, pass span week to the health tool. For a month, pass span month. For a year, pass span year.
            For workouts pass kind workouts. For sleep pass kind sleep.
            Call only this health tool. Do not add a reminder or look up a place from earlier in the chat.
            """
        case "music":
            extra = """
            A song, album, or playlist uses the music tool. Pass song, album, or playlist and the title. Pass play and the title to start playback. Pass now for what is playing.
            Pass recent for the last song played, and for songs the person listened to, including top songs and the past week. Do not search the catalog for those.
            Pass pause to pause, next to skip, and previous to go back.
            Say the title and the artist. Do not say a song is playing unless its line starts with Song.
            Do not say the song changed unless the tool says so.
            """
        case "weather":
            extra = """
            For the forecast, pass span hourly or span daily, the day number, and the city when one is named. 0 is today.
            Leave the city empty for where the person is. Say it in one or two short sentences. The card lists each day or each hour.
            """
        case "alarms":
            extra = """
            A count, or a question about which alarms are on, calls the alarms tool as a read and does not add an alarm. Say how many are on.
            To change an alarm, pass its current time and the new time or repeats. Recurring is daily, weekdays, weekends, or a weekday name.
            To remove an alarm, pass action delete and its time.
            To set alarms, call the alarms tool once and pass every alarm this question asked for. Each one needs a title and a time.
            Do not add an alarm the question did not ask for, and do not mention a reminder.
            Pass a label, an SF Symbol, and an action id from that tool's list when the person wants a custom button.
            Say an alarm was set only when its line starts with Added.
            """
        default:
            extra = ""
        }
        return extra.isEmpty ? preamble : preamble + "\n" + extra
    }
}

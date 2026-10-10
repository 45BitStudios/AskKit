import AskKit
import Foundation

/// Open ended. One skill. The person may ask anything.
///
/// Every question other than "What can I do?" goes to that skill. The reply is the model
/// the chat menu has selected, on-device or Private Cloud. A time question uses the clock specialist.
/// A photo-library question uses the photos specialist. A question with a page address uses the web specialist.
/// Any other question uses one Apple specialist for each source it names.
/// The first launch turns on calendar, reminders, contacts, location, and health. Music, weather, and
/// alarms stay off until the person turns them on. A greeting is answered without those tools. A tool
/// result is the only source for a calendar, reminder, contact, place, health, music, weather, or alarm question.
enum OpenSample {
    static let assistantName = "Open ended"

    static let appleAccess: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music, .weather, .alarms]

    /// Appends open-ended lines onto the built-in AskGuide prompts. Follow-ups are off.
    static let guide = AskGuide(
        routeOpening: .append("The person may ask anything. Answer from the tools that are available."),
        routeRules: .append("There is one skill, answer. Return answer."),
        replyInstructions: .append("""
        The person may ask anything.
        A greeting, thanks, or small talk needs no tool. Answer it in one or two short sentences.
        A question that contains a page address uses the web tool. Say the title it returns. Do not invent the title.
        A photo-library question uses the photos tool. Say how many matches it found. Do not invent photos.
        Call a tool for the person's calendar, reminders, contacts, location, health, music, weather, or alarms, and for where a named place is.
        Pass here to the location tool for where the person is. Pass the place name for where that place is.
        Do not mention coordinates unless the person asked for them. The map shows the place.
        To add an event, call calendar with action add, the title, and the day number from the tool's list. To add a reminder, call reminders with action add and the title.
        To change or remove an event or a reminder, call action update or delete with its title. To add a contact, call contacts with action add and the name. For contacts that begin with letters, call contacts with action look, those letters, and beginsWith true. For workouts pass kind workouts, and for sleep pass kind sleep. Pass pause, next, or previous to the music tool.
        When a tool ran, say only what it returned.
        For a reminder list, say how many are open. Do not list each title. The card lists them.
        If a tool says Not allowed, say you cannot see that.
        Do not invent a calendar event, a reminder, a contact, a place, a health reading, a song, an album, a forecast, or an alarm.
        For a forecast, pass span hourly or span daily to the weather tool, and the city when one is named. For a song or an album, pass the title to the music tool. Pass recent for the last song played, and now only for what is playing.
        Do not say an event, a reminder, or an alarm was added unless the tool line starts with Added.
        To set alarms, call the alarms tool once with every alarm. Pass a label, an SF Symbol, and an action id when the person wants a custom button.
        A different day needs its own calendar call. Say the weekday and date the tool returned. Do not copy an event from earlier in the chat.
        """),
        followUpInstructions: .replace("")
    )

    static func assistant() throws -> AskAssistant {
        AskAppleSelection.rememberIfNeeded(
            [.calendar, .reminders, .contacts, .location, .health],
            allowed: appleAccess,
            for: assistantName
        )
        return try AskAssistant(AskConfiguration(
            assistantName: assistantName,
            persistence: .memory,
            domains: [
                AskDomain(
                    id: "open",
                    summary: "Anything",
                    routingNotes: "Any question. The tools that are on are the only source."
                )
            ],
            skills: [skill],
            context: { AskContext() },
            chips: { _ in [] },
            fastPath: { utterance in
                let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : AskRoute(skillID: "answer")
            },
            guide: guide,
            specialists: [clock, photos],
            webMetadata: true,
            appleAccess: appleAccess
        ))
    }

    /// A clock question uses this specialist and no Apple tool.
    private static let clock = AskSpecialist(
        id: "open.clock",
        title: "Clock",
        symbolName: "clock",
        workingTitle: "Checking the time",
        instructions: """
        Call the clock tool once and say the time it returns. \
        If it says Not allowed, say you cannot see that. Do not invent the time.
        """,
        tools: { [SampleClockTool()] },
        matches: { SampleSpecialist.matches($0, anyOf: ["time", "clock"]) }
    )

    /// A photo-library question searches through PhotoQueryKit.
    /// The host calls `AskPhotos.prepareIndexOnLaunch()` so the saved index loads and only newer photos are indexed.
    private static let photos = AskPhotos.specialist(id: "open.photos")

    private static let skill = AskSkill(
        id: "answer",
        domainID: "open",
        title: "Any question",
        summary: "Answered from the Apple tools that are on",
        routingNotes: "Every request. The person may ask anything.",
        fulfillment: .reply { _ in
            AskChatActivity.update("Answering from the tools that are on")
            return AskReply(
                text: "I can answer from the tools that are on.",
                spoken: "I can answer from the tools that are on.",
                facts: "No app facts. Only a tool result may be stated. A greeting needs no tool result."
            )
        }
    )
}

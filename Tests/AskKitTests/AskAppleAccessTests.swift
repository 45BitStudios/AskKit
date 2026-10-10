import AlarmKit
import FoundationModels
import SwiftUI
import XCTest
@testable import AskKit

@MainActor
final class AskAppleAccessTests: XCTestCase {
    func testAppleAccessStartsEmpty() {
        let configuration = AskConfiguration(
            assistantName: "Ask",
            domains: [],
            skills: [],
            context: { AskContext() },
            chips: { _ in [] }
        )
        XCTAssertTrue(configuration.appleAccess.isEmpty)
        XCTAssertNil(configuration.appleCard)
        XCTAssertEqual(AskAppleTools.make([]).count, 0)
        XCTAssertEqual(AskAppleTools.make([.calendar, .location]).map(\.name), ["calendar", "location"])
    }

    func testSixSourcesLoadOnlyTheSpecialistThatMatches() async throws {
        let model = RecordingModel()
        let assistant = try assistant(model: model, access: [
            .calendar, .reminders, .contacts, .location, .health, .music
        ])
        let unmatched = await assistant.handle(utterance: "What's next?")
        XCTAssertTrue(model.toolCounts.isEmpty)
        XCTAssertEqual(model.plainReplies, 1)
        guard case .reply(let reply) = unmatched.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.spoken, "Pasta.")
        XCTAssertNil(unmatched.pages.first?.card)

        model.replyText = "Dentist at 3."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist at 3"])]
        let matched = await assistant.handle(utterance: "What's on my calendar?")
        XCTAssertEqual(model.toolCounts, [1])
        XCTAssertEqual(model.toolNames, [["calendar"]])
        XCTAssertEqual(matched.pages.first?.card?.title, "Calendar")
    }

    func testDomainToolsStayOnTheirOwnProfile() async throws {
        let refusedModel = RecordingModel()
        let refused = try assistant(
            model: refusedModel,
            access: [],
            tools: { _ in (0..<6).map { StubTool(name: "tool-\($0)") } }
        )
        let kept = await refused.handle(utterance: "What's on my calendar?")
        XCTAssertTrue(refusedModel.toolCounts.isEmpty)
        XCTAssertEqual(refusedModel.plainReplies, 0)
        guard case .reply(let keptReply) = kept.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(keptReply.spoken, "Pasta.")

        let model = RecordingModel()
        model.replyText = "Dentist at 3."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist at 3"])]
        let assistant = try assistant(
            model: model,
            access: [.calendar],
            tools: { _ in (0..<4).map { StubTool(name: "tool-\($0)") } }
        )
        let result = await assistant.handle(utterance: "What's on my calendar?")
        XCTAssertEqual(model.toolCounts, [4, 1])
        XCTAssertEqual(model.toolNames.map(\.first), ["tool-0", "calendar"])
        XCTAssertEqual(result.pages.first?.card?.title, "Calendar")
    }

    func testChipStaysToolFree() async throws {
        let model = RecordingModel()
        model.replyText = "Pasta tonight."
        let assistant = try assistant(model: model, access: [.calendar])
        let result = await assistant.handle(
            chip: AskChip(id: "dinner", skillID: "dinner", title: "What's for dinner?", slots: [:])
        )
        XCTAssertTrue(model.toolCounts.isEmpty)
        XCTAssertEqual(model.plainReplies, 1)
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.spoken, "Pasta tonight.")
        XCTAssertNil(result.pages.first?.card)
    }

    func testToolEqualsJoinsTheFactsAndALongLineIsStillRejected() async throws {
        let model = RecordingModel()
        model.replyText = "The limit=80."
        model.readings = [AskAppleReading(name: "calendar", lines: ["limit=80"])]
        let assistant = try assistant(model: model, access: [.calendar])
        let kept = await assistant.handle(utterance: "What's on my calendar?")
        guard case .reply(let keptReply) = kept.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(keptReply.spoken, "The limit=80.")
        XCTAssertEqual(kept.pages.first?.card?.title, "Calendar")
        XCTAssertEqual(model.toolCounts, [1])
        XCTAssertTrue(model.requests.last?.instructions.contains("Not allowed") == true)

        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist at 3"])]
        model.replyText = "limit=80"
        let rejected = await assistant.handle(utterance: "What is the calendar limit?")
        guard case .reply(let rejectedReply) = rejected.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(rejectedReply.spoken, "Pasta.")
        XCTAssertEqual(rejected.pages.first?.card?.title, "Calendar")

        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist at 3"])]
        model.replyText = String(repeating: "a", count: 601)
        let long = await assistant.handle(utterance: "Tell me more about the calendar")
        guard case .reply(let longReply) = long.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(longReply.spoken, "Pasta.")
        XCTAssertEqual(long.pages.first?.card?.title, "Calendar")
    }

    func testNilAppleCardKeepsTheBuiltInFactCard() async throws {
        let model = RecordingModel()
        model.replyText = "You leave at 7:30."
        model.readings = [AskAppleReading(name: "location", lines: ["1 Market Street", "37.7946, -122.3950"])]
        let assistant = try assistant(model: model, access: [.location], appleCard: { _, _ in nil })
        let result = await assistant.handle(utterance: "Where am I?")
        let card = result.pages.first?.card
        XCTAssertEqual(card?.title, "Location")
        XCTAssertEqual(result.pages.first?.text, "You leave at 7:30.")
        XCTAssertEqual(result.pages.first?.appleReading?.lines.first, "1 Market Street")
    }

    func testAppleCardCanReplaceTheFactCard() async throws {
        let model = RecordingModel()
        model.replyText = "The next stop is close."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Drive at 7:30"])]
        let assistant = try assistant(model: model, access: [.calendar], appleCard: { name, lines in
            AskIntentCard(title: "Stop", spoken: lines.joined(separator: " "), view: Text(name))
        })
        let result = await assistant.handle(utterance: "What's on my calendar?")
        XCTAssertEqual(result.pages.first?.card?.title, "Stop")
        XCTAssertEqual(result.pages.first?.text, "The next stop is close.")
    }

    func testAnIntentSkillKeepsItsOwnCard() async throws {
        let model = RecordingModel()
        model.replyText = "On time."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Drive at 7:30"])]
        let assistant = try AskAssistant(
            AskConfiguration(
                assistantName: "Ask",
                domains: [AskDomain(id: "trip", summary: "Trip", routingNotes: "Driving.")],
                skills: [
                    AskSkill(
                        id: "status",
                        domainID: "trip",
                        title: "Status",
                        summary: "Trip status",
                        routingNotes: "Status.",
                        fulfillment: .intent { _ in
                            AskIntentCard(title: "Trip", spoken: "On the way.", view: Text("Trip"))
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in AskRoute(skillID: "status") },
                guide: AskGuide(replyInstructions: "Rewrite FACTS."),
                appleAccess: [.calendar]
            ),
            model: model.client
        )
        let result = await assistant.handle(utterance: "What's my calendar status?")
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected the skill card")
        }
        XCTAssertEqual(card.title, "Trip")
        XCTAssertEqual(result.pages.first?.card?.title, "Trip")
        XCTAssertEqual(result.pages.first?.appleReading?.lines, ["Drive at 7:30"])
    }

    func testStoredAppleLinesSurviveAReload() async throws {
        let page = AskPage(
            question: "Where am I?",
            text: "You are near the shop.",
            spoken: "You are near the shop.",
            skillID: "dinner",
            domainID: "recipes",
            card: AskIntentCard(title: "Location", spoken: "You are near the shop.", view: Text("Shop")),
            appleReading: AskAppleReading(name: "location", lines: ["1 Market Street"])
        )
        let json = AskStoredPages.encode([page], omitting: [])
        let stored = AskStoredPages.decode(json)
        XCTAssertEqual(stored.first?.appleName, "location")
        XCTAssertEqual(stored.first?.appleLines, ["1 Market Street"])

        let data = Data(json.utf8)
        var rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        rows?[0].removeValue(forKey: "appleName")
        rows?[0].removeValue(forKey: "appleLines")
        let legacy = try JSONSerialization.data(withJSONObject: rows ?? [])
        let decoded = AskStoredPages.decode(String(data: legacy, encoding: .utf8) ?? "")
        XCTAssertEqual(decoded.first?.text, "You are near the shop.")
        XCTAssertEqual(decoded.first?.appleName, "")
    }

    func testHealthKindPicksWeightAndAllShowsEveryMeasurement() {
        XCTAssertEqual(AskHealthCatalog.metrics(matching: "weight").map(\.title), ["Weight"])
        XCTAssertEqual(AskHealthCatalog.metrics(matching: "resting heart").map(\.title), ["Resting heart rate"])
        XCTAssertEqual(AskHealthCatalog.metrics(matching: "resting heart rate").map(\.title), ["Resting heart rate"])
        XCTAssertEqual(AskHealthCatalog.metrics(matching: "heart").map(\.title), ["Heart rate"])
        XCTAssertEqual(AskHealthCatalog.metrics(matching: "steps and heart").map(\.title), ["Steps", "Heart rate"])
        XCTAssertEqual(AskHealthCatalog.metrics(matching: "all").count, AskHealthCatalog.Metric.allCases.count)
        XCTAssertEqual(AskHealthCatalog.metrics(matching: "mood").count, AskHealthCatalog.Metric.allCases.count)
    }

    func testAMissingChoiceUsesTheAppSet() {
        let defaults = isolatedDefaults()
        let allowed: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music]
        XCTAssertEqual(AskAppleSelection.active(allowed: allowed, for: "Ask Choice", defaults: defaults), allowed)
    }

    func testRememberedChoiceStaysUntilThePersonChangesIt() {
        let defaults = isolatedDefaults()
        let allowed: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music]
        let starting: AskAppleAccess = [.calendar, .location]
        AskAppleSelection.rememberIfNeeded(starting, allowed: allowed, for: "Ask Choice", defaults: defaults)
        AskAppleSelection.rememberIfNeeded([.music], allowed: allowed, for: "Ask Choice", defaults: defaults)
        XCTAssertEqual(
            AskAppleSelection.active(allowed: allowed, for: "Ask Choice", defaults: defaults),
            starting
        )
        let saved = AskAppleSelection.update([.music], allowed: allowed, for: "Ask Choice", defaults: defaults)
        XCTAssertEqual(saved, [.music])
        XCTAssertEqual(AskAppleSelection.active(allowed: allowed, for: "Ask Choice", defaults: defaults), [.music])
    }

    func testEveryAllowedSourceCanStayOn() {
        let defaults = isolatedDefaults()
        let allowed: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music, .weather, .alarms]
        let saved = AskAppleSelection.update(allowed, allowed: allowed, for: "Ask Choice", defaults: defaults)
        XCTAssertEqual(saved, allowed)
        XCTAssertEqual(AskAppleSelection.active(allowed: allowed, for: "Ask Choice", defaults: defaults), allowed)
        let outside = AskAppleSelection.update([.music], allowed: [.calendar], for: "Ask Choice", defaults: defaults)
        XCTAssertTrue(outside.isEmpty)
    }

    func testSavedSelectionIsWhatTheReplyUses() async throws {
        let name = "Ask Selection"
        defer { UserDefaults.standard.removeObject(forKey: AskAppleSelection.storageKey(for: name)) }
        let allowed: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music]
        AskAppleSelection.update([.calendar], allowed: allowed, for: name)
        let model = RecordingModel()
        model.replyText = "Dentist at 3."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist at 3"])]
        let assistant = try assistant(model: model, access: allowed, name: name)
        let result = await assistant.handle(utterance: "What's the weather and what's on my calendar?")
        XCTAssertEqual(model.toolCounts, [1])
        XCTAssertEqual(model.toolNames, [["calendar"]])
        XCTAssertEqual(result.pages.first?.card?.title, "Calendar")
    }

    func testASkillMissUsesTheAppleTools() async throws {
        let model = RecordingModel()
        model.routeSkillID = ""
        model.replyText = "Dentist at 3."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist · Tue"])]
        let assistant = try assistant(model: model, access: [.calendar], fastPath: nil)
        let result = await assistant.handle(utterance: "Can you check my Apple calendar")
        XCTAssertEqual(model.toolCounts, [1])
        XCTAssertEqual(result.skillID, AskAppleCopy.missSkillID)
        XCTAssertNil(result.followUp)
        XCTAssertEqual(result.pages.first?.card?.title, "Calendar")
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.spoken, "Dentist at 3.")
    }

    func testASkillMissKeepsTheToolLinesWhenTheSentenceIsEmpty() async throws {
        let model = RecordingModel()
        model.routeSkillID = ""
        model.replyText = ""
        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist · Tue"])]
        let assistant = try assistant(model: model, access: [.calendar], fastPath: nil)
        let result = await assistant.handle(utterance: "Can you check my Apple calendar")
        XCTAssertEqual(result.skillID, AskAppleCopy.missSkillID)
        XCTAssertEqual(result.pages.first?.card?.title, "Calendar")
        guard case .reply(let reply) = result.fulfillment else {
            return XCTFail("Expected a reply")
        }
        XCTAssertEqual(reply.spoken, "Dentist · Tue")
    }

    func testASkillMissWithoutAToolResultKeepsTheHelpCard() async throws {
        let model = RecordingModel()
        model.routeSkillID = ""
        model.replyText = "I looked."
        let assistant = try assistant(model: model, access: [.calendar], fastPath: nil)
        let result = await assistant.handle(utterance: "Who won the game?")
        XCTAssertTrue(model.toolCounts.isEmpty)
        XCTAssertEqual(model.plainReplies, 0)
        XCTAssertEqual(result.skillID, AskCapabilities.skillID)
        guard case .intent(let card) = result.fulfillment else {
            return XCTFail("Expected the capabilities card")
        }
        XCTAssertTrue(card.spoken.hasPrefix("I can't help with that."))
    }

    func testASkillMissWithNoAppleAccessKeepsTheHelpCard() async throws {
        let model = RecordingModel()
        model.routeSkillID = ""
        let assistant = try assistant(model: model, access: [], fastPath: nil)
        let result = await assistant.handle(utterance: "Can you check my Apple calendar")
        XCTAssertTrue(model.toolCounts.isEmpty)
        XCTAssertEqual(model.plainReplies, 0)
        XCTAssertEqual(result.skillID, AskCapabilities.skillID)
    }

    func testJoinedToolTextFeedsTheEqualsCheck() {
        let facts = AskAppleFacts.appending("Battery is fine.", readings: [
            AskAppleReading(name: "calendar", lines: ["limit=80"])
        ])
        XCTAssertTrue(AskGuide.acceptsReply("The limit=80.", facts: facts))
        let plain = AskAppleFacts.appending("Battery is fine.", readings: [
            AskAppleReading(name: "calendar", lines: ["Dentist at 3"])
        ])
        XCTAssertFalse(AskGuide.acceptsReply("limit=80", facts: plain))
        XCTAssertFalse(AskGuide.acceptsReply(String(repeating: "a", count: 601), facts: facts))
        XCTAssertEqual(AskAppleFacts.appending("Battery is fine.", readings: []), "Battery is fine.")
    }

    func testMondayAfterWednesdayIsFiveDaysAhead() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))!
        XCTAssertEqual(AskCalendarWindow.offset(namedIn: "Anything for Monday", now: now, calendar: calendar), 5)
        XCTAssertEqual(AskCalendarWindow.offset(namedIn: "What about Friday", now: now, calendar: calendar), 2)
        XCTAssertEqual(AskCalendarWindow.offset(namedIn: "What about Saturday", now: now, calendar: calendar), 3)
        XCTAssertEqual(AskCalendarWindow.offset(namedIn: "today", now: now, calendar: calendar), 0)
        XCTAssertNil(AskCalendarWindow.offset(namedIn: "Hello", now: now, calendar: calendar))
        XCTAssertNil(AskCalendarWindow.offset(namedIn: "Friday and Saturday", now: now, calendar: calendar))
        let wrong = [AskAppleReading(name: "calendar", lines: ["Saturday, Oct 17 · Nothing scheduled."])]
        XCTAssertEqual(
            AskCalendarWindow.calendarRereadOffset(question: "Anything for Monday", readings: wrong, now: now, calendar: calendar),
            5
        )
        let right = [AskAppleReading(name: "calendar", lines: ["Monday, Oct 12 · Nothing scheduled."])]
        XCTAssertNil(AskCalendarWindow.calendarRereadOffset(question: "Anything for Monday", readings: right, now: now, calendar: calendar))
        let added = [AskAppleReading(name: "calendar", lines: ["Added Saturday, Oct 17 · Dentist · 3:00 PM"])]
        XCTAssertNil(AskCalendarWindow.calendarRereadOffset(question: "Anything for Monday", readings: added, now: now, calendar: calendar))
        let changed = [AskAppleReading(name: "calendar", lines: ["Updated Saturday, Oct 17 · Dentist · 4:00 PM"])]
        XCTAssertNil(AskCalendarWindow.calendarRereadOffset(question: "Anything for Monday", readings: changed, now: now, calendar: calendar))
        let removed = [AskAppleReading(name: "calendar", lines: ["Removed Saturday, Oct 17 · Dentist · 3:00 PM"])]
        XCTAssertNil(AskCalendarWindow.calendarRereadOffset(question: "Anything for Monday", readings: removed, now: now, calendar: calendar))
        XCTAssertTrue(AskCalendarWindow.dayMenu(now: now, calendar: calendar).contains("5 Monday"))
        XCTAssertEqual(AskHealthCatalog.kind(in: "How many steps do I have today"), "steps")
        XCTAssertNil(AskHealthCatalog.kind(in: "Anything for Monday"))
        XCTAssertEqual(AskHealthCatalog.kind(in: "How did I sleep"), "sleep")
        XCTAssertEqual(AskHealthCatalog.kind(in: "Show my workouts"), "workouts")
        XCTAssertEqual(AskHealthCatalog.kind(in: "exercise minutes today"), "exercise minutes")
        XCTAssertFalse(AskHealthCatalog.isActivity("exercise"))
        XCTAssertFalse(AskHealthCatalog.isActivity("steps"))
        XCTAssertNotEqual(AskHealthCatalog.kind(in: "What is my temperature"), "sleep")
        XCTAssertNotEqual(AskHealthCatalog.kind(in: "What is my temperature"), "workouts")
    }

    func testCalendarOffsetReadsOneDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))!
        let today = AskCalendarWindow.day(offset: 0, now: now, calendar: calendar)
        let tomorrow = AskCalendarWindow.day(offset: 1, now: now, calendar: calendar)
        let friday = AskCalendarWindow.day(offset: 2, now: now, calendar: calendar)
        XCTAssertEqual(today?.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 7)))
        XCTAssertEqual(tomorrow?.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))
        XCTAssertEqual(friday?.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 9)))
        XCTAssertEqual(today?.end, tomorrow?.start)
        XCTAssertEqual(tomorrow?.end, friday?.start)
        XCTAssertEqual(today?.end.timeIntervalSince(today!.start), 86_400)
        XCTAssertTrue(today?.title.localizedStandardContains("Wednesday") == true)
        XCTAssertTrue(friday?.title.localizedStandardContains("Friday") == true)
        XCTAssertNotEqual(today?.title, friday?.title)
        let earlier = AskCalendarWindow.day(offset: -4, now: now, calendar: calendar)
        let capped = AskCalendarWindow.day(offset: 40, now: now, calendar: calendar)
        let limit = AskCalendarWindow.day(offset: AskCalendarWindow.maximumOffset, now: now, calendar: calendar)
        XCTAssertEqual(earlier?.start, today?.start)
        XCTAssertEqual(capped?.start, limit?.start)
        XCTAssertEqual(limit?.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
    }

    func testLaterCallsToTheSameToolStayOnTheCard() {
        let reading = AskAppleCards.first([
            AskAppleReading(name: "calendar", lines: ["Wednesday, Oct 7 · Standup · 9:00 AM"]),
            AskAppleReading(name: "location", lines: ["Here"]),
            AskAppleReading(name: "calendar", lines: ["Friday, Oct 9 · Nothing scheduled."])
        ])
        XCTAssertEqual(reading?.name, "calendar")
        XCTAssertEqual(reading?.lines, [
            "Wednesday, Oct 7 · Standup · 9:00 AM",
            "Friday, Oct 9 · Nothing scheduled."
        ])
        let both = AskAppleCards.sources([
            AskAppleReading(name: "location", lines: ["7601 E Ben White Boulevard Frontage Rd, Austin"]),
            AskAppleReading(name: "reminders", lines: ["1 open reminder."]),
            AskAppleReading(name: "location", lines: ["Austin"])
        ])
        XCTAssertEqual(both.map(\.name), ["location", "reminders"])
        XCTAssertEqual(both[0].lines, ["7601 E Ben White Boulevard Frontage Rd, Austin", "Austin"])
    }

    func testAPlaceAndAReminderAreTwoCards() async throws {
        let model = RecordingModel()
        let spoken = "You are at 7601 E Ben White Boulevard Frontage Rd, Austin, and there is 1 open reminder."
        model.replyText = spoken
        let place = AskLocationPin.line(
            label: "7601 E Ben White Boulevard Frontage Rd, Austin",
            latitude: 30.2169,
            longitude: -97.6926
        )
        let reminder = AskReminderItem.line(
            title: "Cancel TDS internet",
            due: "Sep 24, 2026",
            id: "7870A62E-C7AA-48F0-8106-16CC3FAA1A4B"
        )
        model.readings = [
            AskAppleReading(name: "location", lines: [place]),
            AskAppleReading(name: "reminders", lines: [reminder])
        ]
        let assistant = try assistant(
            model: model,
            access: [.location, .reminders],
            spoken: "Skill line.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let asked = "What location am I at and what's the next thing on my Reminder reminders"
        let result = await assistant.handle(utterance: asked)
        XCTAssertEqual(result.pages.count, 2)
        XCTAssertEqual(result.pages[0].text, spoken)
        XCTAssertEqual(result.pages[0].card?.title, "Location")
        XCTAssertEqual(result.pages[1].text, "")
        XCTAssertEqual(result.pages[1].spoken, "")
        XCTAssertEqual(result.pages[1].card?.title, "Reminders")
        XCTAssertTrue(result.pages[1].card?.shareText.contains("Cancel TDS internet") == true)
        XCTAssertNil(result.followUp)
        let turns = try assistant.transcript()
        XCTAssertEqual(turns.filter { $0.role == "user" }.map(\.text), [asked])
        XCTAssertEqual(turns.filter { $0.role == "assistant" }.count, 1)
        XCTAssertEqual(turns.last?.text, spoken)
        let restored = await assistant.pages(for: try XCTUnwrap(turns.last?.id))
        XCTAssertEqual(restored.map { $0.card?.title }, ["Location", "Reminders"])
    }

    func testAGreetingDoesNotCallTools() async throws {
        let model = RecordingModel()
        model.replyText = "Hello. What should I look up?"
        let fallback = "I can answer from the tools that are on."
        let assistant = try assistant(
            model: model,
            access: [.calendar, .reminders, .contacts, .location, .health],
            spoken: fallback,
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(utterance: "Hello")
        XCTAssertEqual(result.pages.first?.text, "Hello. What should I look up?")
        XCTAssertNil(result.pages.first?.card)
        XCTAssertEqual(model.plainReplies, 1)
        XCTAssertTrue(model.toolCounts.isEmpty)
        XCTAssertEqual(model.requests.last?.requiresToolCall, false)
        XCTAssertFalse(AskAppleCopy.questionNeedsATool("Hello"))
        XCTAssertFalse(AskAppleCopy.questionNeedsATool("how are you today"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("What about Friday"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("today"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("how many steps today"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("Where is Apple Park?"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("Remind me to buy milk"))
        XCTAssertEqual(AskPlaceQuery.lookup(in: "Where is Apple Park?"), "Apple Park")
        XCTAssertEqual(AskPlaceQuery.lookup(in: "Where am I?"), "here")
        XCTAssertNil(AskPlaceQuery.lookup(in: "How many steps do I have today"))
        XCTAssertNil(AskPlaceQuery.lookup(in: "Hello"))
        XCTAssertEqual(
            AskCalendarCommand.parse(action: nil, day: 5, title: nil, hour: nil, minute: nil),
            .read(5)
        )
        XCTAssertEqual(
            AskCalendarCommand.parse(action: "add", day: 1, title: "Dentist", hour: 15, minute: 30),
            .add(title: "Dentist", day: 1, hour: 15, minute: 30, place: "", notes: "")
        )
        XCTAssertEqual(
            AskCalendarCommand.parse(action: "add", day: 1, title: "  ", hour: nil, minute: nil),
            .needsTitle
        )
        XCTAssertEqual(
            AskReminderCommand.parse(action: "read", limit: 4, title: nil, day: nil, hour: nil, minute: nil),
            AskReminderCommand.list(4)
        )
        XCTAssertEqual(
            AskReminderCommand.parse(action: "add", limit: 8, title: "Buy milk", day: nil, hour: nil, minute: nil),
            .add(title: "Buy milk", day: nil, hour: nil, minute: 0, notes: "", priority: "")
        )
    }

    func testWritesAndTransportStayInTheParser() {
        XCTAssertEqual(
            AskCalendarCommand.parse(
                action: "add", day: 1, title: "Dentist", hour: 15, minute: 30, place: "Apple Park", notes: "Bring x-rays"
            ),
            .add(title: "Dentist", day: 1, hour: 15, minute: 30, place: "Apple Park", notes: "Bring x-rays")
        )
        XCTAssertEqual(
            AskCalendarCommand.parse(action: "update", day: 1, title: "Dentist", hour: nil, minute: nil, place: "Apple Park"),
            .update(title: "Dentist", day: 1, hour: nil, minute: nil, place: "Apple Park", notes: nil, newTitle: nil)
        )
        XCTAssertEqual(
            AskCalendarCommand.parse(action: "update", day: 1, title: "Dentist", hour: nil, minute: nil),
            .needsChange
        )
        XCTAssertEqual(
            AskCalendarCommand.parse(action: "delete", day: 2, title: "Dentist", hour: nil, minute: nil),
            .delete(title: "Dentist", day: 2)
        )
        XCTAssertEqual(
            AskCalendarCommand.parse(action: "add", day: 1, title: "Dentist", hour: 30, minute: 0),
            .badTime
        )
        XCTAssertEqual(
            AskReminderCommand.parse(
                action: "add", limit: 8, title: "Buy milk", day: nil, hour: nil, minute: nil, notes: "2 percent", priority: "high"
            ),
            .add(title: "Buy milk", day: nil, hour: nil, minute: 0, notes: "2 percent", priority: "high")
        )
        XCTAssertEqual(
            AskReminderCommand.parse(action: "update", limit: 8, title: "Buy milk", day: nil, hour: nil, minute: nil),
            .needsChange
        )
        XCTAssertEqual(
            AskReminderCommand.parse(
                action: "update", limit: 8, title: "Buy milk", day: nil, hour: nil, minute: nil, priority: "low"
            ),
            .update(title: "Buy milk", day: nil, hour: nil, minute: nil, notes: nil, priority: "low", newTitle: nil)
        )
        XCTAssertEqual(
            AskReminderCommand.parse(action: "delete", limit: 8, title: "Buy milk", day: nil, hour: nil, minute: nil),
            .delete(title: "Buy milk")
        )
        XCTAssertEqual(
            AskReminderCommand.parse(action: "add", limit: 8, title: "Buy milk", day: nil, hour: nil, minute: nil, priority: "urgent"),
            .add(title: "Buy milk", day: nil, hour: nil, minute: 0, notes: "", priority: "")
        )
        XCTAssertEqual(
            AskContactCommand.parse(action: "look", name: "Ada", phone: nil, email: nil),
            .lookup(name: "Ada", prefix: false)
        )
        XCTAssertEqual(
            AskContactCommand.parse(action: "look", name: "Mo", phone: nil, email: nil, beginsWith: true),
            .lookup(name: "Mo", prefix: true)
        )
        XCTAssertEqual(
            AskContactCommand.parse(action: "add", name: "Ada Lovelace", phone: "555", email: "ada@example.com"),
            .add(name: "Ada Lovelace", phone: "555", email: "ada@example.com")
        )
        XCTAssertEqual(AskContactCommand.parse(action: "add", name: "  ", phone: nil, email: nil), .needsName)
        let addedContact = AskContactLine.person(from: "Added Ada Lovelace · 555 · ada@example.com")
        XCTAssertTrue(addedContact.isPerson)
        XCTAssertEqual(addedContact.email, "ada@example.com")
        XCTAssertTrue(AskAppleCopy.keepsWrite("Updated Dentist"))
        XCTAssertTrue(AskAppleCopy.keepsWrite("Removed Buy milk."))
        XCTAssertFalse(AskAppleCopy.keepsWrite("Friday · Dentist"))
        XCTAssertEqual(AskReminderItem.forModel("Updated Buy milk."), "Updated Buy milk.")
        XCTAssertEqual(AskReminderItem.forModel("Removed Buy milk."), "Removed Buy milk.")
        let listed = AskReminderItem.line(title: "Buy milk", due: "Oct 9 · high · 2 percent", id: "milk")
        XCTAssertEqual(AskReminderItem.forModel(listed), "1 open reminder.")
        XCTAssertEqual(AskReminderItem.parse(listed)?.title, "Buy milk")
        XCTAssertFalse(listed.contains("="))
        XCTAssertNil(AskHealthChartModel.parse(["Workouts: 2 this week", "Running · 30 minutes · Oct 8"]))
        XCTAssertNil(AskHealthChartModel.parse(["Sleep: 7.2 hours a night this week"]))
        XCTAssertEqual(AskHealthChartModel.parse(["Steps: 100 steps"])?.metric, .steps)
        XCTAssertEqual(AskMusicQuery.request(in: "pause the music").kind, .pause)
        XCTAssertEqual(AskMusicQuery.request(in: "stop the music").kind, .pause)
        XCTAssertEqual(AskMusicQuery.request(in: "stop").kind, .song)
        XCTAssertEqual(AskMusicQuery.request(in: "skip this song").kind, .next)
        XCTAssertEqual(AskMusicQuery.request(in: "next song").kind, .next)
        XCTAssertEqual(AskMusicQuery.request(in: "next").kind, .song)
        XCTAssertEqual(AskMusicQuery.request(in: "previous song").kind, .previous)
        XCTAssertEqual(AskMusicQuery.request(in: "What's my last played song?").kind, .recent)
        XCTAssertEqual(AskMusicQuery.request(which: "pause", query: "Taylor").kind, .pause)
        XCTAssertEqual(AskMusicQuery.request(which: "next", query: "Taylor").kind, .next)
        XCTAssertEqual(AskMusicQuery.request(which: "previous", query: "").kind, .previous)
        XCTAssertFalse(AskMusicQuery.needsReread(AskMusicQuery.request(in: "pause the music"), lines: []))
        XCTAssertFalse(AskMusicQuery.needsReread(AskMusicQuery.request(which: "next", query: nil), lines: []))
        let pausePlan = AskAppleRepair.plan(question: "pause the music", readings: [], toolNames: ["music"])
        XCTAssertNil(pausePlan.music)
        let sleepPlan = AskAppleRepair.plan(question: "How did I sleep", readings: [], toolNames: ["health"])
        XCTAssertEqual(sleepPlan.healthKind, "sleep")
        let workoutPlan = AskAppleRepair.plan(
            question: "Show my workouts",
            readings: [AskAppleReading(name: "health", lines: ["Steps: 100 steps"])],
            toolNames: ["health"]
        )
        XCTAssertEqual(workoutPlan.healthKind, "workouts")
        let keptWorkouts = AskAppleRepair.plan(
            question: "Show my workouts",
            readings: [AskAppleReading(name: "health", lines: ["Workouts: 1 this week", "Running · 30 minutes · Oct 8"])],
            toolNames: ["health"]
        )
        XCTAssertNil(keptWorkouts.healthKind)
        let addedPerson = AskAppleRepair.plan(
            question: "Add a contact named Ada Lovelace",
            readings: [AskAppleReading(name: "contacts", lines: ["Added Ada Lovelace · 555"])],
            toolNames: ["contacts"]
        )
        XCTAssertNil(addedPerson.contactQuery)
        XCTAssertFalse(addedPerson.rereadContact)
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("pause the music"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("add a contact"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("how did I sleep"))
        XCTAssertFalse(replyContainsEquals([
            "Added Wednesday, Oct 8 · Dentist · 3:00 PM · Apple Park",
            "Updated Buy milk.",
            "Removed Buy milk.",
            "Added Ada Lovelace · 555 · ada@example.com",
            "Paused.",
            "Skipped to the next song.",
            "Went back to the previous song.",
            "Workouts: 1 this week",
            "Running · 30 minutes · Oct 8",
            "Sleep: 7.2 hours a night this week"
        ]))
    }

    private func replyContainsEquals(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("=") }
    }

    func testAnEmptyToolReplyUsesTheReading() async throws {
        let model = RecordingModel()
        model.replyText = ""
        model.readings = [AskAppleReading(name: "calendar", lines: ["Friday, Oct 9 · Nothing scheduled."])]
        let assistant = try assistant(
            model: model,
            access: [.calendar],
            spoken: "I can answer from the tools that are on.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(utterance: "What about Friday")
        XCTAssertEqual(result.pages.first?.text, "Friday, Oct 9 · Nothing scheduled.")
        XCTAssertEqual(result.pages.first?.card?.title, "Calendar")
    }

    func testARepeatedToolCallStops() throws {
        let ledger = AskToolLedger()
        try ledger.claim(name: "calendar", arguments: "day 0")
        ledger.finish(name: "calendar", output: "Friday, Oct 9 · Nothing scheduled.")
        XCTAssertThrowsError(try ledger.claim(name: "calendar", arguments: "day 0"))
        try ledger.claim(name: "calendar", arguments: "day 2")
        XCTAssertEqual(ledger.snapshot().map(\.name), ["calendar"])
        XCTAssertEqual(ledger.snapshot().first?.lines, ["Friday, Oct 9 · Nothing scheduled."])
        let tools = AskAppleTools.make([.calendar])
        XCTAssertTrue(AskAppleTools.readings(in: tools).isEmpty)
    }

    func testInventedDayIsDroppedWhenFactsRequireATool() async throws {
        let model = RecordingModel()
        model.replyText = "Your calendar shows two events for Friday: Darnell Jones's 49th Birthday."
        let fallback = "I can answer from the tools that are on."
        let assistant = try assistant(
            model: model,
            access: [.calendar],
            spoken: fallback,
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(utterance: "What about Friday")
        XCTAssertEqual(result.pages.first?.text, fallback)
        XCTAssertNil(result.pages.first?.card)
        XCTAssertEqual(model.requests.last?.requiresToolCall, true)
        XCTAssertTrue(model.requests.last?.instructions.contains("own calendar call") == true)
    }

    func testAToolResultStaysWhenFactsRequireATool() async throws {
        let model = RecordingModel()
        model.replyText = "Friday, Oct 9 has nothing scheduled."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Friday, Oct 9 · Nothing scheduled."])]
        let assistant = try assistant(
            model: model,
            access: [.calendar],
            spoken: "I can answer from the tools that are on.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(utterance: "What about Friday")
        XCTAssertEqual(result.pages.first?.text, "Friday, Oct 9 has nothing scheduled.")
        XCTAssertEqual(result.pages.first?.card?.title, "Calendar")
    }

    func testSkillFactsStillRewriteWhenNoToolRan() async throws {
        let model = RecordingModel()
        model.replyText = "Tomato pasta tonight."
        let assistant = try assistant(model: model, access: [.calendar])
        let result = await assistant.handle(utterance: "What's for dinner?")
        XCTAssertEqual(result.pages.first?.text, "Tomato pasta tonight.")
        XCTAssertEqual(model.requests.last?.requiresToolCall, false)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "AskAppleSelectionTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAPlaceAnswerHidesCoordinatesUnlessAsked() {
        let stored = AskLocationPin.line(
            label: "Apple Park, 1 Apple Park Way, Cupertino",
            latitude: 37.3349,
            longitude: -122.0090
        )
        let parsed = AskLocationPin.parse(stored)
        XCTAssertEqual(parsed.label, "Apple Park, 1 Apple Park Way, Cupertino")
        XCTAssertEqual(parsed.place?.latitude ?? 0, 37.3349, accuracy: 0.0001)
        XCTAssertEqual(parsed.place?.longitude ?? 0, -122.0090, accuracy: 0.0001)
        XCTAssertEqual(
            AskLocationPin.forModel(stored, includeCoordinates: false),
            "Apple Park, 1 Apple Park Way, Cupertino"
        )
        XCTAssertEqual(
            AskLocationPin.forModel(stored, includeCoordinates: true),
            "Apple Park, 1 Apple Park Way, Cupertino. Coordinates 37.3349, -122.0090"
        )
        let copied = "Apple Park is at 1 Apple Park Way, Cupertino, with coordinates 37.3349 and -122.0090."
        let readings = [AskAppleReading(name: "location", lines: [stored])]
        XCTAssertEqual(
            AskLocationPin.adjust(copied, question: "Where is Apple Park", readings: readings),
            "Apple Park is at 1 Apple Park Way, Cupertino."
        )
        XCTAssertFalse(AskLocationPin.asks("Where is Apple Park"))
        XCTAssertTrue(AskLocationPin.asks("What are the coordinates of Apple Park?"))
        XCTAssertEqual(
            AskLocationPin.adjust("Apple Park is in Cupertino.", question: "What are the coordinates?", readings: readings),
            "Apple Park is in Cupertino. Coordinates 37.3349, -122.0090."
        )
        XCTAssertEqual(AskLocationPin.labels(in: ["Not allowed."]), ["Not allowed."])
    }

    func testMapRegionFramesEveryPlace() {
        let places = [
            AskLocationPin.Place(label: "Apple Park, 1 Apple Park Way", latitude: 37.3349, longitude: -122.0090),
            AskLocationPin.Place(label: "Visitor Center, 10600 N Tantau Ave", latitude: 37.3327, longitude: -122.0053),
            AskLocationPin.Place(label: "Main Street, Cupertino", latitude: 37.3230, longitude: -122.0322)
        ]
        let region = AskLocationRegion.region(for: places)
        for place in places {
            XCTAssertGreaterThanOrEqual(place.latitude, region.center.latitude - region.span.latitudeDelta / 2)
            XCTAssertLessThanOrEqual(place.latitude, region.center.latitude + region.span.latitudeDelta / 2)
            XCTAssertGreaterThanOrEqual(place.longitude, region.center.longitude - region.span.longitudeDelta / 2)
            XCTAssertLessThanOrEqual(place.longitude, region.center.longitude + region.span.longitudeDelta / 2)
        }
        XCTAssertNotEqual(AskSnippetMaps.key([places[0]]), AskSnippetMaps.key(places))
        let alone = AskLocationRegion.region(for: [places[0]])
        XCTAssertEqual(alone.center.latitude, places[0].latitude, accuracy: 0.0001)
        XCTAssertEqual(alone.span.latitudeDelta, 0.02, accuracy: 0.0001)
    }

    func testAReminderListSpeaksTheCountAndKeepsEachTask() {
        let lines = [
            AskReminderItem.line(title: "Manage my free Bird account", due: "", id: "bird"),
            AskReminderItem.line(title: "Cancel TDS internet", due: "Sep 24, 2026", id: "tds"),
            AskReminderItem.line(title: "Cancel TruGreen lawn", due: "Sep 24, 2026", id: "lawn"),
            AskReminderItem.line(title: "Cancel pest control", due: "Sep 24, 2026", id: "pest"),
            AskReminderItem.line(title: "Send Hazel more subscriptions", due: "Sep 28, 2026, 9:14 AM", id: "hazel"),
            AskReminderItem.line(title: "Look at your reminders", due: "Sep 24, 2026, 3:00 PM", id: "look"),
            AskReminderItem.line(title: "Ask about Haton type", due: "Sep 30, 2026", id: "haton"),
            AskReminderItem.line(title: "Go to Walgreens", due: "Sep 30, 2026, 10:00 AM", id: "store")
        ]
        let stored = lines.joined(separator: "\n")
        XCTAssertEqual(AskReminderItem.forModel(stored), "8 open reminders.")
        XCTAssertFalse(AskReminderItem.forModel(stored).contains("Walgreens"))
        XCTAssertFalse(stored.contains("12:00"))
        let first = AskReminderItem.parse(lines[1])
        XCTAssertEqual(first?.id, "tds")
        XCTAssertEqual(first?.title, "Cancel TDS internet")
        XCTAssertEqual(first?.due, "Sep 24, 2026")
        XCTAssertEqual(AskLocationPin.labels(in: [lines[1]]), ["Cancel TDS internet · Sep 24, 2026"])
        XCTAssertFalse(AskLocationPin.labels(in: [lines[1]])[0].contains("\u{1F}"))
        let readings = [AskAppleReading(name: "reminders", lines: lines)]
        let dumped = """
        Here are your reminders:
        - Cancel TDS internet · Sep 24, 2026 at 12:00 AM
        - Go to Walgreens · Sep 30, 2026 at 10:00 AM
        """
        XCTAssertEqual(AskReminderItem.speech(dumped, readings: readings), "You have 8 open reminders.")
        XCTAssertEqual(
            AskReminderItem.speech("You have 1 open reminder.", readings: [
                AskAppleReading(name: "reminders", lines: [lines[0]])
            ]),
            "You have 1 open reminder."
        )
        let added = AskReminderItem.line(title: "Added Buy milk", due: "Oct 8, 2026", id: "milk")
        XCTAssertEqual(AskReminderItem.forModel(added), "Added Buy milk")
        XCTAssertEqual(
            AskReminderItem.speech("ignored", readings: [AskAppleReading(name: "reminders", lines: [added])]),
            "Added Buy milk."
        )
        XCTAssertEqual(
            AskReminderItem.speech("No reminders.", readings: [AskAppleReading(name: "reminders", lines: ["No reminders."])]),
            "No reminders."
        )
        XCTAssertEqual(
            AskReminderItem.speech("Friday is clear. You also have reminders.", readings: [
                AskAppleReading(name: "calendar", lines: ["Friday, Oct 9 · Nothing scheduled."]),
                AskAppleReading(name: "reminders", lines: lines)
            ]),
            "Friday is clear. You also have reminders."
        )
        let card = AskAppleCards.make(
            AskAppleReading(name: "reminders", lines: lines),
            spoken: "You have 8 open reminders.",
            custom: nil
        )
        XCTAssertEqual(card.title, "Reminders")
        XCTAssertTrue(card.shareText.contains("Cancel TDS internet · Sep 24, 2026"))
        XCTAssertFalse(card.shareText.contains("\u{1F}"))
        XCTAssertEqual(AskReminderItem.tasks(in: lines).count, 8)
    }

    func testACalendarQuestionReadsThatDayAndDropsOtherSources() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16))!
        let asked = "What's on my calendar for Saturday"
        let reminders = [AskAppleReading(name: "reminders", lines: ["6 open reminders."])]
        let place = [AskAppleReading(name: "location", lines: ["No matching place."])]
        let missed = AskAppleRepair.plan(
            question: asked,
            readings: reminders + place,
            toolNames: ["calendar", "reminders", "location"],
            lookupPlaces: true,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(missed.keep, ["calendar"])
        XCTAssertEqual(missed.calendarDay, 2)
        XCTAssertNil(missed.place)
        XCTAssertNil(missed.healthKind)
        XCTAssertEqual(
            AskCalendarWindow.calendarRereadOffset(question: asked, readings: [], now: now, calendar: calendar),
            2
        )
        XCTAssertNil(
            AskCalendarWindow.calendarRereadOffset(
                question: "How many steps today",
                readings: [],
                now: now,
                calendar: calendar
            )
        )

        let window = try XCTUnwrap(AskCalendarWindow.day(offset: 2, now: now, calendar: calendar))
        let line = "\(window.title) · Lunch · 1:00 PM"
        let model = RecordingModel()
        model.replyText = "I cannot see your location. You have 6 open reminders."
        model.readings = reminders + place + [AskAppleReading(name: "calendar", lines: [line])]
        let assistant = try assistant(
            model: model,
            access: [.calendar, .reminders, .location],
            spoken: "I can answer from the tools that are on.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(utterance: asked)
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.pages.first?.card?.title, "Calendar")
        XCTAssertEqual(result.pages.first?.text, line)
        XCTAssertFalse(result.pages.first?.text.contains("reminder") == true)
    }

    func testEachMatchingContactIsItsOwnCard() async throws {
        let lines = [
            "April Miller · +18438109915",
            "April · (773) 407-9921",
            "Aprill Davis · 414-955-8828",
            "Brandon · 8434429128",
            "Aprill Dawson"
        ]
        XCTAssertEqual(
            AskContactLine.filtered(lines, query: "april").map { AskContactLine.person(from: $0).name },
            ["April Miller", "April", "Aprill Davis", "Aprill Dawson"]
        )
        XCTAssertFalse(AskContactLine.matches(name: "Brandon", query: "april"))
        XCTAssertTrue(AskContactLine.matches(name: "Aprill Davis", query: "April Davis"))
        XCTAssertFalse(AskContactLine.matches(name: "Aprill Dawson", query: "April Davis"))
        XCTAssertEqual(AskContactQuery.name(in: "How many contacts name april do I have?"), "april")
        XCTAssertEqual(AskContactQuery.name(in: "Contacts that begin with Mo"), "Mo")
        XCTAssertEqual(AskContactQuery.name(in: "contacts starting with m"), "m")
        XCTAssertTrue(AskContactQuery.asksPrefix("Contacts that begin with Mo"))
        XCTAssertFalse(AskContactQuery.asksPrefix("How many contacts name april do I have?"))
        XCTAssertTrue(AskContactLine.matches(name: "Morgan Lee", query: "Mo", prefix: true))
        XCTAssertTrue(AskContactLine.matches(name: "Molly", query: "Mo", prefix: true))
        XCTAssertFalse(AskContactLine.matches(name: "Sam", query: "Mo", prefix: true))
        XCTAssertFalse(AskContactLine.matches(name: "Morgan Lee", query: "Mo"))
        XCTAssertEqual(
            AskContactLine.filtered(
                ["Morgan Lee · 555", "Molly · 444", "Sam · 333"],
                query: "Mo",
                prefix: true
            ).map { AskContactLine.person(from: $0).name },
            ["Morgan Lee", "Molly"]
        )
        let prefixMiss = AskAppleRepair.plan(
            question: "Contacts that begin with Mo",
            readings: [],
            toolNames: ["contacts"]
        )
        XCTAssertEqual(prefixMiss.contactQuery, "Mo")
        XCTAssertTrue(prefixMiss.contactPrefix)
        XCTAssertTrue(prefixMiss.rereadContact)
        XCTAssertEqual(
            AskContactLine.speech(
                "I cannot see your calendar.",
                question: "Contacts that begin with Mo",
                readings: [
                    AskAppleReading(name: "contacts", lines: [
                        "Morgan Lee · 555",
                        "Molly · 444"
                    ])
                ]
            ),
            "You have 2 contacts that begin with Mo."
        )
        XCTAssertEqual(
            AskContactLine.line(name: "Aprill Davis", phone: "414-955-8828", email: "april.davis@example.com"),
            "Aprill Davis · 414-955-8828 · april.davis@example.com"
        )
        let split = AskAppleCards.sources([AskAppleReading(name: "contacts", lines: Array(lines.prefix(3)))])
        XCTAssertEqual(split.count, 3)
        XCTAssertEqual(split.map(\.lines), [["April Miller · +18438109915"], ["April · (773) 407-9921"], ["Aprill Davis · 414-955-8828"]])

        let model = RecordingModel()
        model.replyText = "You have 3 contacts named April."
        model.readings = [AskAppleReading(name: "contacts", lines: lines)]
        let assistant = try assistant(
            model: model,
            access: [.contacts],
            spoken: "I can answer from the tools that are on.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let asked = "How many contacts name april do I have?"
        let result = await assistant.handle(utterance: asked)
        XCTAssertEqual(result.pages.count, 4)
        XCTAssertEqual(result.pages.map { $0.card?.title }, ["April Miller", "April", "Aprill Davis", "Aprill Dawson"])
        XCTAssertEqual(result.pages[0].text, "You have 4 contacts named April.")
        XCTAssertEqual(result.pages[1].text, "")
        XCTAssertEqual(result.pages[1].spoken, "")
        XCTAssertEqual(result.pages[2].card?.shareText, "Aprill Davis · 414-955-8828")
        XCTAssertNil(result.followUp)
    }

    func testAnEmailQuestionStatesTheEmail() async throws {
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("What's April Davis email?"))
        XCTAssertEqual(AskContactQuery.name(in: "What's April Davis email?"), "April Davis")
        XCTAssertEqual(AskContactQuery.name(in: "What's April Davis's email?"), "April Davis")
        let line = "Aprill Davis · 414-955-8828 · april.davis@example.com"
        let plan = AskAppleRepair.plan(
            question: "What's April Davis email?",
            readings: [AskAppleReading(name: "contacts", lines: [line])],
            toolNames: ["contacts", "location", "reminders"],
            lookupPlaces: true
        )
        XCTAssertEqual(plan.keep, ["contacts"])
        XCTAssertEqual(plan.contactQuery, "April Davis")
        XCTAssertFalse(plan.rereadContact)
        let missing = AskAppleRepair.plan(
            question: "What's April Davis email?",
            readings: [AskAppleReading(name: "contacts", lines: ["Aprill Davis · 414-955-8828"])],
            toolNames: ["contacts"],
            lookupPlaces: true
        )
        XCTAssertTrue(missing.rereadContact)
        XCTAssertEqual(
            AskContactLine.speech(
                "You are at 7601 E Ben White Boulevard Frontage Rd, Austin.",
                question: "What's April Davis email?",
                readings: [AskAppleReading(name: "contacts", lines: [line])]
            ),
            "Aprill Davis's email is april.davis@example.com."
        )

        let model = RecordingModel()
        model.replyText = "You are at 7601 E Ben White Boulevard Frontage Rd, Austin. You have 8 open reminders."
        model.readings = [
            AskAppleReading(name: "location", lines: ["7601 E Ben White Boulevard Frontage Rd, Austin"]),
            AskAppleReading(name: "contacts", lines: [line])
        ]
        let assistant = try assistant(
            model: model,
            access: [.contacts, .location, .reminders],
            spoken: "I can answer from the tools that are on.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(utterance: "What's April Davis email?")
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.pages.first?.text, "Aprill Davis's email is april.davis@example.com.")
        XCTAssertEqual(result.pages.first?.card?.title, "Aprill Davis")
        XCTAssertEqual(result.pages.first?.card?.shareText, line)
    }

    func testAWeekOfStepsUsesTheWeeklyTotal() async throws {
        let joined = "How many steps have I done today?\nWhat about for the week?"
        XCTAssertEqual(AskHealthCatalog.span(in: joined), "week")
        XCTAssertEqual(AskHealthCatalog.span(in: "steps this weekend"), "today")
        XCTAssertEqual(AskHealthCatalog.kind(in: joined), "steps")
        let todayLine = [AskAppleReading(name: "health", lines: ["Steps: 5,626 steps"])]
        let reread = AskAppleRepair.plan(
            question: joined,
            readings: todayLine,
            toolNames: ["health", "calendar"],
            lookupPlaces: true
        )
        XCTAssertEqual(reread.keep, ["health"])
        XCTAssertEqual(reread.healthKind, "steps")
        XCTAssertEqual(reread.healthSpan, "week")
        XCTAssertNil(reread.calendarDay)
        let weekLine = "Steps: 40,000 steps this week"
        XCTAssertEqual(
            AskHealthCatalog.weekSpeech(
                "You've taken 5,626 steps today. The weekly total is not available.",
                question: joined,
                readings: [AskAppleReading(name: "health", lines: [weekLine])]
            ),
            "Steps: 40,000 steps this week."
        )

        let model = RecordingModel()
        model.replyText = "You've taken 5,626 steps today. The weekly total is not available."
        model.readings = [AskAppleReading(name: "health", lines: [weekLine])]
        let assistant = try assistant(
            model: model,
            access: [.health, .calendar],
            spoken: "I can answer from the tools that are on.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(
            utterance: "What about for the week?",
            priorUserQuestions: ["How many steps have I done today?"]
        )
        XCTAssertEqual(result.pages.first?.text, "Steps: 40,000 steps this week.")
        XCTAssertEqual(result.pages.first?.card?.title, "Health")
    }

    func testNearbyListsPlacesAroundYou() async throws {
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("What am I nearby?"))
        XCTAssertEqual(AskPlaceQuery.lookup(in: "What am I nearby?"), "nearby")
        XCTAssertEqual(AskPlaceQuery.lookup(in: "Where is Apple Park?"), "Apple Park")
        XCTAssertNil(AskPlaceQuery.lookup(in: "How many steps do I have today"))
        let cafe = AskLocationPin.line(label: "Radio Coffee", latitude: 30.25, longitude: -97.75)
        let park = AskLocationPin.line(label: "Boggy Creek", latitude: 30.26, longitude: -97.76)
        let health = [AskAppleReading(name: "health", lines: ["Steps: 5,626 steps"])]
        let places = [AskAppleReading(name: "location", lines: [cafe, park])]
        let covered = AskAppleRepair.plan(
            question: "What am I nearby?",
            readings: health + places,
            toolNames: ["location", "health"],
            lookupPlaces: true
        )
        XCTAssertEqual(covered.keep, ["location"])
        XCTAssertNil(covered.place)
        XCTAssertNil(covered.healthKind)
        let missed = AskAppleRepair.plan(
            question: "What am I nearby?",
            readings: health,
            toolNames: ["location", "health"],
            lookupPlaces: true
        )
        XCTAssertEqual(missed.place, "nearby")
        XCTAssertEqual(
            AskLocationPin.nearbySpeech(
                "You have taken 5,626 steps today.",
                question: "What am I nearby?",
                readings: places
            ),
            "You are near Radio Coffee and Boggy Creek."
        )

        let model = RecordingModel()
        model.replyText = "You have taken 5,626 steps today. The weekly total is not available."
        model.readings = health + places
        let assistant = try assistant(
            model: model,
            access: [.location, .health],
            spoken: "I can answer from the tools that are on.",
            facts: "No app facts. Only a tool result may be stated."
        )
        let result = await assistant.handle(utterance: "What am I nearby?")
        XCTAssertEqual(result.pages.count, 1)
        XCTAssertEqual(result.pages.first?.card?.title, "Location")
        XCTAssertEqual(result.pages.first?.text, "You are near Radio Coffee and Boggy Creek.")
        XCTAssertFalse(result.pages.first?.text.contains("steps") == true)
    }

    func testHealthChartFollowsTheMeasurementAndTheAskedRange() {
        for metric in AskHealthCatalog.Metric.allCases {
            let kind = AskHealthCatalog.chartKind(for: metric)
            if metric.latestSample || metric == .heart {
                XCTAssertEqual(kind, .line, metric.title)
            } else {
                XCTAssertEqual(kind, .bar, metric.title)
            }
        }
        XCTAssertEqual(AskHealthCatalog.span(in: "steps this month"), "month")
        XCTAssertEqual(AskHealthCatalog.span(in: "steps this year"), "year")
        XCTAssertEqual(AskHealthCatalog.span(in: "steps this weekend"), "today")
        XCTAssertEqual(AskHealthChartModel.range(in: "Steps: 5,626 steps"), .day)
        XCTAssertEqual(AskHealthChartModel.range(in: "Steps: 40,000 steps this week"), .week)
        XCTAssertEqual(AskHealthChartModel.range(in: "Steps: 120,000 steps this month"), .month)
        XCTAssertEqual(AskHealthChartModel.range(in: "Steps: 1,000,000 steps this year"), .year)
        let chart = AskHealthChartModel.parse([
            "Steps: 5,626 steps",
            "Heart rate: 72 beats per minute"
        ])
        XCTAssertEqual(chart?.metric, .steps)
        XCTAssertEqual(chart?.range, .day)
        XCTAssertNil(AskHealthChartModel.parse(["Not allowed."]))

        let opened = Date(timeIntervalSinceReferenceDate: 100)
        let earlier = AskHealthRangeChoice(range: .week, at: opened.addingTimeInterval(-1))
        XCTAssertEqual(AskHealthChartModel.displayed(initial: .day, choice: earlier, opened: opened), .day)
        XCTAssertNil(AskHealthChartModel.follows(choice: earlier, opened: opened, active: false))
        let later = AskHealthRangeChoice(range: .month, at: opened.addingTimeInterval(1))
        XCTAssertEqual(AskHealthChartModel.displayed(initial: .day, choice: later, opened: opened), .month)
        XCTAssertNil(AskHealthChartModel.follows(choice: later, opened: opened, active: false))
        XCTAssertEqual(AskHealthChartModel.snippetRange(initial: .day, choice: earlier), .week)
        XCTAssertEqual(AskHealthChartModel.snippetRange(initial: .day, choice: nil), .day)

        let ranges = AskHealthRanges()
        let cardID = UUID()
        let olderID = UUID()
        ranges.claim(metric: "steps", id: olderID, opened: opened.addingTimeInterval(-1))
        ranges.claim(metric: "steps", id: cardID, opened: opened)
        XCTAssertEqual(ranges.activeID(for: "steps"), cardID)
        ranges.claim(metric: "steps", id: olderID, opened: opened.addingTimeInterval(-1))
        XCTAssertEqual(ranges.activeID(for: "steps"), cardID)
        ranges.select(metric: "steps", range: .week)
        let choice = ranges.choices["steps"]
        XCTAssertEqual(choice?.range, .week)
        XCTAssertEqual(
            AskHealthChartModel.follows(choice: choice, opened: opened, active: true),
            .week
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16))!
        XCTAssertEqual(AskHealthBuckets.dates(range: .day, now: now, calendar: calendar).count, 24)
        XCTAssertEqual(AskHealthBuckets.dates(range: .week, now: now, calendar: calendar).count, 7)
        XCTAssertEqual(AskHealthBuckets.dates(range: .month, now: now, calendar: calendar).count, 8)
        XCTAssertEqual(AskHealthBuckets.dates(range: .year, now: now, calendar: calendar).count, 12)
        let week = AskHealthBuckets.dates(range: .week, now: now, calendar: calendar)
        XCTAssertEqual(week.first, calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)))
        XCTAssertEqual(week.last, calendar.date(from: DateComponents(year: 2026, month: 10, day: 8)))

        let monthPlan = AskAppleRepair.plan(
            question: "How many steps this month?",
            readings: [AskAppleReading(name: "health", lines: ["Steps: 5,626 steps"])],
            toolNames: ["health"]
        )
        XCTAssertEqual(monthPlan.healthKind, "steps")
        XCTAssertEqual(monthPlan.healthSpan, "month")
        let monthKept = AskAppleRepair.plan(
            question: "How many steps this month?",
            readings: [AskAppleReading(name: "health", lines: ["Steps: 120,000 steps this month"])],
            toolNames: ["health"]
        )
        XCTAssertNil(monthKept.healthKind)
        let weight = AskAppleRepair.plan(
            question: "What is my weight this month?",
            readings: [AskAppleReading(name: "health", lines: ["Weight: 180 pounds · Oct 8, 2026"])],
            toolNames: ["health"]
        )
        XCTAssertNil(weight.healthKind)
        XCTAssertEqual(
            AskHealthCatalog.weekSpeech(
                "The monthly total is not available.",
                question: "How many steps this month?",
                readings: [AskAppleReading(name: "health", lines: ["Steps: 120,000 steps this month"])]
            ),
            "Steps: 120,000 steps this month."
        )
        XCTAssertEqual(
            AskHealthCatalog.weekSpeech(
                "You have walked 120,000 steps this month.",
                question: "How many steps this month?",
                readings: [AskAppleReading(name: "health", lines: ["Steps: 120,000 steps this month"])]
            ),
            "You have walked 120,000 steps this month."
        )
        let lines = [
            AskHealthCatalog.summary(title: "Steps", value: "5,626 steps", span: "today"),
            AskHealthCatalog.summary(title: "Steps", value: "40,000 steps", span: "week"),
            AskHealthCatalog.summary(title: "Steps", value: "120,000 steps", span: "month"),
            AskHealthCatalog.summary(title: "Steps", value: "1,000,000 steps", span: "year"),
            AskHealthCatalog.headline(value: "5,626", unit: "steps", range: .day),
            AskHealthCatalog.headline(value: "40,000", unit: "steps", range: .week)
        ]
        XCTAssertEqual(lines[0], "Steps: 5,626 steps")
        XCTAssertEqual(lines[1], "Steps: 40,000 steps this week")
        XCTAssertTrue(lines.allSatisfy { !$0.contains("=") })
    }

    func testMusicAndWeatherCardsFollowTheQuestion() {
        XCTAssertEqual(AskAppleAccess.weather.rawValue, 1 << 6)
        XCTAssertEqual(AskMusicQuery.request(in: "what song is playing").kind, .now)
        XCTAssertEqual(AskMusicQuery.request(in: "what's playing").kind, .now)
        let album = AskMusicQuery.request(in: "find the album Abbey Road")
        XCTAssertEqual(album.kind, .album)
        XCTAssertEqual(album.term, "abbey road")
        let songs = AskMusicQuery.request(in: "songs by Taylor Swift")
        XCTAssertEqual(songs.kind, .song)
        XCTAssertEqual(songs.term, "taylor swift")
        XCTAssertEqual(AskMusicQuery.request(which: "album", query: "Midnights").kind, .album)
        XCTAssertEqual(AskMusicQuery.request(which: "now", query: "").kind, .now)
        let lastPlayed = AskMusicQuery.request(in: "What's my last played song?")
        XCTAssertEqual(lastPlayed.kind, .recent)
        XCTAssertEqual(lastPlayed.term, "")
        XCTAssertEqual(AskMusicQuery.request(which: "recent", query: nil).kind, .recent)

        let song = AskMusicLine.songLine(title: "Anti-Hero", artist: "Taylor Swift", album: "Midnights", duration: 201)
        let record = AskMusicLine.albumLine(title: "Abbey Road", artist: "The Beatles", songs: 17, year: "1969")
        XCTAssertEqual(song, "Song: Anti-Hero · Taylor Swift · Midnights · 3:21")
        let recent = AskMusicLine.recentLine(title: "Anti-Hero", artist: "Taylor Swift", album: "Midnights", duration: 201)
        XCTAssertEqual(recent, "Recent: Anti-Hero · Taylor Swift · Midnights · 3:21")
        XCTAssertEqual(AskMusicLine.spoken([recent]), "Last played was Anti-Hero by Taylor Swift.")
        XCTAssertTrue(AskMusicQuery.needsReread(lastPlayed, lines: [song]))
        XCTAssertFalse(AskMusicQuery.needsReread(lastPlayed, lines: [recent]))
        let musicCard = AskAppleCards.make(
            AskAppleReading(name: "music", lines: [song]),
            spoken: "You are currently listening to Anti-Hero by Taylor Swift.",
            custom: nil
        )
        XCTAssertEqual(musicCard.shareText, "Anti-Hero\nTaylor Swift\nMidnights\n3:21")
        XCTAssertFalse(musicCard.shareText.localizedCaseInsensitiveContains("currently"))
        XCTAssertEqual(record, "Album: Abbey Road · The Beatles · 17 songs · 1969")
        XCTAssertFalse(song.contains("="))
        XCTAssertFalse(record.contains("="))
        XCTAssertEqual(AskMusicLine.item(from: song)?.title, "Anti-Hero")
        XCTAssertEqual(AskMusicLine.item(from: record)?.kind, .album)
        XCTAssertEqual(AskMusicLine.item(from: record)?.extra, "1969")
        XCTAssertNil(AskMusicLine.item(from: "Not allowed."))
        XCTAssertNil(AskMusicLine.item(from: "Nothing is playing."))
        let musicCards = AskAppleCards.sources([
            AskAppleReading(name: "music", lines: [song, record, "Song: Daylight · Taylor Swift · Lover · 4:53"])
        ])
        XCTAssertEqual(musicCards.count, 3)
        XCTAssertEqual(
            AskAppleCards.make(AskAppleReading(name: "music", lines: [record]), spoken: "Abbey Road.", custom: nil).title,
            "Abbey Road"
        )
        XCTAssertEqual(
            AskAppleCards.make(AskAppleReading(name: "music", lines: ["Not allowed."]), spoken: "I can't see that.", custom: nil).title,
            "Music"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16))!
        let hourly = AskWeatherQuery.request(in: "hourly forecast", now: now, calendar: calendar)
        XCTAssertEqual(hourly.span, .hourly)
        XCTAssertEqual(hourly.dayOffset, 0)
        XCTAssertEqual(hourly.dayCount, 1)
        let hours = AskWeatherQuery.interval(for: hourly, now: now, calendar: calendar)
        XCTAssertEqual(hours?.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16)))
        XCTAssertEqual(hours?.end, calendar.date(from: DateComponents(year: 2026, month: 10, day: 9)))
        let daily = AskWeatherQuery.request(in: "daily forecast", now: now, calendar: calendar)
        XCTAssertEqual(daily.span, .daily)
        XCTAssertEqual(daily.dayCount, 7)
        XCTAssertEqual(daily.place, "")
        let dailyWindow = AskWeatherQuery.interval(for: daily, now: now, calendar: calendar)
        XCTAssertEqual(dailyWindow?.start, now)
        let brookfield = AskWeatherQuery.request(in: "What's the weather in Brookfield", now: now, calendar: calendar)
        XCTAssertEqual(brookfield.place, "brookfield")
        XCTAssertEqual(brookfield.span, .daily)
        XCTAssertEqual(AskWeatherQuery.request(in: "weather for Saturday", now: now, calendar: calendar).place, "")
        XCTAssertEqual(AskWeatherQuery.place(in: "will it rain in Chicago"), "chicago")
        let saturday = AskWeatherQuery.request(in: "weather on Saturday", now: now, calendar: calendar)
        XCTAssertEqual(saturday.span, .daily)
        XCTAssertEqual(saturday.dayOffset, 2)
        XCTAssertEqual(saturday.dayCount, 1)
        let tomorrowHours = AskWeatherQuery.request(in: "hourly forecast tomorrow", now: now, calendar: calendar)
        XCTAssertEqual(tomorrowHours.span, .hourly)
        XCTAssertEqual(tomorrowHours.dayOffset, 1)

        let day = AskWeatherLine.dayLine(
            title: "Thu, Oct 8",
            symbol: "cloud.sun.fill",
            condition: "Partly cloudy",
            high: "72 F",
            low: "55 F",
            rain: "20 percent"
        )
        let hour = AskWeatherLine.hourLine(
            time: "4 PM",
            symbol: "cloud.sun.fill",
            condition: "Partly cloudy",
            temperature: "70 F",
            rain: "10 percent"
        )
        XCTAssertFalse(day.contains("="))
        XCTAssertFalse(hour.contains("="))
        XCTAssertEqual(AskWeatherLine.day(from: day)?.high, "72 F")
        XCTAssertEqual(AskWeatherLine.hour(from: hour)?.temperature, "70 F")
        let days = (1...3).map { index in
            AskWeatherLine.dayLine(
                title: "Day \(index)",
                symbol: "cloud",
                condition: "Clear",
                high: "70 F",
                low: "50 F",
                rain: "0 percent"
            )
        }
        XCTAssertEqual(AskAppleCards.sources([AskAppleReading(name: "weather", lines: days)]).count, 3)
        XCTAssertEqual(AskAppleCards.sources([AskAppleReading(name: "weather", lines: [day, hour])]).count, 1)
        let weatherCard = AskAppleCards.make(
            AskAppleReading(name: "weather", lines: [day, hour]),
            spoken: "I cannot see the weather for Brookfield, WI.",
            custom: nil
        )
        XCTAssertEqual(weatherCard.title, "Thu, Oct 8")
        XCTAssertTrue(weatherCard.shareText.contains("Partly cloudy"))
        XCTAssertTrue(weatherCard.shareText.contains("72 F"))
        XCTAssertFalse(weatherCard.shareText.localizedCaseInsensitiveContains("cannot see"))
        let deniedWeather = AskAppleCards.make(
            AskAppleReading(name: "weather", lines: ["Weather isn't available."]),
            spoken: "I cannot see the weather for Brookfield, WI.",
            custom: nil
        )
        XCTAssertEqual(deniedWeather.shareText, "Weather isn't available.")
        XCTAssertEqual(
            AskWeatherLine.spoken([day, days[0], days[1]]),
            "3 day forecast. Thu, Oct 8 is Partly cloudy. High 72 F."
        )
        XCTAssertFalse(AskWeatherLine.spoken([day, hour])?.contains("=") == true)

        XCTAssertEqual(AskSourceFocus.named(in: "what's my temperature"), Set(["health"]))
        XCTAssertEqual(AskSourceFocus.named(in: "what's the temperature outside"), Set(["weather"]))
        XCTAssertEqual(AskSourceFocus.named(in: "will it rain"), Set(["weather"]))
        XCTAssertEqual(AskSourceFocus.named(in: "what song is playing"), Set(["music"]))
        XCTAssertFalse(AskSourceFocus.named(in: "what's the weather").contains("health"))

        let missingForecast = AskAppleRepair.plan(
            question: "What's the hourly forecast?",
            readings: [],
            toolNames: ["weather"],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(missingForecast.weather?.span, .hourly)
        XCTAssertNil(missingForecast.healthKind)
        let coveredForecast = AskAppleRepair.plan(
            question: "What's the hourly forecast?",
            readings: [AskAppleReading(name: "weather", lines: [day, hour])],
            toolNames: ["weather"],
            now: now,
            calendar: calendar
        )
        XCTAssertNil(coveredForecast.weather)
        let body = AskAppleRepair.plan(
            question: "What's my temperature?",
            readings: [],
            toolNames: ["health", "weather"],
            now: now,
            calendar: calendar
        )
        XCTAssertNil(body.weather)
        XCTAssertEqual(body.keep, Set(["health"]))
        XCTAssertEqual(body.healthKind, "temperature")
        let outside = AskAppleRepair.plan(
            question: "What's the temperature outside?",
            readings: [],
            toolNames: ["health", "weather"],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(outside.keep, Set(["weather"]))
        XCTAssertNil(outside.healthKind)
        XCTAssertEqual(outside.weather?.span, .daily)
        let week = (0..<7).map { index in
            AskWeatherLine.dayLine(
                title: "Day \(index)",
                symbol: "cloud",
                condition: "Clear",
                high: "70 F",
                low: "50 F",
                rain: "0 percent"
            )
        }
        let namedPlace = AskAppleRepair.plan(
            question: "What's the weather in Brookfield",
            readings: [AskAppleReading(name: "weather", lines: week)],
            toolNames: ["weather"],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(namedPlace.weather?.place, "brookfield")
        let placed = AskAppleRepair.plan(
            question: "What's the weather in Brookfield",
            readings: [AskAppleReading(name: "weather", lines: ["Place: brookfield"] + week)],
            toolNames: ["weather"],
            now: now,
            calendar: calendar
        )
        XCTAssertNil(placed.weather)
        let unavailable = AskAppleRepair.plan(
            question: "What's the weather in Brookfield",
            readings: [AskAppleReading(name: "weather", lines: ["Weather isn't available."])],
            toolNames: ["weather"],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(unavailable.weather?.place, "brookfield")

        let missingAlbum = AskAppleRepair.plan(
            question: "Find the album Abbey Road",
            readings: [],
            toolNames: ["music"]
        )
        XCTAssertEqual(missingAlbum.music?.kind, .album)
        XCTAssertEqual(missingAlbum.music?.term, "abbey road")
        let recentInstead = AskAppleRepair.plan(
            question: "What's my last played song?",
            readings: [AskAppleReading(name: "music", lines: [song])],
            toolNames: ["music"]
        )
        XCTAssertEqual(recentInstead.music?.kind, .recent)
        let foundAlbum = AskAppleRepair.plan(
            question: "Find the album Abbey Road",
            readings: [AskAppleReading(name: "music", lines: [record])],
            toolNames: ["music"]
        )
        XCTAssertNil(foundAlbum.music)
        XCTAssertFalse(AskMusicQuery.needsReread(AskMusicQuery.request(in: "what is playing"), lines: ["Not allowed."]))

        let defaults = isolatedDefaults()
        let allowed: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music, .weather]
        AskAppleSelection.rememberIfNeeded(allowed, allowed: allowed, for: "Ask Seed", defaults: defaults)
        let seeded = AskAppleSelection.active(allowed: allowed, for: "Ask Seed", defaults: defaults)
        XCTAssertEqual(seeded, allowed)
        XCTAssertTrue(seeded.contains(.music))
        XCTAssertTrue(seeded.contains(.weather))
    }

    func testCardGallerySamplesCoverEachCard() {
        XCTAssertEqual(AskCardSamples.names.count, 18)
        XCTAssertEqual(AskAlarmLine.item(from: AskCardSamples.alarmLine)?.title, "Wake up")
        XCTAssertEqual(AskAlarmLine.item(from: AskCardSamples.alarmLine)?.symbol, "sunrise.fill")
        let alarmCard = AskAppleCards.make(
            AskAppleReading(name: "alarms", lines: [AskCardSamples.alarmLine]),
            spoken: "Wake up at 7:00 AM.",
            custom: nil
        )
        XCTAssertEqual(alarmCard.title, "Wake up")
        XCTAssertFalse(alarmCard.shareText.contains("="))
        XCTAssertTrue(AskCardSamples.lines.allSatisfy { !$0.contains("=") })
        XCTAssertEqual(AskMusicLine.item(from: AskCardSamples.songLine)?.title, "Anti-Hero")
        XCTAssertEqual(AskMusicLine.item(from: AskCardSamples.albumLine)?.kind, .album)
        let forecast = AskWeatherLine.forecast(from: AskCardSamples.hourlyLines)
        XCTAssertEqual(forecast?.day.title, "Thu, Oct 8")
        XCTAssertEqual(forecast?.hours.count, 4)
        XCTAssertEqual(AskWeatherLine.forecast(from: [AskCardSamples.dayLine])?.hours.count, 0)
        XCTAssertEqual(AskReminderItem.tasks(in: AskCardSamples.reminderLines).map(\.id), [
            "askkit.sample.reminder.open",
            AskCardSamples.reminderDoneID
        ])
        XCTAssertTrue(AskContactLine.person(from: AskCardSamples.contactLine).isPerson)
        XCTAssertEqual(AskLocationPin.places(in: AskCardSamples.nearbyLines).count, 3)

        let song = AskAppleCards.make(
            AskAppleReading(name: "music", lines: [AskCardSamples.songLine]),
            spoken: "Anti-Hero by Taylor Swift.",
            custom: nil
        )
        XCTAssertEqual(song.title, "Anti-Hero")
        let denied = AskAppleCards.make(
            AskAppleReading(name: "music", lines: ["Not allowed."]),
            spoken: "Not allowed.",
            custom: nil
        )
        XCTAssertEqual(denied.title, "Music")
        let day = AskAppleCards.make(
            AskAppleReading(name: "weather", lines: [AskCardSamples.dayLine]),
            spoken: "Thu, Oct 8 is Partly cloudy.",
            custom: nil
        )
        XCTAssertEqual(day.title, "Thu, Oct 8")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16))!
        let steps = AskCardSamples.healthSeries(metric: .steps, range: .day, now: now, calendar: calendar)
        XCTAssertEqual(steps.points.count, 24)
        XCTAssertFalse(steps.headline.contains("="))
        XCTAssertEqual(AskHealthCatalog.chartKind(for: .steps), .bar)
        let heart = AskCardSamples.healthSeries(metric: .heart, range: .day, now: now, calendar: calendar)
        XCTAssertTrue(heart.points.contains(where: \.recorded))
        XCTAssertEqual(AskHealthCatalog.chartKind(for: .heart), .line)
        XCTAssertEqual(AskCardSamples.sections().map(\.title), AskCardSamples.names)
    }

    func testSeveralAlarmsBecomeSeparateCards() {
        XCTAssertEqual(AskAppleAccess.alarms.rawValue, 1 << 7)
        XCTAssertEqual(AskAppleTools.make([.alarms]).map(\.name), ["alarms"])
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("Set an alarm for 7 and another for 8"))
        XCTAssertTrue(AskAppleCopy.questionNeedsATool("Wake me at 7"))
        XCTAssertEqual(AskSourceFocus.named(in: "Set an alarm for Saturday at 7"), ["alarms"])

        let parsed = AskAlarmCommand.parse([
            .init(title: "Wake up", hour: 7, minute: 0, day: nil, after: nil, repeats: "weekdays", label: "Garage", symbol: "sunrise.fill", action: "open"),
            .init(title: "Leave", hour: 8, minute: 30, day: 1, after: nil, repeats: nil, label: "Maps", symbol: "car.fill", action: "drive"),
            .init(title: "Tea", hour: nil, minute: nil, day: nil, after: 20, repeats: nil, label: nil, symbol: nil, action: nil)
        ])
        guard case .drafts(let drafts) = parsed else {
            XCTFail("Expected three alarms")
            return
        }
        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(AskAlarmCommand.schedule(for: drafts[0]), .relative(hour: 7, minute: 0, repeats: .weekdays))
        XCTAssertEqual(AskAlarmCommand.schedule(for: drafts[1]), .fixed(day: 1, hour: 8, minute: 30))
        XCTAssertEqual(AskAlarmCommand.schedule(for: drafts[2]), .timer(20))
        XCTAssertEqual(
            AskAlarmCommand.parse([.init(title: "Nope", hour: 25, minute: 0, day: nil, after: nil, repeats: nil, label: nil, symbol: nil, action: nil)]),
            .badTime
        )
        let extra = (0..<9).map {
            AskAlarmCommand.Field(title: "Alarm \($0)", hour: 6, minute: $0, day: nil, after: nil, repeats: nil, label: nil, symbol: nil, action: nil)
        }
        guard case .drafts(let capped) = AskAlarmCommand.parse(extra) else {
            XCTFail("Expected the first eight alarms")
            return
        }
        XCTAssertEqual(capped.count, 8)

        let custom = AskAlarmButtonPlan.choice(
            draft: drafts[0],
            registered: ("open", "Open", "arrow.up.forward.app")
        )
        XCTAssertEqual(custom, AskAlarmButtonChoice(label: "Garage", symbol: "sunrise.fill", actionID: "open"))
        XCTAssertNil(AskAlarmButtonPlan.choice(
            draft: AskAlarmDraft(title: "Wake up", hour: 7, label: "Garage", symbol: "sunrise.fill", actionID: "missing"),
            registered: nil
        ))
        XCTAssertEqual(
            AskAlarmButtonPlan.choice(draft: AskAlarmDraft(title: "Wake up", hour: 7, label: "Rise", symbol: "sunrise.fill"), registered: nil)?.actionID,
            "open"
        )
        XCTAssertNil(AskAlarmText.symbol("sunrise fill"))
        XCTAssertNil(AskAlarmText.symbol("a=b"))

        AskAlarms.register(AskAlarmAction(id: "Drive", label: "Maps", symbol: "car.fill") { id, _ in
            AskAlarmOpenIntent(alarmID: id.uuidString)
        })
        XCTAssertEqual(AskAlarms.action(id: "drive")?.symbol, "car.fill")
        XCTAssertNotNil(AskAlarmRead.configuration(for: drafts[0], id: UUID()))
        XCTAssertNotNil(AskAlarmRead.configuration(for: drafts[2], id: UUID()))
        XCTAssertNil(AskAlarmRead.configuration(for: AskAlarmDraft(title: "Nope"), id: UUID()))

        let wake = AskAlarmLine.line(drafts[0])
        let leave = AskAlarmLine.line(drafts[1])
        XCTAssertFalse(wake.contains("="))
        XCTAssertFalse(leave.contains("="))
        XCTAssertEqual(AskAlarmLine.item(from: wake)?.label, "Garage")
        XCTAssertEqual(AskAlarmLine.spoken([wake, leave]), "Set 2 alarms: Wake up at 7:00 AM, Leave at 8:30 AM.")
        let sources = AskAppleCards.sources([
            AskAppleReading(name: "alarms", lines: [wake, leave, "Not allowed."])
        ])
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.map { AskAppleCards.make($0, spoken: "Set.", custom: nil).title }, ["Wake up", "Leave"])
        let denied = AskAppleCards.make(
            AskAppleReading(name: "alarms", lines: ["Not allowed."]),
            spoken: "Not allowed.",
            custom: nil
        )
        XCTAssertEqual(denied.title, "Alarm")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16))!
        let plan = AskAppleRepair.plan(
            question: "Set an alarm for Saturday at 7 and another for 8",
            readings: [AskAppleReading(name: "calendar", lines: ["Friday, Oct 9 · Nothing scheduled."])],
            toolNames: ["alarms", "calendar"],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(plan.keep, ["alarms"])
        XCTAssertNil(plan.calendarDay)

        let defaults = isolatedDefaults()
        let allowed: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music, .weather, .alarms]
        AskAppleSelection.rememberIfNeeded(allowed, allowed: allowed, for: "Ask Alarm Seed", defaults: defaults)
        let seeded = AskAppleSelection.active(allowed: allowed, for: "Ask Alarm Seed", defaults: defaults)
        XCTAssertEqual(seeded, allowed)
        XCTAssertTrue(seeded.contains(.alarms))
        XCTAssertTrue(seeded.contains(.music))
        XCTAssertTrue(seeded.contains(.weather))
    }

    func testASkippedReminderAndAlarmArePlannedWithoutFrameworks() {
        let question = "When is my next reminder and set an alarm for 10am"
        XCTAssertEqual(
            AskSpecialistClause.question(for: "reminders", in: question),
            "When is my next reminder"
        )
        XCTAssertEqual(
            AskSpecialistClause.question(for: "alarms", in: question),
            "set an alarm for 10am"
        )
        XCTAssertEqual(
            AskSpecialistClause.question(for: "weather", in: "Will it rain and what's the temperature outside"),
            "Will it rain and what's the temperature outside"
        )

        let reminders = AskAppleRepair.plan(
            question: "When is my next reminder",
            readings: [],
            toolNames: ["reminders"]
        )
        XCTAssertTrue(reminders.readReminders)
        XCTAssertTrue(reminders.alarmDrafts.isEmpty)
        let already = AskAppleRepair.plan(
            question: "When is my next reminder",
            readings: [AskAppleReading(name: "reminders", lines: ["No reminders."])],
            toolNames: ["reminders"]
        )
        XCTAssertFalse(already.readReminders)
        let adding = AskAppleRepair.plan(
            question: "Remind me to buy milk",
            readings: [],
            toolNames: ["reminders"]
        )
        XCTAssertFalse(adding.readReminders)

        let ten = AskAlarmCommand.drafts(in: "set an alarm for 10am")
        XCTAssertEqual(ten.count, 1)
        XCTAssertEqual(ten.first?.title, "Alarm")
        XCTAssertEqual(ten.first?.hour, 10)
        XCTAssertEqual(ten.first?.minute, 0)
        XCTAssertNil(ten.first?.day)
        XCTAssertEqual(AskAlarmLine.spoken(ten.map(AskAlarmLine.line)), "Alarm at 10:00 AM.")
        XCTAssertFalse(AskAlarmLine.line(ten[0]).contains("="))

        let afternoon = AskAlarmCommand.drafts(in: "set an alarm for 10:30 pm")
        XCTAssertEqual(afternoon.first?.hour, 22)
        XCTAssertEqual(afternoon.first?.minute, 30)
        XCTAssertEqual(AskAlarmCommand.drafts(in: "wake me at 7").first?.hour, 7)
        XCTAssertEqual(AskAlarmCommand.drafts(in: "set an alarm called Wake up for 10am").first?.title, "Wake up")
        XCTAssertEqual(AskAlarmCommand.drafts(in: "set a timer for 10 minutes").first?.afterMinutes, 10)
        XCTAssertNil(AskAlarmCommand.drafts(in: "set a timer for 10 minutes").first?.hour)
        XCTAssertTrue(AskAlarmCommand.drafts(in: "When is my next alarm").isEmpty)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16))!
        let saturday = AskAlarmCommand.drafts(
            in: "Set an alarm for Saturday at 7 and another for 8",
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(saturday.map(\.hour), [7, 8])
        XCTAssertEqual(saturday.map(\.day), [
            AskCalendarWindow.offset(namedIn: "Saturday", now: now, calendar: calendar),
            AskCalendarWindow.offset(namedIn: "Saturday", now: now, calendar: calendar)
        ])

        let alarms = AskAppleRepair.plan(question: question, readings: [], toolNames: ["alarms"])
        XCTAssertEqual(alarms.alarmDrafts.first?.hour, 10)
        XCTAssertFalse(alarms.readReminders)
        let keptAlarm = AskAppleRepair.plan(
            question: "set an alarm for 10am",
            readings: [AskAppleReading(name: "alarms", lines: [AskAlarmLine.line(ten[0])])],
            toolNames: ["alarms"]
        )
        XCTAssertTrue(keptAlarm.alarmDrafts.isEmpty)

        let line = AskReminderItem.line(title: "Buy milk", due: "Oct 10, 2026, 10:00 AM", id: "milk")
        let spoken = AskReminderItem.speech(
            "ignored",
            readings: [AskAppleReading(name: "reminders", lines: [line])],
            question: "When is my next reminder"
        )
        XCTAssertEqual(spoken, "Your next reminder is Buy milk, Oct 10, 2026, 10:00 AM.")
        XCTAssertFalse(spoken.contains("="))
        XCTAssertEqual(
            AskReminderItem.speech(
                "ignored",
                readings: [AskAppleReading(name: "reminders", lines: [line])],
                question: "What are my reminders"
            ),
            "You have 1 open reminder."
        )
    }

    func testAnExtraAlarmDoesNotHideTheOneThatWasSet() {
        let question = "Set alarm at 10am"
        let added = "Added 10am · 10:00 AM · once · Alarm · sunrise.fill"
        let failed = "Alarm isn't available."
        let midnight = AskAlarmLine.line(AskAlarmDraft(title: "Reminder", hour: 0, label: "Reminder"))
        XCTAssertEqual(AskAlarmLine.kept([failed, added], matching: question), [added])
        XCTAssertEqual(AskAlarmLine.kept([midnight, added], matching: question), [added])
        XCTAssertEqual(
            AskAlarmLine.speech(
                "Your alarm for 10am has been set. You cannot see the reminder.",
                readings: [AskAppleReading(name: "alarms", lines: [failed, added])],
                question: question
            ),
            "Alarm at 10:00 AM."
        )
        XCTAssertFalse(AskAlarmLine.speech("Set.", readings: [AskAppleReading(name: "alarms", lines: [added])], question: question).contains("="))
        XCTAssertEqual(
            AskAlarmLine.speech(
                "Your alarm for 10am has been set.",
                readings: [AskAppleReading(name: "alarms", lines: [failed])],
                question: question
            ),
            "Alarm isn't available."
        )
        XCTAssertEqual(
            AskAlarmLine.speech(
                "You are at the store.",
                readings: [
                    AskAppleReading(name: "location", lines: ["The store"]),
                    AskAppleReading(name: "alarms", lines: [added])
                ],
                question: question
            ),
            "You are at the store."
        )

        let sources = AskAppleCards.sources([
            AskAppleReading(name: "alarms", lines: [failed, added])
        ])
        XCTAssertEqual(sources.map(\.lines), [[added]])
        let card = AskAppleCards.make(sources[0], spoken: "Alarm at 10:00 AM.", custom: nil)
        XCTAssertEqual(card.title, "10am")
        let direct = AskAppleCards.make(
            AskAppleReading(name: "alarms", lines: [failed, added]),
            spoken: "Alarm at 10:00 AM.",
            custom: nil
        )
        XCTAssertEqual(direct.title, "10am")

        let asked = AskAlarmCommand.drafts(in: question)
        let chosen = AskAlarmCommand.matching([
            AskAlarmDraft(title: "Reminder", hour: 0, minute: 0),
            AskAlarmDraft(title: "10am", hour: 10, minute: 0)
        ], asked: asked)
        XCTAssertEqual(chosen.map(\.hour), [10])
        let mixed = AskAppleRepair.plan(
            question: question,
            readings: [AskAppleReading(name: "alarms", lines: [failed, added])],
            toolNames: ["alarms"]
        )
        XCTAssertTrue(mixed.alarmDrafts.isEmpty)
        XCTAssertFalse(mixed.alarmList)
        XCTAssertNil(mixed.alarmChange)
        XCTAssertNil(mixed.alarmRemoval)
    }

    func testAlarmQuestionsListChangeAndRepeatWithoutAlarmKit() {
        XCTAssertEqual(AskAlarmCommand.intent(in: "How many alarms do I have on?"), .list)
        XCTAssertEqual(AskAlarmCommand.intent(in: "When is my next alarm"), .list)
        XCTAssertEqual(AskAlarmCommand.intent(in: "set an alarm"), .needsTime)
        XCTAssertEqual(AskAlarmCommand.intent(in: ""), .none)
        XCTAssertEqual(
            AskAlarmLine.speech("I set it.", readings: [], question: "set an alarm"),
            "Say a time."
        )

        guard case .set(let daily) = AskAlarmCommand.intent(in: "make an alarm for 7 every day") else {
            XCTFail("Expected a new daily alarm")
            return
        }
        XCTAssertEqual(daily.first?.hour, 7)
        XCTAssertEqual(daily.first?.minute, 0)
        XCTAssertEqual(daily.first?.repeats, .daily)

        guard case .set(let ten) = AskAlarmCommand.intent(in: "set an alarm for 10am") else {
            XCTFail("Expected the 10am alarm")
            return
        }
        XCTAssertEqual(ten.first?.hour, 10)
        XCTAssertEqual(ten.first?.repeats, .never)

        guard case .change(let dailyChange) = AskAlarmCommand.intent(in: "make the 10am alarm daily") else {
            XCTFail("Expected to change the 10am alarm")
            return
        }
        XCTAssertEqual(dailyChange.matchHour, 10)
        XCTAssertEqual(dailyChange.matchMinute, 0)
        XCTAssertNil(dailyChange.hour)
        XCTAssertEqual(dailyChange.repeats, .daily)

        guard case .change(let moved) = AskAlarmCommand.intent(in: "change the 10am alarm to 7") else {
            XCTFail("Expected a new time")
            return
        }
        XCTAssertEqual(moved.matchHour, 10)
        XCTAssertEqual(moved.matchMinute, 0)
        XCTAssertEqual(moved.hour, 7)
        XCTAssertEqual(moved.minute, 0)
        XCTAssertNil(moved.repeats)

        guard case .change(let destination) = AskAlarmCommand.intent(in: "move it to 7") else {
            XCTFail("Expected the destination time")
            return
        }
        XCTAssertNil(destination.matchHour)
        XCTAssertEqual(destination.hour, 7)
        XCTAssertEqual(destination.minute, 0)

        guard case .change(let recurring) = AskAlarmCommand.intent(in: "make my alarms recurring") else {
            XCTFail("Expected every alarm to become daily")
            return
        }
        XCTAssertNil(recurring.matchHour)
        XCTAssertNil(recurring.hour)
        XCTAssertEqual(recurring.repeats, .daily)

        guard case .remove(let one) = AskAlarmCommand.intent(in: "delete the 10am alarm") else {
            XCTFail("Expected to remove the 10am alarm")
            return
        }
        XCTAssertEqual(one.hour, 10)
        XCTAssertEqual(one.minute, 0)
        guard case .remove(let all) = AskAlarmCommand.intent(in: "delete my alarms") else {
            XCTFail("Expected to remove every alarm")
            return
        }
        XCTAssertNil(all.hour)

        XCTAssertTrue(AskAlarmCommand.matching([
            AskAlarmDraft(title: "Alarm", hour: 10, minute: 0)
        ], asked: []).isEmpty)
        let asked = AskAlarmCommand.drafts(in: "Set alarm at 10am")
        XCTAssertEqual(
            AskAlarmCommand.matching([
                AskAlarmDraft(title: "Reminder", hour: 0, minute: 0),
                AskAlarmDraft(title: "Alarm", hour: 10, minute: 0)
            ], asked: asked).map(\.hour),
            [10]
        )

        let once = Alarm.Schedule.relative(.init(time: .init(hour: 10, minute: 0), repeats: .never))
        XCTAssertEqual(
            AskAlarmList.row(schedule: once, countdown: nil, state: .scheduled),
            "10:00 AM · once · on"
        )
        let everyDay = Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 0),
            repeats: .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
        ))
        XCTAssertEqual(
            AskAlarmList.row(schedule: everyDay, countdown: nil, state: .scheduled),
            "7:00 AM · daily · on"
        )
        let weekdays = Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 0),
            repeats: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday])
        ))
        XCTAssertEqual(
            AskAlarmList.row(schedule: weekdays, countdown: nil, state: .scheduled),
            "7:00 AM · weekdays · on"
        )
        let monday = Alarm.Schedule.relative(.init(
            time: .init(hour: 7, minute: 0),
            repeats: .weekly([.monday])
        ))
        XCTAssertEqual(
            AskAlarmList.row(schedule: monday, countdown: nil, state: .alerting),
            "7:00 AM · Mondays · on"
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let date = calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026, month: 10, day: 10, hour: 10, minute: 15
        ))!
        XCTAssertEqual(
            AskAlarmList.row(schedule: .fixed(date), countdown: nil, state: .scheduled, calendar: calendar),
            "10:15 AM · once · on"
        )
        XCTAssertEqual(
            AskAlarmList.row(schedule: nil, countdown: 600, state: .countdown),
            "in 10 minutes · once · on"
        )
        XCTAssertEqual(
            AskAlarmList.row(schedule: once, countdown: nil, state: .paused),
            "10:00 AM · once · paused"
        )
        XCTAssertEqual(AskAlarmList.spoken(lines: ["10:00 AM · once · on"]), "You have 1 alarm on, at 10:00 AM.")
        XCTAssertEqual(AskAlarmList.spoken(lines: ["10:00 AM · daily · on"]), "You have 1 alarm on, at 10:00 AM, daily.")
        XCTAssertEqual(AskAlarmList.spoken(lines: ["in 10 minutes · once · on"]), "You have 1 alarm on, in 10 minutes.")
        XCTAssertEqual(AskAlarmList.spoken(lines: ["No alarms."]), "You have no alarms on.")
        XCTAssertFalse(AskAlarmList.spoken(lines: ["in 10 minutes · once · on"])?.contains("at in") ?? true)

        let count = "How many alarms do I have on?"
        let added = "Added Alarm · 10:00 AM · once · Alarm · sunrise.fill"
        XCTAssertEqual(AskAlarmLine.kept([added], matching: count), [])
        let counted = AskAlarmLine.speech(
            "An alarm was set for 10:00 AM.",
            readings: [AskAppleReading(name: "alarms", lines: [added])],
            question: count
        )
        XCTAssertEqual(counted, "You have no alarms on.")
        XCTAssertFalse(counted.contains("Alarm at 10:00 AM"))
        XCTAssertEqual(
            AskAlarmLine.speech(
                "An alarm was set for 10:00 AM.",
                readings: [AskAppleReading(name: "alarms", lines: ["10:00 AM · once · on"])],
                question: count
            ),
            "You have 1 alarm on, at 10:00 AM."
        )
        let listed = AskAppleCards.sources([
            AskAppleReading(name: "alarms", lines: ["7:00 AM · daily · on", "8:00 AM · once · on"])
        ])
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed.map { AskAppleCards.make($0, spoken: "Two.", custom: nil).title }, ["Alarm", "Alarm"])

        let updated = "Updated Alarm · 7:00 AM · daily"
        XCTAssertEqual(AskAlarmLine.item(from: updated)?.title, "Alarm")
        XCTAssertEqual(AskAlarmLine.item(from: updated)?.time, "7:00 AM")
        XCTAssertEqual(AskAlarmLine.item(from: updated)?.repeats, "daily")
        XCTAssertEqual(
            AskAlarmLine.speech(
                "Done.",
                readings: [AskAppleReading(name: "alarms", lines: [updated])],
                question: "make the 10am alarm daily"
            ),
            "Alarm at 7:00 AM, daily."
        )
        let edited = AskAppleCards.make(
            AskAppleReading(name: "alarms", lines: [updated]),
            spoken: "Alarm at 7:00 AM, daily.",
            custom: nil
        )
        XCTAssertEqual(edited.title, "Alarm")
        XCTAssertTrue(edited.shareText.contains("7:00 AM"))
        XCTAssertTrue(edited.shareText.contains("daily"))
        XCTAssertEqual(
            AskAlarmLine.speech(
                "Done.",
                readings: [AskAppleReading(name: "alarms", lines: ["Removed 10:00 AM"])],
                question: "delete the 10am alarm"
            ),
            "Removed the 10:00 AM alarm."
        )
        XCTAssertEqual(
            AskAlarmLine.speech(
                "Done.",
                readings: [AskAppleReading(name: "alarms", lines: ["Removed 7:00 AM", "Removed 8:00 AM"])],
                question: "delete my alarms"
            ),
            "Removed 2 alarms."
        )

        let emptyCount = AskAppleRepair.plan(question: count, readings: [], toolNames: ["alarms"])
        XCTAssertTrue(emptyCount.alarmList)
        XCTAssertTrue(emptyCount.alarmDrafts.isEmpty)
        let addedCount = AskAppleRepair.plan(
            question: count,
            readings: [AskAppleReading(name: "alarms", lines: [added])],
            toolNames: ["alarms"]
        )
        XCTAssertTrue(addedCount.alarmList)
        XCTAssertTrue(addedCount.alarmDrafts.isEmpty)
        let next = AskAppleRepair.plan(question: "When is my next alarm", readings: [], toolNames: ["alarms"])
        XCTAssertTrue(next.alarmList)
        XCTAssertTrue(next.alarmDrafts.isEmpty)
        XCTAssertEqual(
            AskAppleRepair.plan(question: "make the 10am alarm daily", readings: [], toolNames: ["alarms"]).alarmChange,
            AskAlarmChange(matchHour: 10, matchMinute: 0, repeats: .daily)
        )
        XCTAssertTrue(
            AskAppleRepair.plan(question: "make the 10am alarm daily", readings: [], toolNames: ["alarms"]).alarmDrafts.isEmpty
        )
        XCTAssertEqual(
            AskAppleRepair.plan(question: "change the 10am alarm to 7", readings: [], toolNames: ["alarms"]).alarmChange,
            AskAlarmChange(matchHour: 10, matchMinute: 0, hour: 7, minute: 0)
        )
        XCTAssertEqual(
            AskAppleRepair.plan(question: "delete the 10am alarm", readings: [], toolNames: ["alarms"]).alarmRemoval,
            AskAlarmRemoval(hour: 10, minute: 0)
        )
        let setting = AskAppleRepair.plan(question: "set an alarm for 10am", readings: [], toolNames: ["alarms"])
        XCTAssertEqual(setting.alarmDrafts.first?.hour, 10)
        XCTAssertFalse(setting.alarmList)
        XCTAssertNil(setting.alarmChange)
        XCTAssertNil(setting.alarmRemoval)
        var saturdayCalendar = Calendar(identifier: .gregorian)
        saturdayCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        saturdayCalendar.locale = Locale(identifier: "en_US_POSIX")
        let saturdayNow = saturdayCalendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16))!
        XCTAssertEqual(
            AskAlarmCommand.drafts(in: "Set an alarm for Saturday at 7", now: saturdayNow, calendar: saturdayCalendar).first?.repeats,
            .never
        )
    }

    func testASchemaMissStillPlansTheStepsRead() {
        let question = "How many steps do I have today"
        let plan = AskAppleRepair.plan(question: question, readings: [], toolNames: ["health"])
        XCTAssertEqual(plan.healthKind, "steps")
        XCTAssertEqual(plan.healthSpan, "today")
        XCTAssertTrue(plan.alarmDrafts.isEmpty)
        XCTAssertFalse(plan.readReminders)

        let on = AskAppleAccess([.health, .location, .music, .weather, .alarms])
        XCTAssertNil(AskTurnSpecialists.closedSentence(question: question, access: on))
        XCTAssertEqual(
            AskTurnSpecialists.closedSentence(question: "What is on my calendar today", access: on),
            "Calendar is turned off."
        )
        XCTAssertEqual(
            AskTurnSpecialists.closedSentence(question: "What are my reminders", access: on),
            "Reminders are turned off."
        )
        XCTAssertNil(AskTurnSpecialists.closedSentence(question: "What is on my calendar today", access: [.calendar]))
        XCTAssertNil(AskTurnSpecialists.closedSentence(question: "Hello", access: []))
        XCTAssertEqual(
            AskTurnSpecialists.closedSentence(
                question: "Check my calendar and my reminders",
                access: []
            ),
            "Calendar and Reminders are turned off."
        )
    }

    func testAPageAddressBecomesAWebReading() {
        XCTAssertEqual(
            AskWebMetadata.url(in: "See https://example.com/docs.")?.absoluteString,
            "https://example.com/docs"
        )
        XCTAssertEqual(
            AskWebMetadata.url(in: "Also http://example.com/a")?.scheme,
            "http"
        )
        XCTAssertNil(AskWebMetadata.url(in: "What's on my calendar?"))
        XCTAssertNil(AskWebMetadata.url(in: "Look at file:///tmp/note.html"))
        XCTAssertFalse(AskWebMetadata.allowed(URL(string: "javascript:alert(1)")!))

        let html = """
        <html><head>
        <title>Ask Kit = Guide</title>
        <meta name="description" content="A page about tools = cards.">
        </head></html>
        """
        let text = AskWebMetadata.text(in: html)
        XCTAssertEqual(text.title, "Ask Kit Guide")
        XCTAssertEqual(text.summary, "A page about tools cards.")
        let lines = AskWebMetadata.lines(
            title: text.title,
            page: "https://example.com/a=b",
            summary: text.summary
        )
        XCTAssertFalse(lines.contains("="))
        XCTAssertTrue(lines.contains("Ask Kit Guide"))
        XCTAssertTrue(lines.contains("Page: https://example.com/a b"))
        XCTAssertEqual(AskWebMetadata.lines(title: "", page: "", summary: ""), AskWebMetadata.unread)

        XCTAssertEqual(AskSourceFocus.named(in: "Summarize https://example.com/docs"), ["web"])
        XCTAssertFalse(AskSourceFocus.named(in: "What's on my calendar?").contains("web"))
        XCTAssertEqual(
            AskSourceFocus.named(in: "What's the weather at https://example.com"),
            ["weather", "web"]
        )

        let web = AskSpecialistChoice(
            id: "web",
            title: "Web",
            workingTitle: "Reading the page",
            origin: .host
        )
        let page = AskTurnSpecialists.decide(
            question: "What is https://example.com/docs about?",
            skillID: "answer",
            facts: "No app facts. Only a tool result may be stated. A greeting needs no tool result.",
            allowsTools: true,
            hosts: [web],
            domainToolCount: 0,
            domainID: "open",
            domainTitle: "Anything",
            apple: [.calendar, .weather]
        )
        XCTAssertEqual(page.choices.map(\.id), ["web"])
        XCTAssertFalse(page.usesWriter)

        let chip = AskTurnSpecialists.decide(
            question: "What is https://example.com/docs about?",
            skillID: "answer",
            facts: "No app facts. Only a tool result may be stated.",
            allowsTools: false,
            hosts: [web],
            domainToolCount: 0,
            domainID: "open",
            domainTitle: "Anything",
            apple: [.calendar]
        )
        XCTAssertTrue(chip.usesWriter)
        XCTAssertTrue(chip.choices.isEmpty)
    }

    func testAPageQuestionLoadsTheWebToolWhenTheFlagIsOn() async throws {
        let on = RecordingModel()
        on.replyText = "Ask Kit"
        on.readings = [AskAppleReading(name: "web", lines: ["Ask Kit", "Page: https://example.com"])]
        let assistant = try assistant(
            model: on,
            access: [.calendar],
            name: "Ask Web",
            facts: "Only a tool result may be stated.",
            webMetadata: true
        )
        let result = await assistant.handle(utterance: "What is https://example.com about?")
        XCTAssertEqual(on.toolNames, [["web"]])
        XCTAssertEqual(on.requests.last?.profileID, "web")
        XCTAssertEqual(on.requests.last?.workingTitle, "Reading the page")
        XCTAssertEqual(result.pages.first?.card?.title, "Web")
        XCTAssertFalse(result.pages.first?.text.contains("=") ?? true)

        let off = RecordingModel()
        off.replyText = "Ask Kit"
        let quiet = try self.assistant(
            model: off,
            access: [.calendar],
            name: "Ask Web Off",
            facts: "Only a tool result may be stated."
        )
        _ = await quiet.handle(utterance: "What is https://example.com about?")
        XCTAssertEqual(off.toolNames, [])
        XCTAssertEqual(off.plainReplies, 1)
    }

    func testSpecialistsFollowTheQuestion() {
        let all: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music, .weather, .alarms]
        let weather = AskTurnSpecialists.decide(
            question: "What's the weather in Brookfield?",
            skillID: "answer",
            facts: "Only a tool result may be stated.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 0,
            domainID: "open",
            domainTitle: "Anything",
            apple: all
        )
        XCTAssertEqual(weather.choices.map(\.id), ["weather"])
        XCTAssertEqual(weather.choices.first?.workingTitle, "Checking the forecast")
        XCTAssertFalse(weather.capped)

        let temperature = AskTurnSpecialists.decide(
            question: "What's my temperature?",
            skillID: "answer",
            facts: "Only a tool result may be stated.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 0,
            domainID: "open",
            domainTitle: "Anything",
            apple: all
        )
        XCTAssertEqual(temperature.choices.map(\.id), ["health"])

        let both = AskTurnSpecialists.decide(
            question: "What's on my calendar and what's the weather?",
            skillID: "answer",
            facts: "Tomato pasta.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 0,
            domainID: "recipes",
            domainTitle: "Cooking",
            apple: all
        )
        XCTAssertEqual(both.choices.map(\.id), ["calendar", "weather"])
        XCTAssertEqual(both.choices.map(\.origin), [.apple, .apple])

        let friday = AskTurnSpecialists.decide(
            question: "What about Friday",
            skillID: "dinner",
            facts: "Only a tool result may be stated.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 0,
            domainID: "recipes",
            domainTitle: "Cooking",
            apple: [.calendar, .reminders]
        )
        XCTAssertEqual(friday.choices.map(\.id), ["calendar"])

        let four = AskTurnSpecialists.decide(
            question: "Check my calendar, reminders, contacts, and health steps",
            skillID: "answer",
            facts: "Only a tool result may be stated.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 0,
            domainID: "open",
            domainTitle: "Anything",
            apple: all
        )
        XCTAssertEqual(four.choices.map(\.id), ["calendar", "reminders", "contacts"])
        XCTAssertTrue(four.capped)

        let greeting = AskTurnSpecialists.decide(
            question: "Hello",
            skillID: "answer",
            facts: "No app facts. Only a tool result may be stated.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 0,
            domainID: "open",
            domainTitle: "Anything",
            apple: all
        )
        XCTAssertTrue(greeting.usesWriter)
        XCTAssertTrue(greeting.choices.isEmpty)

        let chip = AskTurnSpecialists.decide(
            question: "What's on my calendar?",
            skillID: "dinner",
            facts: "Tomato pasta.",
            allowsTools: false,
            hosts: [],
            domainToolCount: 0,
            domainID: "recipes",
            domainTitle: "Cooking",
            apple: [.calendar]
        )
        XCTAssertTrue(chip.usesWriter)
        XCTAssertTrue(chip.choices.isEmpty)

        let host = AskSpecialistChoice(id: "open.clock", title: "Clock", workingTitle: "Checking the time", origin: .host)
        let ordered = AskTurnSpecialists.decide(
            question: "What's the weather?",
            skillID: "answer",
            facts: "Only a tool result may be stated.",
            allowsTools: true,
            hosts: [host],
            domainToolCount: 0,
            domainID: "open",
            domainTitle: "Anything",
            apple: all
        )
        XCTAssertEqual(ordered.choices.map(\.id), ["open.clock", "weather"])

        let domain = AskTurnSpecialists.decide(
            question: "What's on my calendar?",
            skillID: "dinner",
            facts: "Tomato pasta.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 2,
            domainID: "recipes",
            domainTitle: "Cooking",
            apple: [.calendar]
        )
        XCTAssertEqual(domain.choices.map(\.origin), [.domain, .apple])
        XCTAssertEqual(domain.choices.map(\.id), ["app.recipes", "calendar"])

        let oversized = AskTurnSpecialists.decide(
            question: "What's on my calendar?",
            skillID: "dinner",
            facts: "Tomato pasta.",
            allowsTools: true,
            hosts: [],
            domainToolCount: 6,
            domainID: "recipes",
            domainTitle: "Cooking",
            apple: []
        )
        XCTAssertTrue(oversized.refusedToolCount)
        XCTAssertFalse(oversized.usesWriter)
        XCTAssertTrue(oversized.choices.isEmpty)

        let miss = AskTurnSpecialists.decide(
            question: "Who won the game?",
            skillID: AskAppleCopy.missSkillID,
            facts: AskAppleCopy.missFacts,
            allowsTools: true,
            hosts: [],
            domainToolCount: 0,
            domainID: "",
            domainTitle: "",
            apple: [.calendar]
        )
        XCTAssertTrue(miss.leavesMiss)
        XCTAssertFalse(miss.usesWriter)
    }

    func testAHostSpecialistRunsAheadOfApple() async throws {
        let model = RecordingModel()
        model.replyText = "It is 3:45 PM."
        let clock = AskSpecialist(
            id: "open.clock",
            title: "Clock",
            symbolName: "clock",
            workingTitle: "Checking the time",
            instructions: "Call the clock tool once.",
            tools: { [StubTool(name: "clock")] },
            matches: { question in
                question.localizedStandardContains("time")
            }
        )
        let assistant = try assistant(
            model: model,
            access: [.calendar, .weather],
            specialists: [clock]
        )
        let time = await assistant.handle(utterance: "What time is it?")
        XCTAssertEqual(model.toolNames, [["clock"]])
        XCTAssertEqual(time.pages.first?.text, "It is 3:45 PM.")

        model.replyText = "Dentist at 3."
        model.readings = [AskAppleReading(name: "calendar", lines: ["Dentist at 3"])]
        let calendar = await assistant.handle(utterance: "What's on my calendar?")
        XCTAssertEqual(model.toolNames, [["clock"], ["calendar"]])
        XCTAssertEqual(calendar.pages.first?.card?.title, "Calendar")
    }

    private func assistant(
        model: RecordingModel,
        access: AskAppleAccess,
        tools: (@MainActor (String) -> [any Tool])? = nil,
        specialists: [AskSpecialist] = [],
        appleCard: (@MainActor (String, [String]) -> AskIntentCard?)? = nil,
        name: String = "Ask Pantry",
        fastPath: (@MainActor (String) -> AskRoute?)? = { _ in AskRoute(skillID: "dinner") },
        spoken: String = "Pasta.",
        facts: String = "Tomato pasta.",
        webMetadata: Bool = false
    ) throws -> AskAssistant {
        try AskAssistant(
            AskConfiguration(
                assistantName: name,
                domains: [AskDomain(id: "recipes", summary: "Cooking", routingNotes: "Food.")],
                skills: [
                    AskSkill(
                        id: "dinner",
                        domainID: "recipes",
                        title: "Dinner",
                        summary: "Suggest dinner",
                        routingNotes: "Dinner.",
                        fulfillment: .reply { _ in
                            AskReply(text: spoken, spoken: spoken, facts: facts)
                        }
                    )
                ],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: fastPath,
                guide: AskGuide(replyInstructions: "Rewrite FACTS."),
                tools: tools,
                specialists: specialists,
                webMetadata: webMetadata,
                appleAccess: access,
                appleCard: appleCard
            ),
            model: model.client
        )
    }
}

private final class RecordingModel: @unchecked Sendable {
    var routeSkillID = "dinner"
    var replyText = ""
    var readings: [AskAppleReading] = []
    var toolCounts: [Int] = []
    var toolNames: [[String]] = []
    var plainReplies = 0
    var requests: [AskModelRequest] = []

    var client: AskModelClient {
        AskModelClient(
            routeDomain: { _ in "recipes" },
            routeSkill: { _ in AskModelSkillChoice(skillID: "dinner") },
            fillSlots: { _, _ in [:] },
            route: { [self] _ in AskModelSkillChoice(skillID: self.routeSkillID) },
            writeReply: { [self] request in
                self.plainReplies += 1
                self.requests.append(request)
                return self.replyText
            },
            writeReplyUsing: { [self] request, tools in
                self.toolCounts.append(tools.count)
                self.toolNames.append(tools.map(\.name))
                self.requests.append(request)
                return AskWrittenReply(text: self.replyText, readings: self.readings)
            }
        )
    }
}

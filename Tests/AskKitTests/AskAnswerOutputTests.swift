import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskAnswerOutputTests: XCTestCase {
    func testExportMapsPlaceContactReminderAndMusic() {
        let placeLine = AskLocationPin.line(label: "Apple Park, Cupertino", latitude: 37.3349, longitude: -122.0090)
        let contactLine = AskContactLine.line(name: "Ada Lovelace", phone: "555-0100", email: "ada@example.com")
        let reminderLine = AskReminderItem.line(title: "Pick up tires", due: "Thu", id: "reminder.1")
        let musicLine = AskMusicLine.songLine(title: "Anti-Hero", artist: "Taylor Swift", album: "Midnights", duration: 200)

        let turn = AskTurnResult(
            skillID: "ask.apple",
            domainID: "apple",
            slots: [:],
            usedModel: false,
            fulfillment: .reply(AskReply(text: "Here you go.", spoken: "Here you go.")),
            pages: [
                AskPage(
                    text: "Apple Park is nearby.",
                    spoken: "Apple Park is nearby.",
                    skillID: "ask.apple",
                    domainID: "apple",
                    appleReading: AskAppleReading(name: "location", lines: [placeLine])
                ),
                AskPage(
                    text: "Ada Lovelace.",
                    spoken: "Ada Lovelace.",
                    skillID: "ask.apple",
                    domainID: "apple",
                    appleReading: AskAppleReading(name: "contacts", lines: [contactLine])
                ),
                AskPage(
                    text: "1 open reminder.",
                    spoken: "1 open reminder.",
                    skillID: "ask.apple",
                    domainID: "apple",
                    appleReading: AskAppleReading(name: "reminders", lines: [reminderLine])
                ),
                AskPage(
                    text: "Anti-Hero.",
                    spoken: "Anti-Hero.",
                    skillID: "ask.apple",
                    domainID: "apple",
                    appleReading: AskAppleReading(name: "music", lines: [musicLine])
                )
            ]
        )

        let outputs = AskAnswerExport.outputs(from: turn)
        XCTAssertEqual(outputs.count, 4)

        guard case .place(let place) = outputs[0] else { return XCTFail("Expected place") }
        XCTAssertEqual(place.name, "Apple Park")
        XCTAssertEqual(place.latitude, 37.3349, accuracy: 0.0001)
        XCTAssertEqual(place.longitude, -122.0090, accuracy: 0.0001)

        guard case .contact(let contact) = outputs[1] else { return XCTFail("Expected contact") }
        XCTAssertEqual(contact.name, "Ada Lovelace")
        XCTAssertEqual(contact.phone, "555-0100")
        XCTAssertEqual(contact.email, "ada@example.com")

        guard case .reminder(let reminder) = outputs[2] else { return XCTFail("Expected reminder") }
        XCTAssertEqual(reminder.id, "reminder.1")
        XCTAssertEqual(reminder.title, "Pick up tires")

        guard case .music(let music) = outputs[3] else { return XCTFail("Expected music") }
        XCTAssertEqual(music.kind, .song)
        XCTAssertEqual(music.itemTitle, "Anti-Hero")
        XCTAssertEqual(music.artist, "Taylor Swift")
    }

    func testExportFallsBackToSpokenText() {
        let turn = AskTurnResult(
            skillID: "dinner",
            domainID: "recipes",
            slots: [:],
            usedModel: false,
            fulfillment: .reply(AskReply(text: "Pasta tonight.", spoken: "Pasta.")),
            pages: [
                AskPage(
                    text: "Pasta tonight.",
                    spoken: "Pasta.",
                    skillID: "dinner",
                    domainID: "recipes"
                )
            ]
        )

        let outputs = AskAnswerExport.outputs(from: turn)
        XCTAssertEqual(outputs, [.text("Pasta.")])
    }

    func testExportMapsPlaylistLines() {
        let line = AskMusicLine.playlistLine(title: "Chill Hits", curator: "Apple Music", songs: 40)
        let turn = AskTurnResult(
            skillID: "ask.apple",
            domainID: "apple",
            slots: [:],
            usedModel: false,
            fulfillment: .reply(AskReply(text: "Chill Hits.", spoken: "Chill Hits.")),
            pages: [
                AskPage(
                    text: "Chill Hits.",
                    spoken: "Chill Hits.",
                    skillID: "ask.apple",
                    domainID: "apple",
                    appleReading: AskAppleReading(name: "music", lines: [line])
                )
            ]
        )

        let outputs = AskAnswerExport.outputs(from: turn)
        guard case .music(let music) = outputs.first else { return XCTFail("Expected music") }
        XCTAssertEqual(music.kind, .playlist)
        XCTAssertEqual(music.itemTitle, "Chill Hits")
        XCTAssertEqual(music.artist, "Apple Music")
    }

    func testCalendarCommandParsesBirthdaysAndYesterdayOffset() {
        XCTAssertEqual(AskCalendarCommand.parse(action: "birthdays", day: 0, title: nil, hour: nil, minute: nil), .birthdays(0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 15))!
        XCTAssertEqual(AskCalendarWindow.offset(namedIn: "What was on my calendar yesterday", now: now, calendar: calendar), -1)
    }
}

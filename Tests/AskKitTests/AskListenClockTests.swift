import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskListenClockTests: XCTestCase {
    func testAChangedPartialResetsTheSilenceDeadline() {
        var clock = AskListenClock()
        let start = Date(timeIntervalSinceReferenceDate: 100)
        XCTAssertTrue(clock.note("What is", now: start))
        XCTAssertFalse(clock.note("What is", now: start.addingTimeInterval(1)))
        XCTAssertTrue(clock.note("What is next", now: start.addingTimeInterval(1)))
        let early = start.addingTimeInterval(1 + AskListenClock.silence - 0.01)
        XCTAssertEqual(clock.timeUntilCommit(now: early) ?? 0, 0.01, accuracy: 0.000_1)
        XCTAssertNil(clock.commitIfDue(now: early))
        XCTAssertEqual(clock.commitIfDue(now: start.addingTimeInterval(1 + AskListenClock.silence)), "What is next")
        XCTAssertNil(clock.timeUntilCommit(now: start.addingTimeInterval(20)))
        XCTAssertNil(clock.commitIfDue(now: start.addingTimeInterval(20)))
    }

    func testEmptySpeechDoesNotCommit() {
        var clock = AskListenClock()
        XCTAssertFalse(clock.note("   ", now: Date()))
        XCTAssertNil(clock.commitNow())
        XCTAssertNil(clock.commitIfDue(now: Date().addingTimeInterval(10)))
    }

    func testCancelDoesNotCommit() {
        var clock = AskListenClock()
        let now = Date()
        XCTAssertTrue(clock.note("Call home", now: now))
        clock.cancel()
        XCTAssertNil(clock.commitNow())
        XCTAssertNil(clock.commitIfDue(now: now.addingTimeInterval(AskListenClock.silence)))
        XCTAssertFalse(clock.note("Call home again", now: now))
    }

    func testVoiceEntryIsNotSiri() {
        XCTAssertEqual(AskTraceEntry.voice.rawValue, "voice")
        XCTAssertNotEqual(AskTraceEntry.voice, AskTraceEntry.siri)
        XCTAssertEqual(AskTraceFormatter.entryWords(.voice), "Voice")
        XCTAssertEqual(AskTraceFormatter.entrySymbol(.voice), "mic")
        XCTAssertEqual(AskTraceFormatter.entryWords(.siri), "Siri")
        let titles = AskTraceGuide.sections.flatMap(\.items).map(\.title)
        XCTAssertTrue(titles.contains("Voice"))
        XCTAssertTrue(titles.contains("Siri"))
    }
}

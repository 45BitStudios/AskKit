import AskKitIntents
import XCTest
@testable import AskKit

final class AskSurfaceTests: XCTestCase {
    func testTheBoardRoundTripsAndTheQueueIsTakenOnce() {
        let suite = "AskSurfaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AskSurfaceStore(defaults: defaults)
        let board = AskSurfaceBoard.sample
        store.save(board)
        XCTAssertEqual(store.load(), board)
        XCTAssertTrue(board.hasLoaded)

        store.enqueue("  What's on my calendar today?  ")
        store.requestPin()
        XCTAssertEqual(store.takeQuestion(), "What's on my calendar today?")
        XCTAssertNil(store.takeQuestion())
        XCTAssertTrue(store.consumePin())
        XCTAssertFalse(store.consumePin())
        let directions = AskSurfaceMaps.directionsURL(location: "Studio")
        XCTAssertEqual(directions?.host, "maps.apple.com")
        XCTAssertEqual(URLComponents(url: directions!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "Studio")
        XCTAssertNil(AskSurfaceMaps.directionsURL(location: "  "))
    }

    func testPinThisStaysOffTheModel() {
        XCTAssertTrue(AskPinPhrase.matches("Pin this"))
        XCTAssertTrue(AskPinPhrase.matches("  pin that! "))
        XCTAssertTrue(AskPinPhrase.matches("Keep this on the Lock Screen"))
        XCTAssertFalse(AskPinPhrase.matches("Pin this meeting on my calendar tomorrow"))
        XCTAssertEqual(AskPinPhrase.actionID, "ask.pin.next-event")
    }
}

import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskSendBubbleTransitionTests: XCTestCase {
    func testShouldMorphRequiresTextAndNoImages() {
        XCTAssertTrue(AskSendMorph.shouldMorph(text: "Hello", imageCount: 0, reduceMotion: false))
        XCTAssertFalse(AskSendMorph.shouldMorph(text: "Hello", imageCount: 1, reduceMotion: false))
        XCTAssertFalse(AskSendMorph.shouldMorph(text: "   ", imageCount: 0, reduceMotion: false))
        XCTAssertFalse(AskSendMorph.shouldMorph(text: "Hello", imageCount: 0, reduceMotion: true))
    }

    func testHidingPendingUserTurnDropsOnlyTheMatchingLatestUser() {
        struct Turn: Equatable {
            var role: String
            var text: String
        }
        let turns = [
            Turn(role: "user", text: "earlier"),
            Turn(role: "assistant", text: "ok"),
            Turn(role: "user", text: "Hello"),
        ]
        let hidden = AskSendMorph.hidingPendingUserTurn(
            turns,
            pendingText: "Hello",
            role: \.role,
            text: \.text
        )
        XCTAssertEqual(hidden, [
            Turn(role: "user", text: "earlier"),
            Turn(role: "assistant", text: "ok"),
        ])
    }

    func testHidingPendingUserTurnLeavesUnrelatedThreadsAlone() {
        struct Turn: Equatable {
            var role: String
            var text: String
        }
        let turns = [
            Turn(role: "user", text: "Hello"),
            Turn(role: "assistant", text: "ok"),
        ]
        let hidden = AskSendMorph.hidingPendingUserTurn(
            turns,
            pendingText: "Something else",
            role: \.role,
            text: \.text
        )
        XCTAssertEqual(hidden, turns)
        XCTAssertEqual(
            AskSendMorph.hidingPendingUserTurn(
                turns,
                pendingText: nil,
                role: \.role,
                text: \.text
            ),
            turns
        )
    }
}

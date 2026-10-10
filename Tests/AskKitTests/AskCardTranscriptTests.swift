import SwiftUI
import XCTest
@testable import AskKit

final class AskCardTranscriptTests: XCTestCase {
    func testMeridiemStaysOneSentence() {
        let sentences = AskCardTranscript.sentences(in: "Open 4:30 a.m. – 9:00 p.m. Bring a jacket.")
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0], "Open 4:30 a.m. – 9:00 p.m.")
        XCTAssertEqual(sentences[1], "Bring a jacket.")
    }

    func testCoveredPhraseDropsThatSentence() {
        let card = makeCard(text: "Gate B12 is down the hall. Bring a jacket.", covered: ["gate b12"])
        XCTAssertEqual(AskCardTranscript.bubble(card.text, card: card), "Bring a jacket.")
    }

    func testShortPhraseDoesNotDropASentence() {
        let card = makeCard(text: "ab is the code. Done.", covered: ["ab"])
        XCTAssertEqual(AskCardTranscript.bubble(card.text, card: card), "ab is the code. Done.")
    }

    func testNavigationDropsOnlyWhenTheCardHasAnAction() {
        let text = "The gate is B12. I can open the map."
        let withAction = makeCard(text: text, action: AskAction(id: "map", title: "Map"))
        XCTAssertEqual(AskCardTranscript.bubble(text, card: withAction), "The gate is B12.")
        let withoutAction = makeCard(text: text)
        XCTAssertEqual(AskCardTranscript.bubble(text, card: withoutAction), text)
    }

    func testStrippingEverySentenceRestoresTheOriginal() {
        let card = makeCard(text: "Gate B12.", covered: ["gate b12"])
        XCTAssertEqual(AskCardTranscript.bubble(card.text, card: card), "Gate B12.")
    }

    func testNavigationOnlyReplyIsHidden() {
        let card = makeCard(text: "I can open the map.", action: AskAction(id: "map", title: "Map"))
        XCTAssertNil(AskCardTranscript.bubble(card.text, card: card))
    }

    func testCardShareTextJoinsTheTitleAndSpokenLine() {
        let card = AskIntentCard(title: "Charge", spoken: "The battery is at 80 percent.", view: Text("80%"))
        XCTAssertEqual(card.shareText, "Charge\nThe battery is at 80 percent.")
        let named = AskIntentCard(title: "Charge", spoken: "Charge is at 80 percent.", view: Text("80%"))
        XCTAssertEqual(named.shareText, "Charge is at 80 percent.")
    }

    func testReplacesBubbleHidesTheText() {
        let card = makeCard(text: "You have 1000 miles.", replacesBubble: true)
        XCTAssertNil(AskCardTranscript.bubble(card.text, card: card))
    }

    private func makeCard(
        text: String,
        covered: [String] = [],
        replacesBubble: Bool = false,
        action: AskAction? = nil
    ) -> AskIntentCard {
        AskIntentCard(
            spoken: text,
            text: text,
            coveredPhrases: covered,
            replacesBubble: replacesBubble,
            action: action,
            view: Text("card")
        )
    }
}

import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskDictationTranscriptTests: XCTestCase {
    func testAPhraseGrowsWithoutDroppingWords() {
        var transcript = AskDictationTranscript()
        XCTAssertEqual(transcript.update(hypothesis: "testing", isFinal: false), "testing")
        XCTAssertEqual(transcript.update(hypothesis: "testing a cell", isFinal: false), "testing a cell")
    }

    func testAPauseAppendsTheNextPhrase() {
        var transcript = AskDictationTranscript()
        XCTAssertEqual(transcript.update(hypothesis: "testing a cell", isFinal: false), "testing a cell")
        XCTAssertEqual(transcript.update(hypothesis: "sound", isFinal: false), "testing a cell sound")
        XCTAssertEqual(transcript.update(hypothesis: "sound to do", isFinal: false), "testing a cell sound to do")
    }

    func testAFinalPhraseStaysWhenTheNextPhraseStarts() {
        var transcript = AskDictationTranscript()
        XCTAssertEqual(transcript.update(hypothesis: "testing a cell", isFinal: true), "testing a cell")
        XCTAssertEqual(transcript.update(hypothesis: "sound", isFinal: false), "testing a cell sound")
        XCTAssertEqual(transcript.update(hypothesis: "testing a cell sound", isFinal: true), "testing a cell sound")
    }

    func testAShorterRevisionDoesNotEraseThePhrase() {
        var transcript = AskDictationTranscript()
        XCTAssertEqual(transcript.update(hypothesis: "testing a cell", isFinal: false), "testing a cell")
        XCTAssertEqual(transcript.update(hypothesis: "testing", isFinal: false), "testing a cell")
    }

    func testALastWordCorrectionReplacesThatWord() {
        var transcript = AskDictationTranscript()
        XCTAssertEqual(transcript.update(hypothesis: "testing a cell", isFinal: false), "testing a cell")
        XCTAssertEqual(transcript.update(hypothesis: "testing a sell", isFinal: false), "testing a sell")
    }

    func testDictationAppendsToTextAlreadyInTheField() {
        var transcript = AskDictationTranscript(committed: "Buy milk")
        XCTAssertEqual(transcript.update(hypothesis: "and eggs", isFinal: false), "Buy milk and eggs")
        XCTAssertEqual(transcript.update(hypothesis: "today", isFinal: false), "Buy milk and eggs today")
    }
}
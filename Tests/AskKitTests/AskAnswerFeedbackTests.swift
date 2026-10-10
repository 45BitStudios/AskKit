import XCTest
@testable import AskKit

final class AskAnswerFeedbackTests: XCTestCase {
    private let question = UUID()
    private let answer = UUID()
    private let followUp = UUID()
    private let second = UUID()

    func testRowSitsOnTheLatestAnswer() {
        let turns = [
            AskFeedbackTurn(id: question, isUser: true, text: "Status?"),
            AskFeedbackTurn(id: answer, isUser: false, text: "On time.")
        ]
        XCTAssertEqual(AskFeedback.anchorID(in: turns), answer)
        XCTAssertEqual(AskFeedback.question(before: answer, in: turns), "Status?")
    }

    func testWaitingQuestionKeepsThePreviousAnswer() {
        let turns = [
            AskFeedbackTurn(id: question, isUser: true, text: "Status?"),
            AskFeedbackTurn(id: answer, isUser: false, text: "On time."),
            AskFeedbackTurn(id: followUp, isUser: true, text: "Gate?")
        ]
        XCTAssertEqual(AskFeedback.anchorID(in: turns), answer)
    }

    func testNewAnswerTakesTheRow() {
        let turns = [
            AskFeedbackTurn(id: question, isUser: true, text: "Status?"),
            AskFeedbackTurn(id: answer, isUser: false, text: "On time."),
            AskFeedbackTurn(id: followUp, isUser: true, text: "Gate?"),
            AskFeedbackTurn(id: second, isUser: false, text: "B11.")
        ]
        XCTAssertEqual(AskFeedback.anchorID(in: turns), second)
        XCTAssertEqual(AskFeedback.question(before: second, in: turns), "Gate?")
    }

    func testGreetingAndLoneQuestionHaveNoRow() {
        let greeting = UUID()
        XCTAssertNil(AskFeedback.anchorID(in: [
            AskFeedbackTurn(id: greeting, isUser: false, text: "Hello.")
        ]))
        XCTAssertNil(AskFeedback.anchorID(in: [
            AskFeedbackTurn(id: greeting, isUser: false, text: "Hello."),
            AskFeedbackTurn(id: question, isUser: true, text: "Status?")
        ]))
        XCTAssertNil(AskFeedback.anchorID(in: [
            AskFeedbackTurn(id: question, isUser: true, text: "Status?")
        ]))
        XCTAssertEqual(AskFeedback.question(before: greeting, in: [
            AskFeedbackTurn(id: greeting, isUser: false, text: "Hello.")
        ]), "")
    }

    func testSameThumbClearsAndTheOtherThumbReplaces() {
        var votes: [UUID: Bool] = [:]
        votes = AskFeedback.votes(votes, toggling: answer, helpful: true)
        XCTAssertEqual(votes[answer], true)
        votes = AskFeedback.votes(votes, toggling: answer, helpful: true)
        XCTAssertNil(votes[answer])
        votes = AskFeedback.votes(votes, toggling: answer, helpful: false)
        votes = AskFeedback.votes(votes, toggling: answer, helpful: true)
        XCTAssertEqual(votes[answer], true)
    }
}

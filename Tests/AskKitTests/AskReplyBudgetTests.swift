import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskReplyBudgetTests: XCTestCase {
    func testPlainBudgetStaysAtSixHundredCharacters() {
        XCTAssertEqual(
            AskReplyBudget.characterLimit(
                rich: false,
                compute: .onDevice,
                contextSize: 8_192,
                cloudMaximumResponseTokens: nil
            ),
            600
        )
        XCTAssertEqual(
            AskReplyBudget.characterLimit(
                rich: false,
                compute: .privateCloud,
                contextSize: 32_768,
                cloudMaximumResponseTokens: 1_024
            ),
            600
        )
    }

    func testRichOnDeviceUsesASliceOfTheSmallerWindow() {
        XCTAssertEqual(
            AskReplyBudget.responseTokenLimit(
                rich: true,
                compute: .onDevice,
                contextSize: 4_096,
                cloudMaximumResponseTokens: nil
            ),
            512
        )
        XCTAssertEqual(
            AskReplyBudget.responseTokenLimit(
                rich: true,
                compute: .onDevice,
                contextSize: 8_192,
                cloudMaximumResponseTokens: nil
            ),
            512
        )
        XCTAssertEqual(
            AskReplyBudget.characterLimit(
                rich: true,
                compute: .onDevice,
                contextSize: 8_192,
                cloudMaximumResponseTokens: nil
            ),
            2_048
        )
    }

    func testRichPrivateCloudAutomaticUsesALargerSlice() {
        XCTAssertEqual(
            AskReplyBudget.responseTokenLimit(
                rich: true,
                compute: .privateCloud,
                contextSize: 32_768,
                cloudMaximumResponseTokens: nil
            ),
            2_048
        )
        XCTAssertEqual(
            AskReplyBudget.characterLimit(
                rich: true,
                compute: .privateCloud,
                contextSize: 32_768,
                cloudMaximumResponseTokens: nil
            ),
            8_192
        )
    }

    func testRichPrivateCloudHonorsResponseLengthCap() {
        XCTAssertEqual(
            AskReplyBudget.responseTokenLimit(
                rich: true,
                compute: .privateCloud,
                contextSize: 32_768,
                cloudMaximumResponseTokens: 256
            ),
            256
        )
        XCTAssertEqual(
            AskReplyBudget.characterLimit(
                rich: true,
                compute: .privateCloud,
                contextSize: 32_768,
                cloudMaximumResponseTokens: 512
            ),
            2_048
        )
    }

    func testEstimatedTokensRoundsUpByFourCharacters() {
        XCTAssertEqual(AskReplyBudget.estimatedTokens(for: ""), 0)
        XCTAssertEqual(AskReplyBudget.estimatedTokens(for: "abcd"), 1)
        XCTAssertEqual(AskReplyBudget.estimatedTokens(for: "abcde"), 2)
    }
}

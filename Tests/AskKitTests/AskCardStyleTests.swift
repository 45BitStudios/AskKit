import PhotoQueryKit
import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskCardStyleTests: XCTestCase {
    func testStylesCoverSnippetChatAndFullScreen() {
        XCTAssertEqual(AskCardStyle.allCases, [.snippet, .chat, .fullScreen])
    }

    func testSnippetIsTighterThanChatAndFullScreen() {
        XCTAssertLessThan(AskCardStyle.snippet.padding, AskCardStyle.chat.padding)
        XCTAssertLessThan(AskCardStyle.chat.padding, AskCardStyle.fullScreen.padding)
        XCTAssertLessThan(AskCardStyle.snippet.contentSpacing, AskCardStyle.fullScreen.contentSpacing)
    }

    func testFullScreenChartFillsThePage() {
        XCTAssertTrue(AskCardStyle.fullScreen.fillsPage)
        XCTAssertFalse(AskCardStyle.chat.fillsPage)
        XCTAssertFalse(AskCardStyle.snippet.fillsPage)
        XCTAssertEqual(AskCardStyle.chat.chartHeight, 168)
    }

    func testSnippetDetailStaysOnOneLine() {
        XCTAssertEqual(AskCardStyle.snippet.detailLineLimit, 1)
        XCTAssertNil(AskCardStyle.chat.detailLineLimit)
        XCTAssertNil(AskCardStyle.fullScreen.detailLineLimit)
    }

    @MainActor
    func testFactCardExpandsForChatZoom() {
        let card = AskAppleCards.make(
            AskAppleReading(name: "skill", lines: ["68 percent", "About 40 minutes to the limit."]),
            spoken: "68 percent",
            custom: nil
        )
        XCTAssertTrue(card.expands)
        XCTAssertFalse(card.zoomTransition)
    }

    @MainActor
    func testCapabilitiesCardExpandsForChatZoom() {
        let card = AskCapabilities.card(
            spoken: "You can ask me questions like Charge status or Range and I can help with that.",
            domains: [AskDomain(id: "battery", summary: "Battery", routingNotes: "")],
            skills: [
                AskSkill(
                    id: "charge",
                    domainID: "battery",
                    title: "Charge status",
                    summary: "Current battery",
                    routingNotes: "",
                    fulfillment: .reply { _ in AskReply(text: "68%", spoken: "68%") }
                )
            ]
        )
        XCTAssertTrue(card.expands)
    }

    @MainActor
    func testWeatherCardExpandsForChatZoom() {
        let card = AskAppleCards.make(
            AskAppleReading(
                name: "weather",
                lines: [
                    AskWeatherLine.dayLine(
                        title: "Thu, Oct 8",
                        symbol: "cloud.sun",
                        condition: "Partly cloudy",
                        high: "72 F",
                        low: "54 F",
                        rain: "10 percent"
                    )
                ]
            ),
            spoken: "Partly cloudy.",
            custom: nil
        )
        XCTAssertTrue(card.expands)
        XCTAssertFalse(card.zoomTransition)
    }

    @MainActor
    func testPhotosKeepTheirOwnZoomInsteadOfCardExpand() {
        let result = PhotoResult(
            id: "AAAAAAAA-BBBB-CCCC-DDDD-000000000001/L0/001",
            pixelWidth: 100,
            pixelHeight: 80,
            mediaType: .image,
            isFavorite: false,
            filename: "Picnic.jpg"
        )
        let stored = AskPhotosLine.format([result], request: PhotoQueryRequest())
        let card = AskAppleCards.make(
            AskAppleReading(name: "photos", lines: stored.split(separator: "\n").map(String.init)),
            spoken: "One photo.",
            custom: nil
        )
        XCTAssertTrue(card.zoomTransition)
        XCTAssertFalse(card.expands)
    }
}

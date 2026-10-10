import XCTest
@testable import AskKit

final class AskPhotosTests: XCTestCase {
    func testLibraryQuestionsMatch() {
        XCTAssertTrue(AskPhotos.matches("Find my screenshots from last month"))
        XCTAssertTrue(AskPhotos.matches("Show photos of dogs"))
        XCTAssertTrue(AskPhotos.matches("Favorite photos wider than 2000px"))
        XCTAssertTrue(AskPhotos.matches("What's in my camera roll"))
        XCTAssertTrue(AskPhotos.matches("Live Photos from this year"))
        XCTAssertTrue(AskPhotos.matches("Pictures from the Vacation album"))
    }

    func testAttachedPhotoQuestionsStayOff() {
        XCTAssertFalse(AskPhotos.matches("Where was this photo taken?"))
        XCTAssertFalse(AskPhotos.matches("What camera took this picture?"))
        XCTAssertFalse(AskPhotos.matches("When was this image taken?"))
        XCTAssertFalse(AskPhotos.matches("What's my favorite song?"))
        XCTAssertFalse(AskPhotos.matches("Hello there"))
    }

    func testRequestBuildsFilters() {
        let request = AskPhotosQuery.request(
            mediaType: "image",
            minWidth: 2000,
            maxWidth: nil,
            minHeight: nil,
            maxHeight: nil,
            daysAgo: 30,
            throughDaysAgo: nil,
            isFavorite: true,
            subtype: "screenshot",
            albumTitle: nil,
            textSearch: "dog",
            limit: 10
        )
        XCTAssertEqual(request.mediaType, .image)
        XCTAssertEqual(request.minWidth, 2000)
        XCTAssertEqual(request.isFavorite, true)
        XCTAssertEqual(request.mediaSubtypes, ["screenshot"])
        XCTAssertEqual(request.textSearch, "dog")
        XCTAssertEqual(request.limit, 10)
        XCTAssertNotNil(request.startDate)
    }

    func testEnrichFillsGapsFromQuestion() {
        var request = AskPhotosQuery.request(
            mediaType: nil,
            minWidth: nil,
            maxWidth: nil,
            minHeight: nil,
            maxHeight: nil,
            daysAgo: nil,
            throughDaysAgo: nil,
            isFavorite: nil,
            subtype: nil,
            albumTitle: nil,
            textSearch: nil,
            limit: nil
        )
        request = AskPhotosQuery.enrich(request, question: "screenshots from last week wider than 1000px")
        XCTAssertEqual(request.mediaType, .image)
        XCTAssertEqual(request.mediaSubtypes, ["screenshot"])
        XCTAssertEqual(request.minWidth, 1000)
        XCTAssertNotNil(request.startDate)
        XCTAssertEqual(request.limit, AskPhotosQuery.defaultLimit)
    }

    func testLinesHaveNoEqualsAndSpeakCleanly() {
        let lines = """
        Found 2 screenshots.
        IMG_0001.PNG · Oct 1, 2026 · 1170×2532
        IMG_0002.PNG · Oct 2, 2026 · 1170×2532
        """.split(separator: "\n").map(String.init)
        XCTAssertFalse(lines.contains { $0.contains("=") })
        XCTAssertEqual(AskPhotosLine.spoken(lines), "Found 2 screenshots.")
        XCTAssertEqual(AskPhotosLine.spoken([AskPhotosLine.empty]), AskPhotosLine.empty)
        XCTAssertEqual(AskPhotosLine.spoken([AskPhotosLine.denied]), AskPhotosLine.denied)
    }

    func testSpecialistIdentity() {
        let specialist = AskPhotos.specialist(id: "open.photos")
        XCTAssertEqual(specialist.id, "open.photos")
        XCTAssertEqual(specialist.title, "Photos")
        XCTAssertEqual(specialist.workingTitle, "Searching photos")
        XCTAssertTrue(specialist.matches("Find my screenshots"))
        XCTAssertFalse(specialist.matches("What time is it?"))
    }

    @MainActor
    func testPhotosCardUsesLibraryTitle() {
        let card = AskAppleCards.make(
            AskAppleReading(name: "photos", lines: [
                "Found 2 screenshots.",
                "IMG_0001.PNG · Oct 1, 2026 · 1170×2532"
            ]),
            spoken: "Found 2 screenshots."
        )
        XCTAssertEqual(card.title, "Photos")
        XCTAssertTrue(card.shareText.contains("Found 2 screenshots."))
        XCTAssertEqual(AskCardSymbol.symbol(for: "Photos"), "photo.on.rectangle")
    }

    @MainActor
    func testSpecialistExposesPhotosTool() {
        let tools = AskPhotos.specialist().tools()
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, AskPhotos.toolName)
    }

    func testIndexStatusCopy() {
        XCTAssertEqual(AskPhotosIndexCopy.needed.title, "Photos need indexing")
        XCTAssertEqual(AskPhotosIndexCopy.needed.detail, "For content search")
        let indexing = AskPhotosIndexCopy.indexing(completed: 12, total: 200)
        XCTAssertEqual(indexing.title, "Indexing photos…")
        XCTAssertEqual(indexing.detail, "12 of 200")
        let ready = AskPhotosIndexCopy.ready(count: 200)
        XCTAssertEqual(ready.title, "Searching photos")
        XCTAssertEqual(ready.detail, "200 indexed")
        XCTAssertEqual(
            AskPhotosIndexCopy.indexedFact(count: 200),
            "Indexed 200 recent photos for content search."
        )
        XCTAssertEqual(
            AskPhotosIndexCopy.indexedFact(count: 1),
            "Indexed 1 recent photo for content search."
        )
    }

    func testSpokenPrefersFoundAfterIndexFact() {
        let lines = [
            "Indexed 200 recent photos for content search.",
            "Found 2 photos.",
            "IMG_0001.PNG · Oct 1, 2026 · 1170×2532"
        ]
        XCTAssertEqual(AskPhotosLine.spoken(lines), "Found 2 photos.")
    }
}

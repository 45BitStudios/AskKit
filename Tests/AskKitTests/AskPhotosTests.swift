import PhotoQueryKit
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
        XCTAssertTrue(AskPhotos.matches("Find photos near 37.3349, -122.0090"))
        XCTAssertTrue(AskPhotos.matches("Photos within 500 meters of lat 37.33 lon -122.01"))
        XCTAssertTrue(AskPhotos.matches("List my photo albums"))
        XCTAssertTrue(AskPhotos.matches("Show hidden photos"))
        XCTAssertTrue(AskPhotos.matches("Oldest photos first"))
        XCTAssertTrue(AskPhotos.matches("Find similar photos"))
        XCTAssertTrue(AskPhotos.matches("Show burst photos"))
    }

    func testAttachedPhotoQuestionsStayOff() {
        XCTAssertFalse(AskPhotos.matches("Where was this photo taken?"))
        XCTAssertFalse(AskPhotos.matches("What camera took this picture?"))
        XCTAssertFalse(AskPhotos.matches("When was this image taken?"))
        XCTAssertFalse(AskPhotos.matches("What's my favorite song?"))
        XCTAssertFalse(AskPhotos.matches("Hello there"))
    }

    func testRequestBuildsFilters() {
        let request = blankRequest(
            mediaType: "image",
            minWidth: 2000,
            daysAgo: 30,
            isFavorite: true,
            isHidden: true,
            subtype: "screenshot",
            textSearch: "dog",
            latitude: 37.3349,
            longitude: -122.0090,
            radiusMeters: 500,
            newestFirst: false,
            limit: 10
        )
        XCTAssertEqual(request.mediaType, .image)
        XCTAssertEqual(request.minWidth, 2000)
        XCTAssertEqual(request.isFavorite, true)
        XCTAssertEqual(request.isHidden, true)
        XCTAssertEqual(request.mediaSubtypes, ["screenshot"])
        XCTAssertEqual(request.textSearch, "dog")
        XCTAssertEqual(request.limit, 10)
        XCTAssertEqual(request.locationLatitude, 37.3349)
        XCTAssertEqual(request.locationLongitude, -122.0090)
        XCTAssertEqual(request.locationRadiusMeters, 500)
        XCTAssertEqual(request.sortDescending, false)
        XCTAssertNotNil(request.startDate)
    }

    func testRequestDefaultsRadiusWhenCoordinatesProvided() {
        let request = blankRequest(latitude: 37.3349, longitude: -122.0090)
        XCTAssertEqual(request.locationRadiusMeters, AskPhotosQuery.defaultRadiusMeters)
    }

    func testEnrichFillsGapsFromQuestion() {
        var request = blankRequest()
        request = AskPhotosQuery.enrich(request, question: "screenshots from last week wider than 1000px")
        XCTAssertEqual(request.mediaType, .image)
        XCTAssertEqual(request.mediaSubtypes, ["screenshot"])
        XCTAssertEqual(request.minWidth, 1000)
        XCTAssertNotNil(request.startDate)
        XCTAssertEqual(request.limit, AskPhotosQuery.defaultLimit)
    }

    func testEnrichParsesCoordinatesAndRadius() {
        var request = blankRequest()
        request = AskPhotosQuery.enrich(
            request,
            question: "Find photos within 2 km of 37.3349, -122.0090"
        )
        XCTAssertEqual(request.locationLatitude ?? 0, 37.3349, accuracy: 0.0001)
        XCTAssertEqual(request.locationLongitude ?? 0, -122.0090, accuracy: 0.0001)
        XCTAssertEqual(request.locationRadiusMeters ?? 0, 2_000, accuracy: 0.1)

        let labeled = AskPhotosQuery.coordinates(in: "lat 37.33 lon -122.01")
        XCTAssertEqual(labeled?.latitude ?? 0, 37.33, accuracy: 0.001)
        XCTAssertEqual(labeled?.longitude ?? 0, -122.01, accuracy: 0.001)
    }

    func testEnrichParsesHiddenOldestAndHDR() {
        var hidden = AskPhotosQuery.enrich(blankRequest(), question: "Show hidden photos")
        XCTAssertEqual(hidden.isHidden, true)

        var oldest = AskPhotosQuery.enrich(blankRequest(), question: "Oldest photos first")
        XCTAssertEqual(oldest.sortDescending, false)

        var hdr = AskPhotosQuery.enrich(blankRequest(), question: "Find HDR photos")
        XCTAssertEqual(hdr.mediaSubtypes, ["hdr"])
    }

    func testAlbumLines() {
        let text = AskPhotosLine.albums(["Vacation", "Family"])
        XCTAssertTrue(text.hasPrefix("Found 2 albums."))
        XCTAssertTrue(text.contains("Vacation"))
        XCTAssertEqual(AskPhotosLine.albums([]), "No albums.")
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
        let updating = AskPhotosIndexCopy.updating(since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(updating.title, "Updating photo index…")
        XCTAssertTrue(updating.detail.hasPrefix("Since "))
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

    private func blankRequest(
        mediaType: String? = nil,
        minWidth: Int? = nil,
        maxWidth: Int? = nil,
        minHeight: Int? = nil,
        maxHeight: Int? = nil,
        daysAgo: Int? = nil,
        throughDaysAgo: Int? = nil,
        isFavorite: Bool? = nil,
        isHidden: Bool? = nil,
        subtype: String? = nil,
        albumTitle: String? = nil,
        textSearch: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double? = nil,
        newestFirst: Bool? = nil,
        limit: Int? = nil
    ) -> PhotoQueryRequest {
        AskPhotosQuery.request(
            mediaType: mediaType,
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight,
            daysAgo: daysAgo,
            throughDaysAgo: throughDaysAgo,
            isFavorite: isFavorite,
            isHidden: isHidden,
            subtype: subtype,
            albumTitle: albumTitle,
            textSearch: textSearch,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            newestFirst: newestFirst,
            limit: limit
        )
    }
}

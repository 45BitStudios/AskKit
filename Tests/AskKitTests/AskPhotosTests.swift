import PhotoQueryKit
import Photos
import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskPhotosTests: XCTestCase {
    func testLibraryQuestionsMatch() {
        XCTAssertTrue(AskPhotos.matches("Find my screenshots from last month"))
        XCTAssertTrue(AskPhotos.matches("Show photos of dogs"))
        XCTAssertTrue(AskPhotos.matches("Favorite photos wider than 2000px"))
        XCTAssertTrue(AskPhotos.matches("What's in my camera roll"))
        XCTAssertTrue(AskPhotos.matches("Live Photos from this year"))
        XCTAssertTrue(AskPhotos.matches("Pictures from the Vacation album"))
        XCTAssertTrue(AskPhotos.matches("Find photos near 37.3349, -122.0090"))
        XCTAssertTrue(AskPhotos.matches("Do I have any pictures near Austin tx"))
        XCTAssertTrue(AskPhotos.matches("Photos within 500 meters of lat 37.33 lon -122.01"))
        XCTAssertTrue(AskPhotos.matches("List my photo albums"))
        XCTAssertTrue(AskPhotos.matches("Show hidden photos"))
        XCTAssertTrue(AskPhotos.matches("Oldest photos first"))
        XCTAssertTrue(AskPhotos.matches("Find similar photos"))
        XCTAssertTrue(AskPhotos.matches("Show burst photos"))
        XCTAssertTrue(AskPhotos.matches("What photos did I take yesterday?"))
        XCTAssertTrue(AskPhotos.matches("Pictures I took today"))
        XCTAssertTrue(AskPhotos.matches("yesterday's photos"))
        XCTAssertTrue(AskPhotos.matches("What photos did I take this morning?"))
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

    func testANamedPlaceUsesACityRadius() {
        XCTAssertEqual(AskPhotosQuery.place(in: "Do I have any pictures near Austin tx"), "austin tx")
        XCTAssertEqual(AskPhotosQuery.place(in: "Find photos near 37.3349, -122.0090"), "")
        XCTAssertEqual(AskPhotosQuery.place(in: "photos within 2 km of Austin"), "austin")
        XCTAssertEqual(AskPhotosQuery.place(in: "Show photos of dogs"), "")

        let widened = AskPhotosQuery.enrich(
            blankRequest(latitude: 30.267, longitude: -97.743, radiusMeters: 1_000),
            question: "Do I have any pictures near Austin tx"
        )
        XCTAssertEqual(widened.locationLatitude ?? 0, 30.267, accuracy: 0.0001)
        XCTAssertEqual(widened.locationLongitude ?? 0, -97.743, accuracy: 0.0001)
        XCTAssertEqual(widened.locationRadiusMeters ?? 0, AskPhotosQuery.placeRadiusMeters, accuracy: 0.1)
        XCTAssertNil(widened.textSearch)

        let measured = AskPhotosQuery.enrich(blankRequest(), question: "photos within 2 km of Austin")
        XCTAssertNil(measured.locationLatitude)
        XCTAssertEqual(measured.locationRadiusMeters ?? 0, 2_000, accuracy: 0.1)
        XCTAssertNil(measured.textSearch)

        let dogs = AskPhotosQuery.enrich(blankRequest(), question: "Show photos of dogs")
        XCTAssertEqual(dogs.textSearch, "dogs")
        XCTAssertNil(dogs.locationRadiusMeters)
    }

    func testALocationSearchScansPastTheNewestPage() {
        var located = PhotoQueryRequest()
        located.locationLatitude = 30.267
        located.locationLongitude = -97.743
        located.locationRadiusMeters = AskPhotosQuery.placeRadiusMeters
        located.limit = 12
        XCTAssertTrue(PhotoLibraryService.needsLocatedAssets(located))
        XCTAssertEqual(PhotoLibraryService.candidateFetchLimit(for: located), 0)

        var recent = PhotoQueryRequest()
        recent.limit = 12
        XCTAssertFalse(PhotoLibraryService.needsLocatedAssets(recent))
        XCTAssertEqual(PhotoLibraryService.candidateFetchLimit(for: recent), 12)

        var library = PhotoQueryRequest()
        library.sourceType = "userLibrary"
        library.limit = 12
        XCTAssertEqual(PhotoLibraryService.candidateFetchLimit(for: library), 0)
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

    func testAMissedPhotoQuestionPlansALibraryRead() {
        let question = "What photos did I take today"
        let missed = AskAppleRepair.plan(question: question, readings: [], toolNames: ["photos"])
        XCTAssertTrue(missed.readPhotos)
        let kept = AskAppleRepair.plan(
            question: question,
            readings: [AskAppleReading(name: "photos", lines: ["Found 1 photo."])],
            toolNames: ["photos"]
        )
        XCTAssertFalse(kept.readPhotos)
        let otherTool = AskAppleRepair.plan(question: question, readings: [], toolNames: ["music"])
        XCTAssertFalse(otherTool.readPhotos)
        let playing = AskAppleRepair.plan(question: "What's playing", readings: [], toolNames: ["photos"])
        XCTAssertFalse(playing.readPhotos)
        let request = AskPhotosQuery.fromQuestion(question)
        let window = AskPhotosQuery.takenDay(in: question)
        XCTAssertEqual(request.mediaType, .image)
        XCTAssertEqual(request.startDate, window?.start)
        XCTAssertEqual(request.endDate, window?.end.addingTimeInterval(-1))
        XCTAssertTrue(AskPhotosQuery.listsAlbums("What are my albums"))
        XCTAssertFalse(AskPhotosQuery.listsAlbums(question))
    }

    func testEnrichUsesYesterdayAsThatCalendarDay() {
        let question = "What photos did I take yesterday?"
        let now = Date()
        let calendar = Calendar.current
        let request = AskPhotosQuery.enrich(blankRequest(daysAgo: 1), question: question)
        let window = AskPhotosQuery.takenDay(in: question, now: now, calendar: calendar)
        XCTAssertEqual(AskCalendarWindow.offset(namedIn: question, now: now, calendar: calendar), -1)
        XCTAssertEqual(request.startDate, window?.start)
        XCTAssertEqual(request.endDate, window?.end.addingTimeInterval(-1))
        XCTAssertNil(AskPhotosQuery.takenDay(in: "Show photos of dogs", now: now, calendar: calendar))
    }

    func testYesterdayPhotosNameTheLibraryAndNotCalendar() {
        XCTAssertEqual(
            AskSourceFocus.named(in: "What photos did I take yesterday?"),
            Set(["photos"])
        )
        XCTAssertEqual(
            AskSourceFocus.named(in: "What photos did I take yesterday and what's on my calendar?"),
            Set(["calendar", "photos"])
        )
        let choices = AskTurnSpecialists.appleChoices(
            question: "What photos did I take yesterday?",
            access: .calendar
        )
        XCTAssertTrue(choices.isEmpty)
    }

    func testSpecialistIdentity() {
        let specialist = AskPhotos.specialist(id: "open.photos")
        XCTAssertEqual(specialist.id, "open.photos")
        XCTAssertEqual(specialist.title, "Photos")
        XCTAssertEqual(specialist.symbolName, "photo.on.rectangle")
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
            spoken: "Found 2 screenshots.",
            custom: nil
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

    func testPhotoRowsKeepEveryAssetAndHideItFromTheModel() {
        let results = (1...10).map { index in
            PhotoResult(
                id: String(format: "AAAAAAAA-BBBB-CCCC-DDDD-%012d/L0/001", index),
                pixelWidth: 100,
                pixelHeight: 80,
                mediaType: .image,
                isFavorite: false,
                filename: "IMG_\(index).jpg"
            )
        }
        let stored = AskPhotosLine.format(results, request: PhotoQueryRequest())
        XCTAssertFalse(stored.contains("="))
        XCTAssertEqual(stored.components(separatedBy: "asset:").count - 1, 10)
        XCTAssertFalse(stored.contains("And "))
        let model = AskPhotosLine.forModel(stored)
        XCTAssertFalse(model.contains("asset:"))
        XCTAssertFalse(model.contains("AAAAAAAA"))
        XCTAssertTrue(model.contains("Found 10 photos."))
        XCTAssertTrue(model.contains("And 2 more."))
        XCTAssertEqual(model.components(separatedBy: "IMG_").count - 1, 8)
        let grid = AskPhotosLine.grid(from: stored.split(separator: "\n").map(String.init))
        XCTAssertEqual(grid?.photos.count, 10)
        XCTAssertEqual(grid?.photos.first?.caption, "IMG_1.jpg")
        XCTAssertEqual(grid?.photos.first?.id, results[0].id)
        XCTAssertEqual(AskPhotosLine.overflow(count: 12), 8)
        XCTAssertEqual(AskPhotosLine.overflow(count: 4), 0)
        XCTAssertEqual(AskPhotosLine.overflow(count: 1), 0)
        let ids = results.map(\.id)
        XCTAssertEqual(
            AskPhotosLine.zoomSource(prefix: "card", photoID: ids[1], ids: ids),
            "card|\(ids[1])"
        )
        XCTAssertEqual(
            AskPhotosLine.zoomSource(prefix: "card", photoID: ids[8], ids: ids),
            "card|\(ids[3])"
        )
        XCTAssertEqual(
            AskPhotosLine.selectedID(startID: ids[2], choiceStart: nil, choiceID: nil, ids: ids),
            ids[2]
        )
        XCTAssertEqual(
            AskPhotosLine.selectedID(startID: ids[2], choiceStart: ids[0], choiceID: ids[1], ids: ids),
            ids[2]
        )
        XCTAssertEqual(
            AskPhotosLine.selectedID(startID: ids[2], choiceStart: ids[2], choiceID: ids[5], ids: ids),
            ids[5]
        )
        XCTAssertEqual(
            AskPhotosLine.selectedID(startID: "missing", choiceStart: nil, choiceID: nil, ids: ids),
            ids[0]
        )
    }

    func testAnEqualsSignInAnAssetIdIsStoredEncoded() {
        let result = PhotoResult(
            id: "abc=def/L0/001",
            pixelWidth: 10,
            pixelHeight: 10,
            mediaType: .image,
            isFavorite: false,
            filename: "A.jpg"
        )
        let line = AskPhotosLine.row(result)
        XCTAssertFalse(line.contains("="))
        XCTAssertTrue(line.contains("asset:abc%3Ddef/L0/001"))
        XCTAssertEqual(AskPhotosLine.photo(from: line)?.id, "abc=def/L0/001")
        XCTAssertEqual(AskPhotosLine.photo(from: line)?.caption, "A.jpg")
        XCTAssertNil(AskPhotosLine.grid(from: ["Found 2 albums.", "Vacation"]))
    }

    @MainActor
    func testPhotoCardSharesTheCountWithoutAssetIds() {
        let id = "AAAAAAAA-BBBB-CCCC-DDDD-000000000001/L0/001"
        let card = AskAppleCards.make(
            AskAppleReading(name: "photos", lines: [
                "Found 1 photo.",
                "Beach.jpg · Oct 1, 2026 · 100×80 · asset:\(id)"
            ]),
            spoken: "Found 1 photo.",
            custom: nil
        )
        XCTAssertEqual(card.title, "Photos")
        XCTAssertTrue(card.shareText.contains("Found 1 photo."))
        XCTAssertTrue(card.shareText.contains("Beach.jpg"))
        XCTAssertFalse(card.shareText.contains("asset:"))
        XCTAssertFalse(card.shareText.contains(id))
        XCTAssertEqual(card.coveredPhrases, ["Beach.jpg"])
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
        burstIdentifier: String? = nil,
        sourceType: String? = nil,
        similarTo: String? = nil,
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
            burstIdentifier: burstIdentifier,
            sourceType: sourceType,
            similarTo: similarTo,
            limit: limit
        )
    }
}

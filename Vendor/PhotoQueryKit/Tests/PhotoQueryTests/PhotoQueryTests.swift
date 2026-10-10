import XCTest
@testable import PhotoQueryKit

final class PhotoQueryTests: XCTestCase {
    func testRequestCodableRoundTrip() throws {
        var request = PhotoQueryRequest()
        request.mediaType = .image
        request.minWidth = 1920
        request.isFavorite = true
        request.limit = 25

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(PhotoQueryRequest.self, from: data)

        XCTAssertEqual(decoded.mediaType, .image)
        XCTAssertEqual(decoded.minWidth, 1920)
        XCTAssertEqual(decoded.isFavorite, true)
        XCTAssertEqual(decoded.limit, 25)
    }

    func testIndexProgressFraction() {
        let mid = PhotoIndexProgress(completed: 50, total: 200, indexedCount: 40, isFinished: false)
        XCTAssertEqual(mid.fractionComplete, 0.25, accuracy: 0.0001)
        let empty = PhotoIndexProgress(completed: 0, total: 0, indexedCount: 0, isFinished: true)
        XCTAssertEqual(empty.fractionComplete, 1)
    }
}

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

    func testIndexStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoQueryKit-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = PhotoIndexStore(fileURL: url)
        let stamped = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = VisionIndexer.IndexEntry(
            localIdentifier: "asset-1",
            labels: ["dog", "pet"],
            ocrText: "hello",
            indexedAt: stamped
        )
        let snapshot = PhotoIndexSnapshot(lastIndexedAt: stamped, entries: [entry])
        try store.save(snapshot)

        let loaded = store.load()
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.localIdentifier, "asset-1")
        XCTAssertEqual(loaded.entries.first?.labels, ["dog", "pet"])
        XCTAssertEqual(loaded.lastIndexedAt?.timeIntervalSince1970, stamped.timeIntervalSince1970, accuracy: 1)
    }

    func testEmptyStoreLoadsBlankSnapshot() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoQueryKit-missing-\(UUID().uuidString).json")
        let store = PhotoIndexStore(fileURL: url)
        let loaded = store.load()
        XCTAssertNil(loaded.lastIndexedAt)
        XCTAssertTrue(loaded.entries.isEmpty)
    }
}

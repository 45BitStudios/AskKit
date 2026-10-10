import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AskKit

final class AskImageFileTests: XCTestCase {
    func testOnlyFoundationModelImageTypesAreAccepted() {
        XCTAssertTrue(AskImageFile.matches(.jpeg))
        XCTAssertTrue(AskImageFile.matches(.png))
        XCTAssertTrue(AskImageFile.matches(.heic))
        XCTAssertTrue(AskImageFile.matches(.gif))
        XCTAssertFalse(AskImageFile.matches(.pdf))
        XCTAssertFalse(AskImageFile.matches(.plainText))
        XCTAssertFalse(AskImageFile.matches(.json))
        XCTAssertEqual(AskImageFile.maximumCount, 4)
    }

    func testADecodedPngIsStoredAndPlainTextIsNot() throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        let stored = try XCTUnwrap(AskImageFile.store(data: png, preferredName: "dot.png"))
        XCTAssertEqual(stored.pathExtension.lowercased(), "png")
        XCTAssertNil(AskImageFile.store(data: Data("hello".utf8), preferredName: "note.txt"))
        XCTAssertEqual(AskImageFacts.block([stored]), "")
        try? FileManager.default.removeItem(at: stored)
    }

    func testPhotoMetadataJoinsTheFactsAndAPlainPngDoesNot() throws {
        let jpeg = try taggedJPEG(name: "Photo.jpg")
        defer { try? FileManager.default.removeItem(at: jpeg) }
        let block = AskImageFacts.block([jpeg])
        XCTAssertTrue(block.hasPrefix("Photo. "))
        XCTAssertTrue(block.contains("Coordinates 37.5000, -122.5000"))
        XCTAssertTrue(block.contains("Taken 12 March 2024 at 3:04 PM"))
        XCTAssertTrue(block.contains("Place Cupertino"))
        XCTAssertTrue(block.contains("Camera Apple iPhone 15"))
        XCTAssertTrue(block.contains("Altitude 12 m"))
        XCTAssertFalse(block.contains("Photo 1"))
        XCTAssertFalse(block.contains("="))
        let shot = try XCTUnwrap(AskImageFacts.snapshots([jpeg]).first)
        XCTAssertEqual(shot.latitude, 37.5)
        XCTAssertEqual(shot.longitude, -122.5)
        XCTAssertEqual(shot.place, "Cupertino")

        let facts = AskImageFacts.merging("Battery 80 percent.", photoFacts: block)
        XCTAssertTrue(facts.hasPrefix("Battery 80 percent.\nPhoto. "))
        XCTAssertEqual(AskImageFacts.merging("Battery 80 percent.", photoFacts: ""), "Battery 80 percent.")

        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        let stored = try XCTUnwrap(AskImageFile.store(data: png, preferredName: "shot.png"))
        defer { try? FileManager.default.removeItem(at: stored) }
        XCTAssertEqual(AskImageFacts.block([stored]), "")

        let second = try taggedJPEG(name: "ridge.jpg")
        defer { try? FileManager.default.removeItem(at: second) }
        let pair = AskImageFacts.block([jpeg, second])
        XCTAssertTrue(pair.contains("Photo 1"))
        XCTAssertTrue(pair.contains("Photo 2 ridge"))
    }

    func testAFollowUpAboutWhereItWasTakenUsesThePhoto() {
        XCTAssertTrue(AskImageFacts.asksWhereTaken("What location was it taken at"))
        XCTAssertTrue(AskImageFacts.asksWhereTaken("Where was this photo taken"))
        XCTAssertTrue(AskImageFacts.continues("What location was it taken at"))
        XCTAssertTrue(AskImageFacts.continues("When was it taken"))
        XCTAssertFalse(AskImageFacts.asksWhereTaken("Where is Apple Park?"))
        XCTAssertFalse(AskImageFacts.continues("Where is Apple Park?"))
        XCTAssertFalse(AskImageFacts.continues("how many steps today"))
        XCTAssertTrue(AskImageFacts.continues("Do you have the mega ppi Do you have the megapixel information"))
        XCTAssertTrue(AskImageFacts.asksPixels("Do you have the mega ppi Do you have the megapixel information"))
        XCTAssertTrue(AskImageFacts.asksPPI("Do you have the mega ppi Do you have the megapixel information"))
        XCTAssertFalse(AskImageFacts.asksPixels("Where is Apple Park?"))
        XCTAssertTrue(AskImageFacts.asksCamera("with what phone"))
        XCTAssertTrue(AskImageFacts.continues("with what phone"))
        XCTAssertTrue(AskImageFacts.asksCamera("on what phone"))
        XCTAssertFalse(AskImageFacts.asksCamera("where's my phone"))
        XCTAssertFalse(AskImageFacts.continues("where's my phone"))
        XCTAssertFalse(AskImageFacts.asksCamera("what's my phone number"))
        XCTAssertTrue(AskImageFacts.asksDate("on what date"))
        XCTAssertTrue(AskImageFacts.asksDate("when was it taken"))
        XCTAssertTrue(AskImageFacts.continues("on what date"))
        XCTAssertFalse(AskImageFacts.asksDate("what's the date today"))
        XCTAssertFalse(AskImageFacts.continues("what's the date today"))
        XCTAssertFalse(AskImageFacts.continues("how's my phone"))

        let parts = AskPages.pieces("Where was it taken and on what date and with what phone")
        XCTAssertEqual(parts, ["Where was it taken", "on what date", "with what phone"])
        XCTAssertEqual(parts.compactMap(AskImageFacts.aspect), [.place, .date, .camera])
        XCTAssertTrue(AskImageFacts.distinctQuestions(parts, hasPhotos: true))
        XCTAssertFalse(AskImageFacts.distinctQuestions(["how far", "miles left"], hasPhotos: true))
        XCTAssertFalse(AskImageFacts.distinctQuestions(parts, hasPhotos: false))

        let pixels = AskImageFacts.Snapshot(width: 4032, height: 3024, ppiWidth: 72, ppiHeight: 72)
        XCTAssertEqual(
            AskImageFacts.pixelSentence([pixels], includesPPI: true),
            "It's 12.2 megapixels, 4032 by 3024, at 72 ppi."
        )
        let bare = AskImageFacts.Snapshot(width: 4032, height: 3024)
        XCTAssertEqual(
            AskImageFacts.pixelSentence([bare], includesPPI: true),
            "It's 12.2 megapixels, 4032 by 3024. The file doesn't include a ppi."
        )
        XCTAssertEqual(
            AskImageFacts.cameraSentence([AskImageFacts.Snapshot(camera: "Apple iPhone 17 Pro Max")]),
            "It was taken on an Apple iPhone 17 Pro Max."
        )
        XCTAssertEqual(
            AskImageFacts.dateSentence([AskImageFacts.Snapshot(date: "12 March 2024 at 3:04 PM")]),
            "It was taken on 12 March 2024 at 3:04 PM."
        )
        XCTAssertEqual(
            AskImageFacts.dateSentence([AskImageFacts.Snapshot(camera: "Apple iPhone 17 Pro Max")]),
            "This photo doesn't include a date."
        )
        XCTAssertEqual(
            AskLocationPin.addressLine(["17395A W Bluemound Rd", "17395A W Bluemound Rd, Brookfield"]),
            "17395A W Bluemound Rd, Brookfield"
        )

        let named = AskImageFacts.Snapshot(date: "6 October 2026 at 11:48 AM", place: "Ferry Building, San Francisco", latitude: 37.5, longitude: -122.5)
        XCTAssertEqual(AskImageFacts.whereTakenSentence([named]), "It was taken at Ferry Building, San Francisco.")
        let dated = AskImageFacts.Snapshot(date: "6 October 2026 at 11:48 AM", place: nil, latitude: nil, longitude: nil)
        XCTAssertEqual(
            AskImageFacts.whereTakenSentence([dated]),
            "This photo doesn't include a place. It was taken on 6 October 2026 at 11:48 AM."
        )
        let unnamed = AskImageFacts.Snapshot(date: nil, place: AskPhotoLocation.unnamed, latitude: 37.5, longitude: -122.5)
        XCTAssertEqual(AskImageFacts.whereTakenSentence([unnamed]), "The map shows where it was taken.")
    }

    private func taggedJPEG(name: String) throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 6,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.5,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.5,
                kCGImagePropertyGPSLongitudeRef: "W",
                kCGImagePropertyGPSAltitude: 12,
                kCGImagePropertyGPSAltitudeRef: 0
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2024:03:12 15:04:05"
            ] as [CFString: Any],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone=15"
            ] as [CFString: Any],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCity: "Cupertino"
            ] as [CFString: Any]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}

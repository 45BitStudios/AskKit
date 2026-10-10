import CoreLocation
import Foundation
import Photos

// MARK: - Authorization

public enum PhotoAuthorization {
    public static func status(for accessLevel: PHAccessLevel = .readWrite) -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: accessLevel)
    }

    public static func request(accessLevel: PHAccessLevel = .readWrite) async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: accessLevel)
    }

    public static var isAuthorized: Bool {
        let status = status()
        return status == .authorized || status == .limited
    }
}

// MARK: - Structured Query (LLM-friendly)

/// Codable request that foundation models can emit as JSON.
/// Example: “images wider than 2000px from June 2024 that are favorites”
public struct PhotoQueryRequest: Codable, Sendable {
    public var mediaType: MediaType?
    public var minWidth: Int?
    public var maxWidth: Int?
    public var minHeight: Int?
    public var maxHeight: Int?
    public var startDate: Date?
    public var endDate: Date?
    public var isFavorite: Bool?
    public var isHidden: Bool?
    public var mediaSubtypes: [String]?          // e.g. ["screenshot", "live", "panorama"]
    public var albumTitle: String?
    public var textSearch: String?               // filename or OCR match
    public var locationLatitude: Double?
    public var locationLongitude: Double?
    public var locationRadiusMeters: Double?
    public var limit: Int?
    public var sortDescending: Bool?

    public enum MediaType: String, Codable, Sendable, Equatable {
        case image, video, livePhoto, any
    }

    public init(
        mediaType: MediaType? = nil,
        minWidth: Int? = nil,
        maxWidth: Int? = nil,
        minHeight: Int? = nil,
        maxHeight: Int? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isFavorite: Bool? = nil,
        isHidden: Bool? = nil,
        mediaSubtypes: [String]? = nil,
        albumTitle: String? = nil,
        textSearch: String? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        locationRadiusMeters: Double? = nil,
        limit: Int? = nil,
        sortDescending: Bool? = true
    ) {
        self.mediaType = mediaType
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.startDate = startDate
        self.endDate = endDate
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.mediaSubtypes = mediaSubtypes
        self.albumTitle = albumTitle
        self.textSearch = textSearch
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.locationRadiusMeters = locationRadiusMeters
        self.limit = limit
        self.sortDescending = sortDescending
    }
}

// MARK: - Result Model

public struct PhotoResult: Identifiable, Sendable {
    public let id: String                          // localIdentifier
    public let cloudIdentifier: String?
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let mediaType: PHAssetMediaType
    public let isFavorite: Bool
    public let filename: String?
    public let location: CLLocation?
    public let visionLabels: [String]
    public let ocrText: String?

    public var aspectRatio: Double {
        guard pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }
}

// MARK: - Internal Filter

struct PhotoFilter {
    var mediaType: PHAssetMediaType?
    var mediaSubtypes: PHAssetMediaSubtype = []
    var isFavorite: Bool?
    var isHidden: Bool?
    var minWidth: Int?
    var maxWidth: Int?
    var minHeight: Int?
    var maxHeight: Int?
    var dateRange: ClosedRange<Date>?
    var album: PHAssetCollection?
    var fetchLimit: Int = 0
    var sortDescending: Bool = true
}

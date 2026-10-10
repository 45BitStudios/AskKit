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
    /// Match assets in this burst group.
    public var burstIdentifier: String?
    /// userLibrary, cloudShared, or iTunesSynced.
    public var sourceType: String?
    /// Find visually similar photos using Vision feature prints.
    public var similarToLocalIdentifier: String?
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
        burstIdentifier: String? = nil,
        sourceType: String? = nil,
        similarToLocalIdentifier: String? = nil,
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
        self.burstIdentifier = burstIdentifier
        self.sourceType = sourceType
        self.similarToLocalIdentifier = similarToLocalIdentifier
        self.limit = limit
        self.sortDescending = sortDescending
    }
}

// MARK: - Result Model

public struct PhotoResult: Identifiable, Sendable {
    public let id: String                          // localIdentifier
    public let cloudIdentifier: String?
    public let creationDate: Date?
    public let modificationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let mediaType: PHAssetMediaType
    /// Normalized subtype names such as screenshot, live, panorama, hdr, depth, timelapse, slowmo.
    public let mediaSubtypes: [String]
    public let isFavorite: Bool
    public let isHidden: Bool
    /// Video duration in seconds. Nil for stills.
    public let durationSeconds: Double?
    public let filename: String?
    public let location: CLLocation?
    /// Burst group id when this asset is part of a burst.
    public let burstIdentifier: String?
    public let representsBurst: Bool
    /// userLibrary, cloudShared, and/or iTunesSynced.
    public let sourceTypes: [String]
    public let visionLabels: [String]
    public let ocrText: String?
    /// True when a Vision feature print is stored for similarity search.
    public let hasFeaturePrint: Bool
    /// Distance to the probe asset when this result came from a similarity search. Lower is closer.
    public let similarityDistance: Float?

    public var aspectRatio: Double {
        guard pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    public init(
        id: String,
        cloudIdentifier: String? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        mediaType: PHAssetMediaType,
        mediaSubtypes: [String] = [],
        isFavorite: Bool,
        isHidden: Bool = false,
        durationSeconds: Double? = nil,
        filename: String? = nil,
        location: CLLocation? = nil,
        burstIdentifier: String? = nil,
        representsBurst: Bool = false,
        sourceTypes: [String] = [],
        visionLabels: [String] = [],
        ocrText: String? = nil,
        hasFeaturePrint: Bool = false,
        similarityDistance: Float? = nil
    ) {
        self.id = id
        self.cloudIdentifier = cloudIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.durationSeconds = durationSeconds
        self.filename = filename
        self.location = location
        self.burstIdentifier = burstIdentifier
        self.representsBurst = representsBurst
        self.sourceTypes = sourceTypes
        self.visionLabels = visionLabels
        self.ocrText = ocrText
        self.hasFeaturePrint = hasFeaturePrint
        self.similarityDistance = similarityDistance
    }

    public func withVision(labels: [String], ocrText: String?, hasFeaturePrint: Bool) -> PhotoResult {
        PhotoResult(
            id: id,
            cloudIdentifier: cloudIdentifier,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            mediaType: mediaType,
            mediaSubtypes: mediaSubtypes,
            isFavorite: isFavorite,
            isHidden: isHidden,
            durationSeconds: durationSeconds,
            filename: filename,
            location: location,
            burstIdentifier: burstIdentifier,
            representsBurst: representsBurst,
            sourceTypes: sourceTypes,
            visionLabels: labels,
            ocrText: ocrText,
            hasFeaturePrint: hasFeaturePrint,
            similarityDistance: similarityDistance
        )
    }

    public func withSimilarityDistance(_ distance: Float) -> PhotoResult {
        PhotoResult(
            id: id,
            cloudIdentifier: cloudIdentifier,
            creationDate: creationDate,
            modificationDate: modificationDate,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            mediaType: mediaType,
            mediaSubtypes: mediaSubtypes,
            isFavorite: isFavorite,
            isHidden: isHidden,
            durationSeconds: durationSeconds,
            filename: filename,
            location: location,
            burstIdentifier: burstIdentifier,
            representsBurst: representsBurst,
            sourceTypes: sourceTypes,
            visionLabels: visionLabels,
            ocrText: ocrText,
            hasFeaturePrint: hasFeaturePrint,
            similarityDistance: distance
        )
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
    var burstIdentifier: String?
    var sourceType: PHAssetSourceType?
    var fetchLimit: Int = 0
    var sortDescending: Bool = true
}

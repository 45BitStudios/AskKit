// Photos is not on Apple Watch, so this file builds empty there.
#if canImport(Photos)
import Foundation
import Photos
import CoreLocation

public final class PhotoLibraryService: Sendable {
    public init() {}

    // MARK: - Execute LLM-friendly request

    public func execute(_ request: PhotoQueryRequest) async -> [PhotoResult] {
        guard PhotoAuthorization.isAuthorized else { return [] }

        let filter = buildFilter(from: request)
        let fetchResult = fetchAssets(matching: filter)

        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        // Post-filters (location, text)
        assets = applyPostFilters(assets: assets, request: request)

        // Apply limit after post-filtering
        if let limit = request.limit, limit > 0, assets.count > limit {
            assets = Array(assets.prefix(limit))
        }

        return enrich(assets: assets)
    }

    // MARK: - Core fetch

    func fetchAssets(matching filter: PhotoFilter) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        var predicates: [NSPredicate] = []

        if let type = filter.mediaType {
            predicates.append(NSPredicate(format: "mediaType == %d", type.rawValue))
        }

        if filter.mediaSubtypes.rawValue != 0 {
            predicates.append(NSPredicate(format: "(mediaSubtypes & %d) != 0", filter.mediaSubtypes.rawValue))
        }

        if let fav = filter.isFavorite {
            predicates.append(NSPredicate(format: "isFavorite == %@", NSNumber(value: fav)))
        }

        if let hidden = filter.isHidden {
            predicates.append(NSPredicate(format: "isHidden == %@", NSNumber(value: hidden)))
        }

        if let minW = filter.minWidth {
            predicates.append(NSPredicate(format: "pixelWidth >= %d", minW))
        }
        if let maxW = filter.maxWidth {
            predicates.append(NSPredicate(format: "pixelWidth <= %d", maxW))
        }
        if let minH = filter.minHeight {
            predicates.append(NSPredicate(format: "pixelHeight >= %d", minH))
        }
        if let maxH = filter.maxHeight {
            predicates.append(NSPredicate(format: "pixelHeight <= %d", maxH))
        }

        if let range = filter.dateRange {
            predicates.append(NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                range.lowerBound as NSDate,
                range.upperBound as NSDate
            ))
        }

        if let burst = filter.burstIdentifier, !burst.isEmpty {
            predicates.append(NSPredicate(format: "burstIdentifier == %@", burst))
        }

        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: !filter.sortDescending)
        ]

        if filter.fetchLimit > 0 {
            options.fetchLimit = filter.fetchLimit
        }

        if let album = filter.album {
            return PHAsset.fetchAssets(in: album, options: options)
        }
        return PHAsset.fetchAssets(with: options)
    }

    // MARK: - Helpers

    private func buildFilter(from request: PhotoQueryRequest) -> PhotoFilter {
        var filter = PhotoFilter()

        switch request.mediaType {
        case .image: filter.mediaType = .image
        case .video: filter.mediaType = .video
        case .livePhoto: filter.mediaSubtypes = .photoLive
        case .any, .none: break
        }

        if let subtypes = request.mediaSubtypes {
            filter.mediaSubtypes = subtypes.reduce(into: PHAssetMediaSubtype()) { result, name in
                switch name.lowercased() {
                case "screenshot": result.insert(.photoScreenshot)
                case "live", "livephoto": result.insert(.photoLive)
                case "panorama": result.insert(.photoPanorama)
                case "hdr": result.insert(.photoHDR)
                case "depth": result.insert(.photoDepthEffect)
                case "timelapse": result.insert(.videoTimelapse)
                case "highframerate", "slowmo": result.insert(.videoHighFrameRate)
                default: break
                }
            }
        }

        filter.isFavorite = request.isFavorite
        filter.isHidden = request.isHidden
        filter.minWidth = request.minWidth
        filter.maxWidth = request.maxWidth
        filter.minHeight = request.minHeight
        filter.maxHeight = request.maxHeight

        if let start = request.startDate, let end = request.endDate {
            filter.dateRange = start...end
        } else if let start = request.startDate {
            filter.dateRange = start...Date.distantFuture
        } else if let end = request.endDate {
            filter.dateRange = Date.distantPast...end
        }

        filter.sortDescending = request.sortDescending ?? true
        // Photos rejects location and sourceType predicates. Scan, then keep the matches.
        filter.fetchLimit = Self.candidateFetchLimit(for: request)

        if let title = request.albumTitle {
            filter.album = findAlbum(title: title)
        }

        let burst = request.burstIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !burst.isEmpty {
            filter.burstIdentifier = burst
        }
        filter.sourceType = Self.sourceType(named: request.sourceType)

        return filter
    }

    /// A location, source-type, or similarity search must see past the newest page. Other searches keep `limit`.
    public static func candidateFetchLimit(for request: PhotoQueryRequest) -> Int {
        if request.similarToLocalIdentifier != nil { return 0 }
        if needsLocatedAssets(request) { return 0 }
        if sourceType(named: request.sourceType) != nil { return 0 }
        return request.limit ?? 0
    }

    public static func needsLocatedAssets(_ request: PhotoQueryRequest) -> Bool {
        request.locationLatitude != nil
            && request.locationLongitude != nil
            && request.locationRadiusMeters != nil
    }

    private func findAlbum(title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "localizedTitle == %@", title)
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        return result.firstObject
    }

    private func applyPostFilters(assets: [PHAsset], request: PhotoQueryRequest) -> [PHAsset] {
        var result = assets

        // Location radius
        if let lat = request.locationLatitude,
           let lon = request.locationLongitude,
           let radius = request.locationRadiusMeters {
            let center = CLLocation(latitude: lat, longitude: lon)
            result = result.filter { asset in
                guard let loc = asset.location else { return false }
                return loc.distance(from: center) <= radius
            }
        }

        if let source = Self.sourceType(named: request.sourceType) {
            result = result.filter { $0.sourceType.contains(source) }
        }

        // Text search (filename)
        if let text = request.textSearch?.lowercased(), !text.isEmpty {
            result = result.filter { asset in
                let resources = PHAssetResource.assetResources(for: asset)
                return resources.contains { $0.originalFilename.lowercased().contains(text) }
            }
        }

        return result
    }

    private func enrich(assets: [PHAsset]) -> [PhotoResult] {
        let cloudMap = cloudIdentifiers(for: assets)
        return assets.map { asset in
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename
            let duration = asset.mediaType == .video ? asset.duration : nil
            return PhotoResult(
                id: asset.localIdentifier,
                cloudIdentifier: cloudMap[asset.localIdentifier],
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                mediaType: asset.mediaType,
                mediaSubtypes: Self.subtypeNames(asset.mediaSubtypes),
                isFavorite: asset.isFavorite,
                isHidden: asset.isHidden,
                durationSeconds: duration,
                filename: filename,
                location: asset.location,
                burstIdentifier: asset.burstIdentifier,
                representsBurst: asset.representsBurst,
                sourceTypes: Self.sourceTypeNames(asset.sourceType),
                visionLabels: [],
                ocrText: nil
            )
        }
    }

    private func cloudIdentifiers(for assets: [PHAsset]) -> [String: String] {
        guard !assets.isEmpty else { return [:] }
        let ids = assets.map(\.localIdentifier)
        let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: ids)
        var result: [String: String] = [:]
        for (localID, mapping) in mappings {
            if case .success(let cloud) = mapping {
                result[localID] = cloud.stringValue
            }
        }
        return result
    }

    static func subtypeNames(_ subtypes: PHAssetMediaSubtype) -> [String] {
        var names: [String] = []
        if subtypes.contains(.photoScreenshot) { names.append("screenshot") }
        if subtypes.contains(.photoLive) { names.append("live") }
        if subtypes.contains(.photoPanorama) { names.append("panorama") }
        if subtypes.contains(.photoHDR) { names.append("hdr") }
        if subtypes.contains(.photoDepthEffect) { names.append("depth") }
        if subtypes.contains(.videoTimelapse) { names.append("timelapse") }
        if subtypes.contains(.videoHighFrameRate) { names.append("slowmo") }
        return names
    }

    static func sourceTypeNames(_ source: PHAssetSourceType) -> [String] {
        var names: [String] = []
        if source.contains(.typeUserLibrary) { names.append("userLibrary") }
        if source.contains(.typeCloudShared) { names.append("cloudShared") }
        if source.contains(.typeiTunesSynced) { names.append("iTunesSynced") }
        return names
    }

    static func sourceType(named raw: String?) -> PHAssetSourceType? {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "userlibrary", "library", "user": return .typeUserLibrary
        case "cloudshared", "shared", "icloudshared": return .typeCloudShared
        case "itunessynced", "itunes", "synced": return .typeiTunesSynced
        default: return nil
        }
    }

    // MARK: - Albums

    public func albums() -> [PHAssetCollection] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options)
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in
            albums.append(collection)
        }
        return albums
    }
}
#endif

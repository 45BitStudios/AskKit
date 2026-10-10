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

        // Enrich with filenames + optional vision data (lightweight)
        return await enrich(assets: assets)
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
        filter.fetchLimit = request.limit ?? 0

        if let title = request.albumTitle {
            filter.album = findAlbum(title: title)
        }

        return filter
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

        // Text search (filename)
        if let text = request.textSearch?.lowercased(), !text.isEmpty {
            result = result.filter { asset in
                let resources = PHAssetResource.assetResources(for: asset)
                return resources.contains { $0.originalFilename.lowercased().contains(text) }
            }
        }

        return result
    }

    private func enrich(assets: [PHAsset]) async -> [PhotoResult] {
        assets.map { asset in
            let resources = PHAssetResource.assetResources(for: asset)
            let filename = resources.first?.originalFilename

            return PhotoResult(
                id: asset.localIdentifier,
                cloudIdentifier: nil, // resolved lazily if needed
                creationDate: asset.creationDate,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                mediaType: asset.mediaType,
                isFavorite: asset.isFavorite,
                filename: filename,
                location: asset.location,
                visionLabels: [],
                ocrText: nil
            )
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

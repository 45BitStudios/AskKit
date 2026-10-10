import Foundation
import Photos
import UIKit

/// Thin wrapper around PHCachingImageManager for efficient thumbnail caching.
public final class PhotoCache: @unchecked Sendable {
    public let cachingManager = PHCachingImageManager()

    public init() {
        cachingManager.allowsCachingHighQualityImages = false
    }

    public func startCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 200, height: 200)) {
        cachingManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    public func stopCaching(assets: [PHAsset], targetSize: CGSize = CGSize(width: 200, height: 200)) {
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    public func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize = CGSize(width: 300, height: 300)
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast

            cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

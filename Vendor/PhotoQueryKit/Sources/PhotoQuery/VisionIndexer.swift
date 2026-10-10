import Foundation
import Photos
import Vision
import UIKit

/// Lightweight on-device indexer using Vision.
/// Stores classification labels and OCR text keyed by localIdentifier.
/// Suitable for foundation-model tool calling (“photos that contain a dog” etc.).
public actor VisionIndexer {
    public struct IndexEntry: Codable, Sendable {
        public let localIdentifier: String
        public var labels: [String]
        public var ocrText: String?
        public var featurePrintData: Data?   // optional VNFeaturePrintObservation data
        public let indexedAt: Date
    }

    private var index: [String: IndexEntry] = [:]
    private let maxConcurrent = 4

    public init() {}

    /// Index a batch of assets (call from background).
    public func index(assets: [PHAsset], includeFeaturePrint: Bool = false) async {
        await withTaskGroup(of: IndexEntry?.self) { group in
            var iterator = assets.makeIterator()
            for _ in 0..<maxConcurrent {
                if let asset = iterator.next() {
                    group.addTask { await self.indexOne(asset: asset, includeFeaturePrint: includeFeaturePrint) }
                }
            }

            while let entry = await group.next() {
                if let entry {
                    index[entry.localIdentifier] = entry
                }
                if let next = iterator.next() {
                    group.addTask { await self.indexOne(asset: next, includeFeaturePrint: includeFeaturePrint) }
                }
            }
        }
    }

    public func entry(for localIdentifier: String) -> IndexEntry? {
        index[localIdentifier]
    }

    public func searchLabels(containing query: String) -> [String] {
        let q = query.lowercased()
        return index.values
            .filter { entry in
                entry.labels.contains { $0.lowercased().contains(q) }
                || (entry.ocrText?.lowercased().contains(q) ?? false)
            }
            .map(\.localIdentifier)
    }

    public func allEntries() -> [IndexEntry] {
        Array(index.values)
    }

    // MARK: - Private

    private func indexOne(asset: PHAsset, includeFeaturePrint: Bool) async -> IndexEntry? {
        guard asset.mediaType == .image else { return nil }

        let image = await loadThumbnail(asset: asset, size: CGSize(width: 512, height: 512))
        guard let cgImage = image?.cgImage else { return nil }

        var labels: [String] = []
        var ocr: String?

        // Classification
        let classifyRequest = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([classifyRequest])
        if let results = classifyRequest.results {
            labels = results
                .filter { $0.confidence > 0.3 }
                .prefix(8)
                .map(\.identifier)
        }

        // OCR
        let ocrRequest = VNRecognizeTextRequest()
        ocrRequest.recognitionLevel = .fast
        try? handler.perform([ocrRequest])
        if let observations = ocrRequest.results {
            ocr = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }

        var featureData: Data?
        if includeFeaturePrint {
            let fpRequest = VNGenerateImageFeaturePrintRequest()
            try? handler.perform([fpRequest])
            if let observation = fpRequest.results?.first as? VNFeaturePrintObservation {
                featureData = try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
            }
        }

        return IndexEntry(
            localIdentifier: asset.localIdentifier,
            labels: labels,
            ocrText: ocr,
            featurePrintData: featureData,
            indexedAt: Date()
        )
    }

    private func loadThumbnail(asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.resizeMode = .fast

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

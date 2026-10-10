import Foundation
import Photos

/// High-level facade intended for foundation-model / tool-calling integration.
public actor PhotoQuery {
    public static let shared = PhotoQuery()

    private let library = PhotoLibraryService()
    private let vision = VisionIndexer()
    public let cache = PhotoCache()

    private init() {}

    // MARK: - Authorization

    public func ensureAuthorized() async -> Bool {
        let status = await PhotoAuthorization.request()
        return status == .authorized || status == .limited
    }

    // MARK: - Structured query (best for LLMs)

    /// Execute a structured request. Ideal for tool calling from a foundation model.
    public func query(_ request: PhotoQueryRequest) async -> [PhotoResult] {
        await library.execute(request)
    }

    /// Convenience: parse a simple natural-language-ish string into a request.
    /// For production, prefer your foundation model emitting `PhotoQueryRequest` JSON directly.
    public func query(naturalLanguage text: String) async -> [PhotoResult] {
        let request = Self.parseNaturalLanguage(text)
        return await library.execute(request)
    }

    // MARK: - Vision indexing

    /// Index a set of local identifiers (or all recent images).
    public func indexRecentImages(limit: Int = 200, includeFeaturePrint: Bool = false) async {
        var request = PhotoQueryRequest()
        request.mediaType = .image
        request.limit = limit
        request.sortDescending = true

        let results = await library.execute(request)
        let assets = results.compactMap { result -> PHAsset? in
            PHAsset.fetchAssets(withLocalIdentifiers: [result.id], options: nil).firstObject
        }
        await vision.index(assets: assets, includeFeaturePrint: includeFeaturePrint)
    }

    public func visionSearch(query: String) async -> [String] {
        await vision.searchLabels(containing: query)
    }

    // MARK: - Helpers

    public func albums() -> [String] {
        library.albums().compactMap(\.localizedTitle)
    }

    // MARK: - Simple NL parser (fallback)

    private static func parseNaturalLanguage(_ text: String) -> PhotoQueryRequest {
        var request = PhotoQueryRequest()
        let lower = text.lowercased()

        // Pixel size
        if let range = lower.range(of: #"(\d+)\s*px"# , options: .regularExpression) {
            let numStr = lower[range].filter(\.isNumber)
            if let px = Int(numStr) {
                if lower.contains("wider") || lower.contains("width") || lower.contains("horizontal") {
                    request.minWidth = px
                } else if lower.contains("taller") || lower.contains("height") {
                    request.minHeight = px
                } else {
                    request.minWidth = px
                    request.minHeight = px
                }
            }
        }

        // Dates (very simple)
        if lower.contains("last week") {
            request.startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())
        } else if lower.contains("last month") {
            request.startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())
        } else if lower.contains("this year") {
            let comps = Calendar.current.dateComponents([.year], from: Date())
            request.startDate = Calendar.current.date(from: comps)
        }

        // Favorites
        if lower.contains("favorite") || lower.contains("favourites") {
            request.isFavorite = true
        }

        // Screenshots
        if lower.contains("screenshot") {
            request.mediaSubtypes = ["screenshot"]
        }

        // Media type
        if lower.contains("video") || lower.contains("videos") {
            request.mediaType = .video
        } else if lower.contains("photo") || lower.contains("image") || lower.contains("picture") {
            request.mediaType = .image
        }

        // Text search fallback
        if request.textSearch == nil {
            request.textSearch = text
        }

        request.limit = 100
        return request
    }
}

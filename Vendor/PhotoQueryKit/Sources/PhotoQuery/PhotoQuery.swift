import Foundation
import Photos

/// High-level facade intended for foundation-model / tool-calling integration.
public actor PhotoQuery {
    public static let shared = PhotoQuery()

    private let library = PhotoLibraryService()
    private let vision = VisionIndexer()
    private let store: PhotoIndexStore
    private var lastIndexedAt: Date?
    private var didLoadStore = false
    public let cache = PhotoCache()

    /// - Parameter storeURL: Override the on-disk index location. Nil uses Application Support.
    public init(storeURL: URL? = nil) {
        self.store = PhotoIndexStore(fileURL: storeURL)
    }

    // MARK: - Authorization

    public func ensureAuthorized() async -> Bool {
        let status = await PhotoAuthorization.request()
        return status == .authorized || status == .limited
    }

    // MARK: - Structured query (best for LLMs)

    /// Execute a structured request. Ideal for tool calling from a foundation model.
    /// Attaches Vision labels and OCR from the persisted index when present.
    public func query(_ request: PhotoQueryRequest) async -> [PhotoResult] {
        await loadStoreIfNeeded()
        let results = await library.execute(request)
        return await attachVision(results)
    }

    /// Convenience: parse a simple natural-language-ish string into a request.
    /// For production, prefer your foundation model emitting `PhotoQueryRequest` JSON directly.
    public func query(naturalLanguage text: String) async -> [PhotoResult] {
        let request = Self.parseNaturalLanguage(text)
        return await query(request)
    }

    // MARK: - Vision indexing

    /// How many assets currently have Vision labels or OCR in the index.
    public func indexedCount() async -> Int {
        await loadStoreIfNeeded()
        return await vision.indexedCount()
    }

    /// When the index was last saved after an indexing pass. Nil until the first save.
    public func lastIndexDate() async -> Date? {
        await loadStoreIfNeeded()
        return lastIndexedAt
    }

    /// Writes the in-memory index and ``lastIndexDate`` to Application Support.
    @discardableResult
    public func saveIndex(lastIndexedAt date: Date? = nil) async -> Bool {
        await loadStoreIfNeeded()
        if let date {
            lastIndexedAt = date
        }
        let snapshot = PhotoIndexSnapshot(
            lastIndexedAt: lastIndexedAt,
            entries: await vision.exportEntries()
        )
        do {
            try store.save(snapshot)
            return true
        } catch {
            return false
        }
    }

    /// Loads the on-disk index into memory if needed.
    public func loadIndex() async {
        await loadStoreIfNeeded()
    }

    /// Index recent images. Reports progress for UI. Already-indexed assets are skipped.
    /// Saves the index and updates ``lastIndexDate`` when the pass finishes.
    public func indexRecentImages(
        limit: Int = 200,
        includeFeaturePrint: Bool = false,
        onProgress: (@Sendable (PhotoIndexProgress) -> Void)? = nil
    ) async {
        await loadStoreIfNeeded()
        var request = PhotoQueryRequest()
        request.mediaType = .image
        request.limit = limit
        request.sortDescending = true

        let results = await library.execute(request)
        let assets = assets(from: results)
        await vision.index(assets: assets, includeFeaturePrint: includeFeaturePrint, onProgress: onProgress)
        await finishIndexingPass()
    }

    /// Indexes photos newer than ``lastIndexDate``.
    /// When there is no saved date, indexes the most recent `limit` images instead.
    /// Saves the index and updates ``lastIndexDate`` when the pass finishes.
    public func indexNewImagesSinceLastIndex(
        limit: Int = 200,
        includeFeaturePrint: Bool = false,
        onProgress: (@Sendable (PhotoIndexProgress) -> Void)? = nil
    ) async {
        await loadStoreIfNeeded()
        var request = PhotoQueryRequest()
        request.mediaType = .image
        request.limit = limit
        request.sortDescending = true
        if let since = lastIndexedAt {
            request.startDate = since
        }

        let results = await library.execute(request)
        let assets = assets(from: results)
        await vision.index(assets: assets, includeFeaturePrint: includeFeaturePrint, onProgress: onProgress)
        await finishIndexingPass()
    }

    /// Load the persisted index, then index only photos newer than the last save.
    /// Call from app launch. Safe to call repeatedly.
    public func prepareIndexOnLaunch(
        limit: Int = 200,
        includeFeaturePrint: Bool = false,
        onProgress: (@Sendable (PhotoIndexProgress) -> Void)? = nil
    ) async {
        await loadStoreIfNeeded()
        await indexNewImagesSinceLastIndex(
            limit: limit,
            includeFeaturePrint: includeFeaturePrint,
            onProgress: onProgress
        )
    }

    public func visionSearch(query: String) async -> [String] {
        await loadStoreIfNeeded()
        return await vision.searchLabels(containing: query)
    }

    // MARK: - Helpers

    public func albums() -> [String] {
        library.albums().compactMap(\.localizedTitle)
    }

    private func attachVision(_ results: [PhotoResult]) async -> [PhotoResult] {
        guard !results.isEmpty else { return results }
        var attached: [PhotoResult] = []
        attached.reserveCapacity(results.count)
        for result in results {
            if let entry = await vision.entry(for: result.id) {
                attached.append(result.withVision(labels: entry.labels, ocrText: entry.ocrText))
            } else {
                attached.append(result)
            }
        }
        return attached
    }

    private func loadStoreIfNeeded() async {
        guard !didLoadStore else { return }
        didLoadStore = true
        let snapshot = store.load()
        lastIndexedAt = snapshot.lastIndexedAt
        await vision.replaceAll(snapshot.entries)
    }

    private func finishIndexingPass() async {
        lastIndexedAt = Date()
        _ = await saveIndex(lastIndexedAt: lastIndexedAt)
    }

    private func assets(from results: [PhotoResult]) -> [PHAsset] {
        results.compactMap { result in
            PHAsset.fetchAssets(withLocalIdentifiers: [result.id], options: nil).firstObject
        }
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

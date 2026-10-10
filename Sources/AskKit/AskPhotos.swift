import Foundation
import FoundationModels
import Photos
import PhotoQueryKit
import SwiftUI

/// Photo library search for host specialists. Built on PhotoQueryKit.
///
/// Register `AskPhotos.specialist` on an assistant. A match runs before Apple specialists.
/// The host app needs `NSPhotoLibraryUsageDescription`.
///
/// Content search needs an on-device Vision index stored in Application Support (not CloudKit).
/// When that index is empty, AskKit shows “Photos need indexing” then “Indexing photos…”
/// with a count beside the thinking orb, then searches.
///
/// Call ``prepareIndexOnLaunch(limit:)`` at app launch to reload the saved index and index
/// only photos newer than ``lastIndexDate()``.
public enum AskPhotos {
    public static let toolName = "photos"
    public static let defaultSpecialistID = "photos"
    public static let defaultIndexLimit = 200

    public static let note = """
    Call the photos tool once with the filters the question named. \
    Say how many matches it found and name a few. \
    If a line says photos were indexed first, you may mention that briefly. \
    If it says Not allowed, say you cannot see the photo library. Do not invent photos.
    """

    /// A library-search question. Attached-photo questions such as "where was this photo taken" stay off.
    public static func matches(_ question: String) -> Bool {
        AskPhotosFocus.matches(question)
    }

    /// Host specialist that searches the photo library through PhotoQueryKit.
    public static func specialist(
        id: String = defaultSpecialistID,
        title: String = "Photos",
        symbolName: String = "photo.on.rectangle",
        workingTitle: String = "Searching photos"
    ) -> AskSpecialist {
        AskSpecialist(
            id: id,
            title: title,
            symbolName: symbolName,
            workingTitle: workingTitle,
            instructions: note,
            tools: { [AskPhotosTool(toolLedger: AskToolLedger())] },
            matches: matches
        )
    }

    /// How far the on-device Vision index has gotten.
    public static func indexStatus() async -> AskPhotosIndexStatus {
        await AskPhotosIndex.status()
    }

    /// When the persisted index was last saved. Nil until the first successful save.
    public static func lastIndexDate() async -> Date? {
        await PhotoQuery.shared.lastIndexDate()
    }

    /// Writes the current in-memory index and last-index date to disk.
    @discardableResult
    public static func saveIndex() async -> Bool {
        await PhotoQuery.shared.saveIndex()
    }

    /// Reloads the saved index, then indexes photos newer than ``lastIndexDate()``.
    /// Call from app launch. Updates the thinking line when a turn is active.
    @discardableResult
    public static func prepareIndexOnLaunch(limit: Int = defaultIndexLimit) async -> AskPhotosIndexStatus {
        await AskPhotosIndex.prepareOnLaunch(limit: limit)
    }

    /// Builds or refreshes the Vision index. Prefer ``prepareIndexOnLaunch(limit:)`` at launch.
    @discardableResult
    public static func warmIndex(limit: Int = defaultIndexLimit) async -> AskPhotosIndexStatus {
        await AskPhotosIndex.prepareOnLaunch(limit: limit)
    }
}

/// State of the on-device photo Vision index.
public enum AskPhotosIndexStatus: Equatable, Sendable {
    case idle
    case needed
    case indexing(completed: Int, total: Int)
    case ready(count: Int)

    public var indexedCount: Int {
        switch self {
        case .idle, .needed: 0
        case .indexing(_, _): 0
        case .ready(let count): count
        }
    }
}

/// Status copy and indexing for the photos specialist.
enum AskPhotosIndex {
    static let detail = "Photos"

    static func status() async -> AskPhotosIndexStatus {
        if AskPhotosIndexState.shared.isIndexing {
            let snap = AskPhotosIndexState.shared.snapshot
            return .indexing(completed: snap.completed, total: snap.total)
        }
        await PhotoQuery.shared.loadIndex()
        let count = await PhotoQuery.shared.indexedCount()
        if count == 0 { return .needed }
        return .ready(count: count)
    }

    /// App launch: load disk, index photos newer than the last save, persist again.
    @discardableResult
    static func prepareOnLaunch(limit: Int = AskPhotos.defaultIndexLimit) async -> AskPhotosIndexStatus {
        let allowed = await PhotoQuery.shared.ensureAuthorized()
        guard allowed else { return .needed }

        await PhotoQuery.shared.loadIndex()
        let before = await PhotoQuery.shared.indexedCount()
        let since = await PhotoQuery.shared.lastIndexDate()
        if before == 0 {
            await announceNeeded()
        } else if let since {
            await announce(AskPhotosIndexCopy.updating(since: since))
        }

        return await runIndex(limit: limit) {
            await PhotoQuery.shared.prepareIndexOnLaunch(limit: limit, onProgress: $0)
        }
    }

    /// Indexes when content search needs Vision and the store is still empty after load.
    @discardableResult
    static func ensureReady(limit: Int = AskPhotos.defaultIndexLimit, force: Bool = false) async -> AskPhotosIndexStatus {
        let allowed = await PhotoQuery.shared.ensureAuthorized()
        guard allowed else { return .needed }

        await PhotoQuery.shared.loadIndex()
        let count = await PhotoQuery.shared.indexedCount()
        if !force, count > 0 {
            return .ready(count: count)
        }

        if count == 0 {
            await announceNeeded()
        }

        return await runIndex(limit: limit) { onProgress in
            if count == 0 {
                await PhotoQuery.shared.indexRecentImages(limit: limit, onProgress: onProgress)
            } else {
                await PhotoQuery.shared.indexNewImagesSinceLastIndex(limit: limit, onProgress: onProgress)
            }
        }
    }

    private static func runIndex(
        limit: Int,
        body: (@escaping @Sendable (PhotoIndexProgress) -> Void) async -> Void
    ) async -> AskPhotosIndexStatus {
        AskPhotosIndexState.shared.begin(total: max(limit, 1))
        await announce(AskPhotosIndexCopy.indexing(completed: 0, total: max(limit, 1)))

        await body { progress in
            AskPhotosIndexState.shared.update(progress)
            let line = AskPhotosIndexCopy.indexing(completed: progress.completed, total: progress.total)
            if progress.isFinished || progress.completed == 0 || progress.completed % 4 == 0
                || progress.completed == progress.total {
                Task { @MainActor in
                    AskChatActivity.show(line.title, detail: line.detail, phase: .tool)
                }
            }
        }

        let indexed = await PhotoQuery.shared.indexedCount()
        AskPhotosIndexState.shared.finish(count: indexed)
        await announce(AskPhotosIndexCopy.ready(count: indexed))
        return .ready(count: indexed)
    }

    private static func announceNeeded() async {
        await announce(AskPhotosIndexCopy.needed)
    }

    @MainActor
    private static func announce(_ line: (title: String, detail: String)) {
        AskChatActivity.show(line.title, detail: line.detail, phase: .tool)
    }
}

/// Copy for the thinking orb while photos are indexed.
enum AskPhotosIndexCopy {
    static let needed = (title: "Photos need indexing", detail: "For content search")

    static func updating(since date: Date) -> (title: String, detail: String) {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        return ("Updating photo index…", "Since \(day)")
    }

    static func indexing(completed: Int, total: Int) -> (title: String, detail: String) {
        let safeTotal = max(total, 1)
        let safeCompleted = min(max(completed, 0), safeTotal)
        return ("Indexing photos…", "\(safeCompleted) of \(safeTotal)")
    }

    static func ready(count: Int) -> (title: String, detail: String) {
        if count <= 0 {
            return ("Searching photos", AskPhotosIndex.detail)
        }
        return ("Searching photos", "\(count) indexed")
    }

    static func indexedFact(count: Int) -> String {
        if count <= 0 { return "No recent photos were indexed." }
        if count == 1 { return "Indexed 1 recent photo for content search." }
        return "Indexed \(count) recent photos for content search."
    }
}

/// Shared progress while a Vision index pass runs.
final class AskPhotosIndexState: @unchecked Sendable {
    static let shared = AskPhotosIndexState()
    private let lock = NSLock()
    private var _isIndexing = false
    private var _completed = 0
    private var _total = 0

    var isIndexing: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isIndexing
    }

    var snapshot: (completed: Int, total: Int) {
        lock.lock(); defer { lock.unlock() }
        return (_completed, _total)
    }

    func begin(total: Int) {
        lock.lock()
        _isIndexing = true
        _completed = 0
        _total = max(total, 1)
        lock.unlock()
    }

    func update(_ progress: PhotoIndexProgress) {
        lock.lock()
        _completed = progress.completed
        _total = max(progress.total, 1)
        if progress.isFinished { _isIndexing = false }
        lock.unlock()
    }

    func finish(count: Int) {
        lock.lock()
        _isIndexing = false
        _completed = count
        _total = max(count, _total)
        lock.unlock()
    }
}

/// Words that mean search the library, not an attached picture.
enum AskPhotosFocus {
    static func matches(_ question: String) -> Bool {
        let folded = AskAppleCopy.folded(question)
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        if phrases.contains(where: { folded.localizedStandardContains($0) }) { return true }
        if tokens.contains(where: { libraryWords.contains($0) }) { return true }
        if tokens.contains("screenshots") || tokens.contains("screenshot") { return true }
        if tokens.contains(where: { ["favorite", "favorites", "favourite", "favourites"].contains($0) }) {
            return tokens.contains(where: { pictureWords.contains($0) })
        }
        // "photos of dogs", "pictures from June"
        if tokens.contains(where: { pictureWords.contains($0) }) {
            return tokens.contains("of") || tokens.contains("from") || tokens.contains("in")
                || tokens.contains("wider") || tokens.contains("taller")
                || tokens.contains("album") || tokens.contains("library")
        }
        return false
    }

    private static let phrases = [
        "camera roll", "photo library", "live photo", "live photos",
        "find photos", "find pictures", "find images", "search photos", "search pictures",
        "photos of", "pictures of", "images of", "photos from", "pictures from", "images from",
        "my photos", "my pictures", "my screenshots"
    ]

    private static let libraryWords: Set<String> = [
        "screenshot", "screenshots", "panorama", "panoramas", "album", "albums",
        "roll", "library"
    ]

    private static let pictureWords: Set<String> = [
        "photo", "photos", "picture", "pictures", "image", "images"
    ]
}

/// Builds a PhotoQueryKit request from tool arguments or a question.
enum AskPhotosQuery {
    static let maximumLimit = 25
    static let defaultLimit = 12

    static func request(
        mediaType: String?,
        minWidth: Int?,
        maxWidth: Int?,
        minHeight: Int?,
        maxHeight: Int?,
        daysAgo: Int?,
        throughDaysAgo: Int?,
        isFavorite: Bool?,
        subtype: String?,
        albumTitle: String?,
        textSearch: String?,
        limit: Int?
    ) -> PhotoQueryRequest {
        var request = PhotoQueryRequest()
        request.mediaType = media(mediaType)
        request.minWidth = positive(minWidth)
        request.maxWidth = positive(maxWidth)
        request.minHeight = positive(minHeight)
        request.maxHeight = positive(maxHeight)
        request.isFavorite = isFavorite
        if let subtype, !subtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.mediaSubtypes = [subtype.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        }
        let album = trimmed(albumTitle)
        if !album.isEmpty { request.albumTitle = album }
        let search = trimmed(textSearch)
        if !search.isEmpty { request.textSearch = search }
        applyDates(daysAgo: daysAgo, throughDaysAgo: throughDaysAgo, to: &request)
        let capped = min(max(limit ?? defaultLimit, 1), maximumLimit)
        request.limit = capped
        request.sortDescending = true
        return request
    }

    /// Fills gaps the model left empty from the question text.
    static func enrich(_ request: PhotoQueryRequest, question: String) -> PhotoQueryRequest {
        var next = request
        let folded = AskAppleCopy.folded(question)
        let tokens = Set(AskAppleCopy.foldedTokens(question))

        if next.mediaType == nil {
            if tokens.contains("video") || tokens.contains("videos") {
                next.mediaType = .video
            } else if folded.localizedStandardContains("live photo") {
                next.mediaType = .livePhoto
            } else if tokens.contains(where: { ["photo", "photos", "picture", "pictures", "image", "images", "screenshot", "screenshots"].contains($0) }) {
                next.mediaType = .image
            }
        }

        if next.mediaSubtypes == nil || next.mediaSubtypes?.isEmpty == true {
            if tokens.contains("screenshot") || tokens.contains("screenshots") {
                next.mediaSubtypes = ["screenshot"]
            } else if folded.localizedStandardContains("live photo") {
                next.mediaSubtypes = ["live"]
            } else if tokens.contains("panorama") || tokens.contains("panoramas") {
                next.mediaSubtypes = ["panorama"]
            }
        }

        if next.isFavorite == nil,
           tokens.contains(where: { ["favorite", "favorites", "favourite", "favourites"].contains($0) }) {
            next.isFavorite = true
        }

        if next.startDate == nil {
            if folded.localizedStandardContains("last week") {
                next.startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())
            } else if folded.localizedStandardContains("last month") {
                next.startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())
            } else if folded.localizedStandardContains("this year") {
                let comps = Calendar.current.dateComponents([.year], from: Date())
                next.startDate = Calendar.current.date(from: comps)
            }
        }

        if next.minWidth == nil, let px = pixelSize(in: folded) {
            if folded.contains("wider") || folded.contains("width") {
                next.minWidth = px
            } else if folded.contains("taller") || folded.contains("height") {
                next.minHeight = px
            } else {
                next.minWidth = px
            }
        }

        if next.textSearch == nil || next.textSearch?.isEmpty == true {
            if let of = contentAfter(folded, marker: " of ") {
                next.textSearch = of
            }
        }

        if next.limit == nil || next.limit == 0 {
            next.limit = defaultLimit
        }
        return next
    }

    private static func media(_ raw: String?) -> PhotoQueryRequest.MediaType? {
        switch AskAppleCopy.folded(raw ?? "") {
        case "image", "photo", "photos", "picture", "pictures": .image
        case "video", "videos": .video
        case "livephoto", "live", "live photo", "live photos": .livePhoto
        case "any": .any
        default: nil
        }
    }

    private static func applyDates(daysAgo: Int?, throughDaysAgo: Int?, to request: inout PhotoQueryRequest) {
        let calendar = Calendar.current
        let now = Date()
        if let daysAgo {
            let start = calendar.date(byAdding: .day, value: -max(daysAgo, 0), to: now)
            request.startDate = start
        }
        if let throughDaysAgo {
            let end = calendar.date(byAdding: .day, value: -max(throughDaysAgo, 0), to: now)
            request.endDate = end
        }
    }

    private static func pixelSize(in folded: String) -> Int? {
        guard let range = folded.range(of: #"(\d+)\s*px"#, options: .regularExpression) else { return nil }
        let digits = folded[range].filter(\.isNumber)
        return Int(digits)
    }

    private static func contentAfter(_ folded: String, marker: String) -> String? {
        guard let range = folded.range(of: marker) else { return nil }
        var rest = String(folded[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        let stop: Set<String> = [
            "from", "in", "on", "last", "this", "my", "the", "a", "an", "wider", "taller", "than"
        ]
        var words = rest.split(separator: " ").map(String.init)
        if let cut = words.firstIndex(where: { stop.contains($0) }) {
            words = Array(words.prefix(cut))
        }
        rest = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.count >= 2, rest.count <= 40 else { return nil }
        return rest
    }

    private static func positive(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Lines the model and the card both read. None of them contain an equals sign.
enum AskPhotosLine {
    static let denied = AskAppleCopy.denied
    static let empty = "No matching photos."
    static let maximumListed = 8

    static func spoken(_ lines: [String]) -> String? {
        let kept = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let head = kept.first else { return nil }
        if head == denied || head == empty { return head }
        if head.hasPrefix("Found ") { return head }
        if head.hasPrefix("Indexed ") {
            if let found = kept.first(where: { $0.hasPrefix("Found ") }) { return found }
            return head
        }
        return kept.prefix(3).joined(separator: " ")
    }

    static func format(
        _ results: [PhotoResult],
        request: PhotoQueryRequest,
        indexedCount: Int? = nil
    ) -> String {
        var rows: [String] = []
        if let indexedCount {
            rows.append(AskPhotosIndexCopy.indexedFact(count: indexedCount))
        }
        guard !results.isEmpty else {
            rows.append(empty)
            return rows.joined(separator: "\n")
        }
        let count = results.count
        let kind = label(for: request)
        rows.append("Found \(count) \(kind).")
        for result in results.prefix(maximumListed) {
            rows.append(row(result))
        }
        if results.count > maximumListed {
            rows.append("And \(results.count - maximumListed) more.")
        }
        return rows.joined(separator: "\n")
    }

    static func row(_ result: PhotoResult) -> String {
        var parts: [String] = []
        if let name = result.filename, !name.isEmpty {
            parts.append(AskAppleCopy.plain(name, limit: 48))
        } else {
            parts.append(mediaName(result.mediaType))
        }
        if let date = result.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append("\(result.pixelWidth)×\(result.pixelHeight)")
        if result.isFavorite { parts.append("favorite") }
        if !result.visionLabels.isEmpty {
            let labels = result.visionLabels.prefix(3).joined(separator: ", ")
            parts.append(AskAppleCopy.plain(labels, limit: 40))
        }
        return parts.joined(separator: " · ")
    }

    private static func label(for request: PhotoQueryRequest) -> String {
        if request.mediaSubtypes?.contains(where: { $0.lowercased() == "screenshot" }) == true {
            return request.limit == 1 ? "screenshot" : "screenshots"
        }
        if request.isFavorite == true {
            return "favorite photos"
        }
        switch request.mediaType {
        case .video: return request.limit == 1 ? "video" : "videos"
        case .livePhoto: return request.limit == 1 ? "Live Photo" : "Live Photos"
        case .image, .any, .none: return request.limit == 1 ? "photo" : "photos"
        }
    }

    private static func mediaName(_ type: PHAssetMediaType) -> String {
        switch type {
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Photo"
        default: "Item"
        }
    }
}

enum AskPhotosRead {
    static func lines(_ request: PhotoQueryRequest) async -> String {
        let allowed = await PhotoQuery.shared.ensureAuthorized()
        guard allowed else { return AskPhotosLine.denied }

        let search = request.textSearch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let needsVision = !search.isEmpty
        var justIndexed: Int?

        if needsVision {
            let before = await PhotoQuery.shared.indexedCount()
            if before == 0 {
                let status = await AskPhotosIndex.ensureReady()
                if case .ready(let count) = status {
                    justIndexed = count
                }
            }
            await MainActor.run {
                let ready = AskPhotosIndexCopy.ready(count: justIndexed ?? before)
                AskChatActivity.show(ready.title, detail: ready.detail, phase: .tool)
            }
        }

        var results = await PhotoQuery.shared.query(request)
        if results.isEmpty, needsVision {
            let ids = await PhotoQuery.shared.visionSearch(query: search)
            if !ids.isEmpty {
                var fallback = request
                fallback.textSearch = nil
                fallback.limit = AskPhotosQuery.maximumLimit
                let broad = await PhotoQuery.shared.query(fallback)
                let matched = Set(ids)
                results = broad.filter { matched.contains($0.id) }
                if let limit = request.limit, limit > 0, results.count > limit {
                    results = Array(results.prefix(limit))
                }
            }
        }
        return AskPhotosLine.format(results, request: request, indexedCount: justIndexed)
    }
}

struct AskPhotosTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    let name = AskPhotos.toolName
    let description = """
    Search the photo library. Pass mediaType image, video, livePhoto, or any. \
    Pass subtype screenshot, live, or panorama when named. \
    Pass daysAgo for how far back to look, such as 7 or 30. \
    Pass isFavorite true for favorites. Pass albumTitle for an album. \
    Pass textSearch for a filename or content word such as dog. \
    Pass minWidth for a pixel width floor. Pass limit up to 25. Call once.
    """

    @Generable
    struct Arguments {
        @Guide(description: "image, video, livePhoto, or any.", .anyOf(["image", "video", "livePhoto", "any"]))
        var mediaType: String?
        @Guide(description: "Minimum pixel width. Leave empty when unused.", .range(1...20_000))
        var minWidth: Int?
        @Guide(description: "Maximum pixel width. Leave empty when unused.", .range(1...20_000))
        var maxWidth: Int?
        @Guide(description: "Minimum pixel height. Leave empty when unused.", .range(1...20_000))
        var minHeight: Int?
        @Guide(description: "Maximum pixel height. Leave empty when unused.", .range(1...20_000))
        var maxHeight: Int?
        @Guide(description: "How many days back to start. 7 is last week. 30 is last month. Leave empty for any time.", .range(0...3_650))
        var daysAgo: Int?
        @Guide(description: "How many days back the range ends. Leave empty for now.", .range(0...3_650))
        var throughDaysAgo: Int?
        @Guide(description: "True for favorites only. Leave empty otherwise.")
        var isFavorite: Bool?
        @Guide(description: "screenshot, live, or panorama when named. Leave empty otherwise.", .anyOf(["screenshot", "live", "panorama", "hdr", "depth", "timelapse", "slowmo"]))
        var subtype: String?
        @Guide(description: "Album title. Leave empty when unused.")
        var albumTitle: String?
        @Guide(description: "A filename or content word such as dog or receipt. Leave empty when unused.")
        var textSearch: String?
        @Guide(description: "How many results to return, from 1 to 25.", .range(1...AskPhotosQuery.maximumLimit))
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let request = AskPhotosQuery.request(
            mediaType: arguments.mediaType,
            minWidth: arguments.minWidth,
            maxWidth: arguments.maxWidth,
            minHeight: arguments.minHeight,
            maxHeight: arguments.maxHeight,
            daysAgo: arguments.daysAgo,
            throughDaysAgo: arguments.throughDaysAgo,
            isFavorite: arguments.isFavorite,
            subtype: arguments.subtype,
            albumTitle: arguments.albumTitle,
            textSearch: arguments.textSearch,
            limit: arguments.limit
        )
        let label = summary(request)
        return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: label) {
            await AskPhotosRead.lines(request)
        }
    }

    private func summary(_ request: PhotoQueryRequest) -> String {
        var parts: [String] = []
        if let type = request.mediaType { parts.append(type.rawValue) }
        if let subtypes = request.mediaSubtypes, !subtypes.isEmpty {
            parts.append(subtypes.joined(separator: "+"))
        }
        if request.isFavorite == true { parts.append("favorites") }
        if let search = request.textSearch, !search.isEmpty { parts.append(search) }
        if let album = request.albumTitle, !album.isEmpty { parts.append(album) }
        if let days = request.startDate {
            let delta = Calendar.current.dateComponents([.day], from: days, to: Date()).day ?? 0
            parts.append("\(max(delta, 0))d")
        }
        if parts.isEmpty { parts.append("search") }
        return parts.joined(separator: " ")
    }
}

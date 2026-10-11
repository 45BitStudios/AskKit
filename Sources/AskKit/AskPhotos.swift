import CoreLocation
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
    Pass action albums to list album titles. \
    For a named place, pass latitude and longitude when you know them. Leave radiusMeters empty unless the person named a distance. \
    Pass isHidden for hidden items and newestFirst false for oldest first. \
    Pass burstIdentifier for a burst group, sourceType for userLibrary, cloudShared, or iTunesSynced, \
    and similarTo for photos visually like another local photo id. \
    Say how many matches it found. The card shows the photos. Do not list file names or photo ids. \
    If a line says photos were indexed first, you may mention that briefly. \
    If it says Not allowed, say you cannot see the photo library. Do not invent photos. \
    Answer this question only. Do not repeat a song, an album, or anything from earlier in the chat.
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
        let tokenList = AskAppleCopy.foldedTokens(question)
        let tokens = Set(tokenList)
        if phrases.contains(where: { folded.localizedStandardContains($0) }) { return true }
        if tokens.contains(where: { libraryWords.contains($0) }) { return true }
        if tokens.contains("screenshots") || tokens.contains("screenshot") { return true }
        if tokens.contains("albums") || (tokens.contains("album") && !tokens.contains("music")) { return true }
        if tokens.contains(where: { ["favorite", "favorites", "favourite", "favourites"].contains($0) }) {
            return tokens.contains(where: { pictureWords.contains($0) })
        }
        // "photos of dogs", "pictures from June", "photos near 37.3, -122.0"
        if tokens.contains(where: { pictureWords.contains($0) }) {
            if AskPhotosQuery.coordinates(in: folded) != nil { return true }
            if tokens.contains("of") || tokens.contains("from") || tokens.contains("in")
                || tokens.contains("near") || tokens.contains("around")
                || tokens.contains("wider") || tokens.contains("taller")
                || tokens.contains("album") || tokens.contains("library") {
                return true
            }
            // "What photos did I take yesterday?" is the library. "Where was this photo taken?" is an attachment.
            if !pointsAtAttachment(tokenList) {
                if tokens.contains(where: { captureWords.contains($0) }) { return true }
                if tokens.contains(where: { AskAppleCopy.dayWords.contains($0) }) { return true }
            }
        }
        return false
    }

    /// "this photo" points at an attachment. "this morning" does not.
    private static func pointsAtAttachment(_ tokens: [String]) -> Bool {
        for index in tokens.indices.dropLast() {
            if demonstratives.contains(tokens[index]), pictureWords.contains(tokens[index + 1]) {
                return true
            }
        }
        return false
    }

    private static let phrases = [
        "camera roll", "photo library", "live photo", "live photos",
        "find photos", "find pictures", "find images", "search photos", "search pictures",
        "photos of", "pictures of", "images of", "photos from", "pictures from", "images from",
        "photos near", "pictures near", "images near", "photos around", "pictures around",
        "list albums", "my albums", "photo albums",
        "hidden photos", "hidden pictures", "oldest photos", "oldest first",
        "similar photos", "photos like this", "looks like", "burst photos",
        "my photos", "my pictures", "my screenshots"
    ]

    private static let libraryWords: Set<String> = [
        "screenshot", "screenshots", "panorama", "panoramas", "album", "albums",
        "roll", "library", "hdr", "timelapse", "slowmo", "burst", "bursts"
    ]

    private static let pictureWords: Set<String> = [
        "photo", "photos", "picture", "pictures", "image", "images"
    ]

    private static let captureWords: Set<String> = [
        "take", "took", "taken", "taking"
    ]

    private static let demonstratives: Set<String> = [
        "this", "that", "these", "those"
    ]
}

/// Builds a PhotoQueryKit request from tool arguments or a question.
enum AskPhotosQuery {
    static let maximumLimit = 25
    static let defaultLimit = 12
    /// Used when latitude and longitude are set but no radius is passed.
    static let defaultRadiusMeters = 1_000.0
    /// A named place with no stated distance, such as "near Austin". A coordinate pair stays at the point default.
    static let placeRadiusMeters = 40_000.0
    static let maximumRadiusMeters = 50_000.0

    static func request(
        mediaType: String?,
        minWidth: Int?,
        maxWidth: Int?,
        minHeight: Int?,
        maxHeight: Int?,
        daysAgo: Int?,
        throughDaysAgo: Int?,
        isFavorite: Bool?,
        isHidden: Bool?,
        subtype: String?,
        albumTitle: String?,
        textSearch: String?,
        latitude: Double?,
        longitude: Double?,
        radiusMeters: Double?,
        newestFirst: Bool?,
        burstIdentifier: String?,
        sourceType: String?,
        similarTo: String?,
        limit: Int?
    ) -> PhotoQueryRequest {
        var request = PhotoQueryRequest()
        request.mediaType = media(mediaType)
        request.minWidth = positive(minWidth)
        request.maxWidth = positive(maxWidth)
        request.minHeight = positive(minHeight)
        request.maxHeight = positive(maxHeight)
        request.isFavorite = isFavorite
        request.isHidden = isHidden
        if let subtype, !subtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.mediaSubtypes = [subtype.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        }
        let album = trimmed(albumTitle)
        if !album.isEmpty { request.albumTitle = album }
        let search = trimmed(textSearch)
        if !search.isEmpty { request.textSearch = search }
        applyDates(daysAgo: daysAgo, throughDaysAgo: throughDaysAgo, to: &request)
        applyLocation(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters, to: &request)
        let burst = trimmed(burstIdentifier)
        if !burst.isEmpty { request.burstIdentifier = burst }
        let source = trimmed(sourceType)
        if !source.isEmpty { request.sourceType = source }
        let similar = trimmed(similarTo)
        if !similar.isEmpty { request.similarToLocalIdentifier = similar }
        let capped = min(max(limit ?? defaultLimit, 1), maximumLimit)
        request.limit = capped
        request.sortDescending = newestFirst ?? true
        return request
    }

    /// A library search built only from the question. Used when the model never called the tool.
    static func fromQuestion(_ question: String) -> PhotoQueryRequest {
        enrich(PhotoQueryRequest(), question: question)
    }

    /// List album titles. A photo search that names an album stays a search.
    static func listsAlbums(_ question: String) -> Bool {
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        if tokens.contains("music") { return false }
        if tokens.contains(where: { ["photo", "photos", "picture", "pictures", "image", "images"].contains($0) }) {
            return false
        }
        return tokens.contains("album") || tokens.contains("albums")
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
            } else if tokens.contains("hdr") {
                next.mediaSubtypes = ["hdr"]
            } else if tokens.contains("depth") || folded.localizedStandardContains("portrait mode") {
                next.mediaSubtypes = ["depth"]
            } else if tokens.contains("timelapse") || tokens.contains("time-lapse") {
                next.mediaSubtypes = ["timelapse"]
            } else if tokens.contains("slowmo") || tokens.contains("slow-motion")
                        || folded.localizedStandardContains("slow motion") {
                next.mediaSubtypes = ["slowmo"]
            }
        }

        if next.isFavorite == nil,
           tokens.contains(where: { ["favorite", "favorites", "favourite", "favourites"].contains($0) }) {
            next.isFavorite = true
        }

        if next.isHidden == nil,
           tokens.contains(where: { ["hidden", "hide", "concealed"].contains($0) }) {
            next.isHidden = true
        }

        if folded.localizedStandardContains("oldest first") || folded.localizedStandardContains("oldest photos") {
            next.sortDescending = false
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

        if let window = takenDay(in: question) {
            next.startDate = window.start
            next.endDate = window.end.addingTimeInterval(-1)
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

        if next.locationLatitude == nil || next.locationLongitude == nil,
           let pair = coordinates(in: folded) {
            applyLocation(
                latitude: pair.latitude,
                longitude: pair.longitude,
                radiusMeters: next.locationRadiusMeters ?? radius(in: folded),
                to: &next
            )
        } else if next.locationLatitude != nil, next.locationLongitude != nil, next.locationRadiusMeters == nil {
            next.locationRadiusMeters = radius(in: folded) ?? defaultRadiusMeters
        }

        let namedPlace = place(in: folded)
        if !namedPlace.isEmpty {
            if let explicit = radius(in: folded) {
                next.locationRadiusMeters = min(max(explicit, 1), maximumRadiusMeters)
            } else if coordinates(in: folded) == nil {
                next.locationRadiusMeters = placeRadiusMeters
            }
        }

        if next.textSearch == nil || next.textSearch?.isEmpty == true {
            if let of = contentAfter(folded, marker: " of ") {
                // A place or a coordinate pair is not a filename.
                if coordinates(in: of) == nil, namedPlace != of {
                    next.textSearch = of
                }
            }
        }

        if next.limit == nil || next.limit == 0 {
            next.limit = defaultLimit
        }
        return next
    }

    /// Yesterday, today, tonight, or tomorrow as one calendar day. Nil for any other wording.
    static func takenDay(in question: String, now: Date = Date(), calendar: Calendar = .current) -> AskCalendarWindow? {
        let tokens = Set(AskAppleCopy.foldedTokens(question))
        guard tokens.contains(where: { ["yesterday", "today", "tonight", "tomorrow"].contains($0) }),
              let offset = AskCalendarWindow.offset(namedIn: question, now: now, calendar: calendar),
              (-1...1).contains(offset) else {
            return nil
        }
        return AskCalendarWindow.day(offset: offset, now: now, calendar: calendar)
    }

    /// The place after "near", "around", or "close to". A coordinate pair is not a place.
    /// "within 2 km of Austin" uses the words after "of". Tests do not geocode this string.
    static func place(in question: String) -> String {
        let folded = AskAppleCopy.folded(question)
        if let named = phrase(after: [" near ", " around ", " close to "], in: folded),
           coordinates(in: named) == nil {
            return named
        }
        if radius(in: folded) != nil,
           let named = phrase(after: [" of "], in: folded),
           coordinates(in: named) == nil {
            return named
        }
        return ""
    }

    /// Fills coordinates for a named place. A coordinate pair already in the question is left as parsed.
    static func resolvePlace(_ request: PhotoQueryRequest, question: String) async -> PhotoQueryRequest {
        var next = request
        let named = place(in: question)
        guard !named.isEmpty, coordinates(in: question) == nil else { return next }
        guard let found = await AskLocationRead.coordinate(forPlace: named) else { return next }
        next.locationLatitude = found.coordinate.latitude
        next.locationLongitude = found.coordinate.longitude
        if next.locationRadiusMeters == nil {
            next.locationRadiusMeters = radius(in: question) ?? placeRadiusMeters
        }
        return next
    }

    /// Latitude and longitude from text such as `37.3349, -122.0090` or `lat 37.33 lon -122.01`.
    static func coordinates(in text: String) -> (latitude: Double, longitude: Double)? {
        let folded = AskAppleCopy.folded(text)
        if let pair = labeledCoordinates(in: folded) { return pair }
        guard let range = folded.range(
            of: #"([+-]?\d{1,3}\.\d+)\s*[, ]\s*([+-]?\d{1,3}\.\d+)"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let match = String(folded[range])
        let parts = match.split { $0 == "," || $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              validCoordinate(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return (latitude, longitude)
    }

    static func radius(in text: String) -> Double? {
        let folded = AskAppleCopy.folded(text)
        if let meters = measurement(in: folded, pattern: #"within\s+(\d+(?:\.\d+)?)\s*(m|meter|meters|metre|metres)\b"#) {
            return min(max(meters, 1), maximumRadiusMeters)
        }
        if let km = measurement(in: folded, pattern: #"within\s+(\d+(?:\.\d+)?)\s*(km|kilometer|kilometers|kilometre|kilometres)\b"#) {
            return min(max(km * 1_000, 1), maximumRadiusMeters)
        }
        if let miles = measurement(in: folded, pattern: #"within\s+(\d+(?:\.\d+)?)\s*(mi|mile|miles)\b"#) {
            return min(max(miles * 1_609.344, 1), maximumRadiusMeters)
        }
        return nil
    }

    private static func phrase(after markers: [String], in folded: String) -> String? {
        guard let marker = markers.compactMap({ folded.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }
        var words = String(folded[marker.upperBound...])
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        let trailing: Set<String> = [
            "please", "today", "yesterday", "tonight", "tomorrow", "now"
        ]
        while let last = words.last, trailing.contains(last) {
            words.removeLast()
        }
        let tail = words.joined(separator: " ")
        let blocked: Set<String> = ["", "me", "here", "us", "you", "home", "there", "my", "the"]
        if blocked.contains(tail) || tail.count < 2 { return nil }
        return String(tail.prefix(80))
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

    private static func applyLocation(
        latitude: Double?,
        longitude: Double?,
        radiusMeters: Double?,
        to request: inout PhotoQueryRequest
    ) {
        guard let latitude, let longitude, validCoordinate(latitude: latitude, longitude: longitude) else { return }
        request.locationLatitude = latitude
        request.locationLongitude = longitude
        let radius = radiusMeters ?? defaultRadiusMeters
        request.locationRadiusMeters = min(max(radius, 1), maximumRadiusMeters)
    }

    private static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    private static func labeledCoordinates(in folded: String) -> (latitude: Double, longitude: Double)? {
        let pattern = #"lat(?:itude)?\s*[:=]?\s*([+-]?\d{1,3}\.\d+).{0,24}lon(?:gitude)?\s*[:=]?\s*([+-]?\d{1,3}\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(folded.startIndex..<folded.endIndex, in: folded)
        guard let match = regex.firstMatch(in: folded, range: range),
              match.numberOfRanges == 3,
              let latRange = Range(match.range(at: 1), in: folded),
              let lonRange = Range(match.range(at: 2), in: folded),
              let latitude = Double(folded[latRange]),
              let longitude = Double(folded[lonRange]),
              validCoordinate(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return (latitude, longitude)
    }

    private static func measurement(in folded: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(folded.startIndex..<folded.endIndex, in: folded)
        guard let match = regex.firstMatch(in: folded, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: folded) else {
            return nil
        }
        return Double(folded[valueRange])
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
        // Every match stays on the stored line so the card can open it. forModel trims the model copy.
        for result in results {
            rows.append(row(result))
        }
        return rows.joined(separator: "\n")
    }

    /// What the model may say. Asset ids stay on the stored line for the card.
    static func forModel(_ output: String) -> String {
        var kept: [String] = []
        var listed = 0
        var hidden = 0
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if photo(from: text) != nil {
                if listed < maximumListed {
                    kept.append(withoutAsset(text))
                    listed += 1
                } else {
                    hidden += 1
                }
            } else if isMoreLine(text) {
                continue
            } else {
                kept.append(text)
            }
        }
        if hidden > 0 {
            kept.append("And \(hidden) more.")
        }
        return kept.joined(separator: "\n")
    }

    /// Photos the card can show. Lines without an asset id, including albums, stay out.
    static func grid(from lines: [String]) -> Grid? {
        var seen = Set<String>()
        var photos: [Photo] = []
        for line in lines {
            guard let photo = photo(from: line), seen.insert(photo.id).inserted else { continue }
            photos.append(photo)
        }
        guard !photos.isEmpty else { return nil }
        let title = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("Found ") } ?? "Photos"
        return Grid(title: title, photos: photos)
    }

    /// How many photos sit past the four shown on the card. Twelve photos leave eight.
    static func overflow(count: Int) -> Int {
        max(count - gridCount, 0)
    }

    /// Zoom source for a page. A photo with no cell returns to the bottom-trailing cell.
    static func zoomSource(prefix: String, photoID: String, ids: [String]) -> String {
        let visible = ids.prefix(gridCount)
        let target = visible.contains(photoID) ? photoID : (visible.last ?? photoID)
        guard !prefix.isEmpty else { return target }
        return "\(prefix)|\(target)"
    }

    /// Gallery page. A swipe counts only for the open that started it. A choice from an earlier open stays off this one.
    static func selectedID(
        startID: String,
        choiceStart: String?,
        choiceID: String?,
        ids: [String]
    ) -> String {
        if choiceStart == startID, let choiceID, ids.contains(choiceID) {
            return choiceID
        }
        if ids.contains(startID) { return startID }
        return ids.first ?? ""
    }

    static let gridCount = 4

    struct Photo: Identifiable, Equatable, Sendable {
        var id: String
        var caption: String
    }

    struct Grid: Equatable, Sendable {
        var title: String
        var photos: [Photo]

        var shareText: String {
            ([title] + photos.map(\.caption)).joined(separator: "\n")
        }

        /// File names the bubble should not repeat. Generic placeholders stay out.
        var coveredPhrases: [String] {
            let generic: Set<String> = ["photo", "video", "audio", "item"]
            return photos.map(\.caption).filter { caption in
                guard caption.count >= 3 else { return false }
                let folded = caption.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                return !generic.contains(folded)
            }
        }
    }

    static func photo(from line: String) -> Photo? {
        let parts = line.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard let last = parts.last, last.hasPrefix(assetPrefix) else { return nil }
        let stored = String(last.dropFirst(assetPrefix.count))
        let id = stored.replacingOccurrences(of: "%3D", with: "=")
        guard isAssetID(id) else { return nil }
        let caption = parts.count > 1 ? parts[0] : "Photo"
        return Photo(id: id, caption: caption)
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
        if result.aspectRatio > 0 {
            parts.append(String(format: "%.2f:1", result.aspectRatio))
        }
        if !result.mediaSubtypes.isEmpty {
            parts.append(result.mediaSubtypes.joined(separator: "+"))
        }
        if let seconds = result.durationSeconds, seconds > 0 {
            parts.append(durationLabel(seconds))
        }
        if let location = result.location {
            parts.append(
                String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
            )
        }
        if result.isFavorite { parts.append("favorite") }
        if result.isHidden { parts.append("hidden") }
        if result.representsBurst { parts.append("burst") }
        if let burst = result.burstIdentifier, !burst.isEmpty {
            parts.append("burstID " + AskAppleCopy.plain(burst, limit: 24))
        }
        if !result.sourceTypes.isEmpty {
            parts.append(result.sourceTypes.joined(separator: "+"))
        }
        if let distance = result.similarityDistance {
            parts.append(String(format: "similar %.3f", distance))
        }
        if result.hasFeaturePrint { parts.append("print") }
        if !result.visionLabels.isEmpty {
            let labels = result.visionLabels.prefix(3).joined(separator: ", ")
            parts.append(AskAppleCopy.plain(labels, limit: 40))
        }
        if let ocr = result.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
            parts.append("OCR " + AskAppleCopy.plain(ocr, limit: 48))
        }
        let asset = storedAsset(result.id)
        if !asset.isEmpty {
            parts.append(assetPrefix + asset)
        }
        return parts.joined(separator: " · ")
    }

    static func albums(_ titles: [String]) -> String {
        let kept = titles
            .map { AskAppleCopy.plain($0, limit: 60) }
            .filter { !$0.isEmpty }
        guard !kept.isEmpty else { return "No albums." }
        var rows = ["Found \(kept.count) albums."]
        rows.append(contentsOf: kept.prefix(40))
        if kept.count > 40 {
            rows.append("And \(kept.count - 40) more.")
        }
        return rows.joined(separator: "\n")
    }

    private static let assetPrefix = "asset:"

    /// `=` is stored as `%3D` so the reply check keeps the line. The card restores it.
    private static func storedAsset(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAssetID(trimmed.replacingOccurrences(of: "=", with: "")) else { return "" }
        return trimmed.replacingOccurrences(of: "=", with: "%3D")
    }

    private static func isAssetID(_ id: String) -> Bool {
        !id.isEmpty
            && id.count <= 180
            && !id.contains("·")
            && !id.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    private static func withoutAsset(_ line: String) -> String {
        let parts = line.split(separator: "·", omittingEmptySubsequences: false)
        guard parts.count > 1,
              parts.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(assetPrefix) == true else {
            return line
        }
        return parts.dropLast()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " · ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isMoreLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("And ") && trimmed.hasSuffix(" more.")
    }

    private static func label(for request: PhotoQueryRequest) -> String {
        if request.mediaSubtypes?.contains(where: { $0.lowercased() == "screenshot" }) == true {
            return request.limit == 1 ? "screenshot" : "screenshots"
        }
        if request.isFavorite == true {
            return "favorite photos"
        }
        if request.isHidden == true {
            return "hidden photos"
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

    private static func durationLabel(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        let minutes = whole / 60
        let remain = whole % 60
        if minutes > 0 {
            return "\(minutes)m \(remain)s"
        }
        return "\(remain)s"
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

    static func albums() async -> String {
        let allowed = await PhotoQuery.shared.ensureAuthorized()
        guard allowed else { return AskPhotosLine.denied }
        return AskPhotosLine.albums(await PhotoQuery.shared.albums())
    }
}

struct AskPhotosTool: Tool, AskToolReadingSource {
    var toolLedger: AskToolLedger
    /// The question for this turn. Empty until the session stamps it.
    var question = ""
    let name = AskPhotos.toolName

    static func stamped(_ tool: any Tool, question: String) -> any Tool {
        guard var photos = tool as? AskPhotosTool else { return tool }
        photos.question = question
        return photos
    }
    let description = """
    Search the photo library, or list albums. Pass action search or albums. \
    For search, pass mediaType image, video, livePhoto, or any. \
    Pass subtype screenshot, live, panorama, hdr, depth, timelapse, or slowmo when named. \
    Pass daysAgo for how far back to look, such as 7 or 30. \
    Pass isFavorite true for favorites. Pass isHidden true for hidden items. \
    Pass albumTitle for an album. Pass textSearch for a filename or content word such as dog. \
    Pass latitude and longitude when you know the coordinates of a place named in the question. \
    Leave radiusMeters empty unless the person named a distance. A place with no distance searches the surrounding area. \
    Pass burstIdentifier for photos in one burst. \
    Pass sourceType userLibrary, cloudShared, or iTunesSynced. \
    Pass similarTo with a photo local id to find visually similar photos. \
    Pass newestFirst false for oldest first. Pass minWidth for a pixel width floor. \
    Pass limit up to 25. Call once. Do not say a photo id or a file name.
    """

    @Generable
    struct Arguments {
        @Guide(description: "search or albums. Use albums to list album titles.", .anyOf(["search", "albums"]))
        var action: String?
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
        @Guide(description: "How many days back to start. 7 is last week. 30 is last month. Leave empty for any time. Yesterday, today, and tomorrow are filled from the question.", .range(0...3_650))
        var daysAgo: Int?
        @Guide(description: "How many days back the range ends. Leave empty for now.", .range(0...3_650))
        var throughDaysAgo: Int?
        @Guide(description: "True for favorites only. Leave empty otherwise.")
        var isFavorite: Bool?
        @Guide(description: "True for hidden items only. Leave empty otherwise.")
        var isHidden: Bool?
        @Guide(description: "screenshot, live, panorama, hdr, depth, timelapse, or slowmo when named. Leave empty otherwise.", .anyOf(["screenshot", "live", "panorama", "hdr", "depth", "timelapse", "slowmo"]))
        var subtype: String?
        @Guide(description: "Album title. Leave empty when unused.")
        var albumTitle: String?
        @Guide(description: "A filename or content word such as dog or receipt. Leave empty when unused.")
        var textSearch: String?
        @Guide(description: "Latitude from -90 to 90 for a nearby photo search. Leave empty when unused.", .range(-90...90))
        var latitude: Double?
        @Guide(description: "Longitude from -180 to 180 for a nearby photo search. Leave empty when unused.", .range(-180...180))
        var longitude: Double?
        @Guide(description: "Search radius in meters when the person named a distance. Leave empty otherwise. Max 50000.", .range(1...50_000))
        var radiusMeters: Double?
        @Guide(description: "True for newest first. False for oldest first. True when omitted.")
        var newestFirst: Bool?
        @Guide(description: "Burst group identifier. Leave empty when unused.")
        var burstIdentifier: String?
        @Guide(description: "userLibrary, cloudShared, or iTunesSynced. Leave empty when unused.", .anyOf(["userLibrary", "cloudShared", "iTunesSynced"]))
        var sourceType: String?
        @Guide(description: "Local identifier of a photo to find visually similar photos. Leave empty when unused.")
        var similarTo: String?
        @Guide(description: "How many results to return, from 1 to 25.", .range(1...AskPhotosQuery.maximumLimit))
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let action = AskAppleCopy.folded(arguments.action ?? "search")
        if action == "albums" {
            return try await boundedAppleCall(ledger: toolLedger, name: name, arguments: "albums") {
                await AskPhotosRead.albums()
            }
        }
        let built = AskPhotosQuery.request(
            mediaType: arguments.mediaType,
            minWidth: arguments.minWidth,
            maxWidth: arguments.maxWidth,
            minHeight: arguments.minHeight,
            maxHeight: arguments.maxHeight,
            daysAgo: arguments.daysAgo,
            throughDaysAgo: arguments.throughDaysAgo,
            isFavorite: arguments.isFavorite,
            isHidden: arguments.isHidden,
            subtype: arguments.subtype,
            albumTitle: arguments.albumTitle,
            textSearch: arguments.textSearch,
            latitude: arguments.latitude,
            longitude: arguments.longitude,
            radiusMeters: arguments.radiusMeters,
            newestFirst: arguments.newestFirst,
            burstIdentifier: arguments.burstIdentifier,
            sourceType: arguments.sourceType,
            similarTo: arguments.similarTo,
            limit: arguments.limit
        )
        let enriched = question.isEmpty ? built : AskPhotosQuery.enrich(built, question: question)
        let request = await AskPhotosQuery.resolvePlace(enriched, question: question)
        let label = summary(request)
        return try await boundedAppleCall(
            ledger: toolLedger,
            name: name,
            arguments: label,
            present: AskPhotosLine.forModel
        ) {
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
        if request.isHidden == true { parts.append("hidden") }
        if request.sortDescending == false { parts.append("oldest") }
        if let search = request.textSearch, !search.isEmpty { parts.append(search) }
        if let album = request.albumTitle, !album.isEmpty { parts.append(album) }
        if let burst = request.burstIdentifier, !burst.isEmpty { parts.append("burst") }
        if let source = request.sourceType, !source.isEmpty { parts.append(source) }
        if let similar = request.similarToLocalIdentifier, !similar.isEmpty { parts.append("similar") }
        if let latitude = request.locationLatitude, let longitude = request.locationLongitude {
            let radius = Int(request.locationRadiusMeters ?? AskPhotosQuery.defaultRadiusMeters)
            parts.append(String(format: "%.4f,%.4f,%dm", latitude, longitude, radius))
        }
        if let days = request.startDate {
            let delta = Calendar.current.dateComponents([.day], from: days, to: Date()).day ?? 0
            parts.append("\(max(delta, 0))d")
        }
        if parts.isEmpty { parts.append("search") }
        return parts.joined(separator: " ")
    }
}

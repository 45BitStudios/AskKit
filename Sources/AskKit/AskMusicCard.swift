import AppIntents
import Foundation
import MusicKit
import SwiftUI

/// What a music question is asking for. Tests use this so they do not open MusicKit.
enum AskMusicQuery {
    static let limit = 3

    enum Kind: Equatable, Sendable {
        case now
        case recent
        case song
        case album
        case playlist
        case play
        case pause
        case next
        case previous
    }

    struct Request: Equatable, Sendable {
        var kind: Kind
        var term: String
    }

    /// A title stays a search. "What is playing" stays on the current song. "Last played" is the recent song.
    static func request(in question: String) -> Request {
        let tokens = AskAppleCopy.foldedTokens(question)
        let folded = AskAppleCopy.folded(question)
        let album = tokens.contains("album") || tokens.contains("albums")
        let playlist = tokens.contains("playlist") || tokens.contains("playlists")
        if isRecent(folded), !album, !playlist {
            return Request(kind: .recent, term: "")
        }
        if isPause(folded, tokens: tokens) {
            return Request(kind: .pause, term: "")
        }
        if isNext(tokens) {
            return Request(kind: .next, term: "")
        }
        if isPrevious(tokens) {
            return Request(kind: .previous, term: "")
        }
        // A straight apostrophe splits "what's" into "what" and "s". A one-letter token is not a title.
        let term = tokens.filter { !skip.contains($0) && $0.count > 1 }.joined(separator: " ")
        let clipped = String(term.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        if clipped.isEmpty {
            return Request(kind: .now, term: "")
        }
        if isPlay(folded, tokens: tokens) {
            return Request(kind: .play, term: clipped)
        }
        if playlist {
            return Request(kind: .playlist, term: clipped)
        }
        if album {
            return Request(kind: .album, term: clipped)
        }
        return Request(kind: .song, term: clipped)
    }

    /// The tool arguments. An empty title falls back to what is playing.
    static func request(which: String, query: String?) -> Request {
        let kind = AskAppleCopy.folded(which)
        let term = String((query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if kind.contains("pause") || kind == "stop" {
            return Request(kind: .pause, term: "")
        }
        if kind.contains("next") || kind.contains("skip") {
            return Request(kind: .next, term: "")
        }
        if kind.contains("previous") || kind == "back" {
            return Request(kind: .previous, term: "")
        }
        if kind.contains("recent") || kind.contains("last") {
            return Request(kind: .recent, term: "")
        }
        if kind == "play" || kind.hasPrefix("play ") {
            return term.isEmpty ? Request(kind: .now, term: "") : Request(kind: .play, term: term)
        }
        if kind.contains("playlist") {
            return term.isEmpty ? Request(kind: .now, term: "") : Request(kind: .playlist, term: term)
        }
        if kind.contains("album") {
            return term.isEmpty ? Request(kind: .now, term: "") : Request(kind: .album, term: term)
        }
        if kind.contains("song") {
            return term.isEmpty ? Request(kind: .now, term: "") : Request(kind: .song, term: term)
        }
        if !term.isEmpty {
            return Request(kind: .song, term: term)
        }
        return Request(kind: .now, term: "")
    }

    /// Play a named song or album. Pause and stop stay transport commands.
    private static func isPlay(_ folded: String, tokens: [String]) -> Bool {
        if tokens.contains("pause") || tokens.contains("stop") { return false }
        if folded.localizedStandardContains("play the")
            || folded.localizedStandardContains("play a")
            || folded.localizedStandardContains("play some") {
            return true
        }
        return tokens.contains("play") && tokens.contains(where: { !skip.contains($0) && $0 != "play" })
    }

    /// "Last played" is play history. The song sitting in the queue is a different question.
    static func isRecent(_ folded: String) -> Bool {
        folded.localizedStandardContains("last played")
            || folded.localizedStandardContains("recently played")
            || folded.localizedStandardContains("recently listened")
            || folded.localizedStandardContains("play history")
    }

    /// Pause, or stop while music is playing. A bare stop stays a search.
    private static func isPause(_ folded: String, tokens: [String]) -> Bool {
        if tokens.contains("pause") { return true }
        return folded.localizedStandardContains("stop the music")
            || folded.localizedStandardContains("stop playing")
            || folded.localizedStandardContains("stop the song")
            || folded.localizedStandardContains("stop playback")
    }

    /// Skip, or next when a song is named. Next by itself is not a transport command.
    private static func isNext(_ tokens: [String]) -> Bool {
        if tokens.contains("skip") { return true }
        return tokens.contains("next") && hasTrack(tokens)
    }

    /// Previous or back when a song is named. Last played is handled before this.
    private static func isPrevious(_ tokens: [String]) -> Bool {
        let goingBack = tokens.contains("previous") || tokens.contains("back")
        return goingBack && hasTrack(tokens)
    }

    private static func hasTrack(_ tokens: [String]) -> Bool {
        tokens.contains("song") || tokens.contains("songs") || tokens.contains("track") || tokens.contains("music")
    }

    /// True when the lines are missing or are the wrong kind of result.
    static func needsReread(_ request: Request, lines: [String]) -> Bool {
        if lines.contains(where: { settled.contains(plain($0)) }) { return false }
        let items = lines.compactMap(AskMusicLine.item(from:))
        switch request.kind {
        case .now:
            if lines.isEmpty { return true }
            return items.isEmpty
        case .recent:
            return !lines.contains { plain($0).hasPrefix("Recent:") }
        case .song:
            return !items.contains { $0.kind == .song }
        case .album:
            return !items.contains { $0.kind == .album }
        case .playlist:
            return !items.contains { $0.kind == .playlist }
        case .play, .pause, .next, .previous:
            return false
        }
    }

    private static func plain(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let settled: Set<String> = [
        AskAppleCopy.denied,
        "Nothing is playing.",
        "Nothing was played recently.",
        "No matching songs.",
        "No matching albums.",
        "No matching playlists.",
        "Music isn't available."
    ]

    private static let skip: Set<String> = [
        "what", "whats", "is", "are", "the", "a", "an", "my", "me", "playing", "now", "song", "songs",
        "album", "albums", "playlist", "playlists", "music", "find", "search", "show", "play", "by",
        "called", "named", "for", "some", "please", "this", "that", "from", "on", "of", "about", "can",
        "you", "i", "want", "to", "listen", "hear", "look", "up", "lookup", "any", "there", "something",
        "current", "currently", "do", "last", "played", "recent", "recently", "listened", "history"
    ]
}

/// One song or album line. The card reads it back. Nothing in the line uses `=`.
enum AskMusicLine {
    struct Item: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case song
            case album
            case playlist
        }

        var kind: Kind
        var title: String
        var artist: String
        var detail: String
        var extra: String

        /// Words for Copy, Share, and the trace picture. The spoken rewrite stays off this text.
        var shareText: String {
            [title, artist, detail, extra].filter { !$0.isEmpty }.joined(separator: "\n")
        }

        var subtitle: String {
            [detail, extra].filter { !$0.isEmpty }.joined(separator: " · ")
        }

        var musicKind: AskMusicKind {
            switch kind {
            case .song: .song
            case .album: .album
            case .playlist: .playlist
            }
        }
    }

    static func songLine(title: String, artist: String, album: String?, duration: TimeInterval?) -> String {
        let name = clean(title)
        guard !name.isEmpty else { return "Nothing is playing." }
        var parts = [name]
        let who = clean(artist)
        let record = clean(album ?? "")
        let length = duration.flatMap(clock) ?? ""
        if !who.isEmpty || !record.isEmpty || !length.isEmpty {
            parts.append(who.isEmpty ? "Unknown artist" : who)
        }
        if !record.isEmpty || !length.isEmpty {
            parts.append(record.isEmpty ? "Single" : record)
        }
        if !length.isEmpty {
            parts.append(length)
        }
        return "Song: " + parts.joined(separator: " · ")
    }

    /// The last song that played. The prefix keeps it distinct from the song in the queue.
    static func recentLine(title: String, artist: String, album: String?, duration: TimeInterval?) -> String {
        let song = songLine(title: title, artist: artist, album: album, duration: duration)
        guard let rest = song.dropPrefix("Song:") else { return "Nothing was played recently." }
        return "Recent: " + rest
    }

    static func albumLine(title: String, artist: String, songs: Int, year: String) -> String {
        let name = clean(title)
        guard !name.isEmpty else { return "No matching albums." }
        var parts = [name]
        let who = clean(artist)
        let count = songs == 1 ? "1 song" : "\(max(songs, 0)) songs"
        let released = clean(year)
        if !who.isEmpty || songs > 0 || !released.isEmpty {
            parts.append(who.isEmpty ? "Unknown artist" : who)
        }
        if songs > 0 || !released.isEmpty {
            parts.append(count)
        }
        if !released.isEmpty {
            parts.append(released)
        }
        return "Album: " + parts.joined(separator: " · ")
    }

    static func playlistLine(title: String, curator: String, songs: Int) -> String {
        let name = clean(title)
        guard !name.isEmpty else { return "No matching playlists." }
        var parts = [name]
        let who = clean(curator)
        let count = songs == 1 ? "1 song" : "\(max(songs, 0)) songs"
        if !who.isEmpty || songs > 0 {
            parts.append(who.isEmpty ? "Playlist" : who)
        }
        if songs > 0 {
            parts.append(count)
        }
        return "Playlist: " + parts.joined(separator: " · ")
    }

    static func item(from line: String) -> Item? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: Item.Kind
        let rest: String
        if let suffix = trimmed.dropPrefix("Song:") ?? trimmed.dropPrefix("Recent:") {
            kind = .song
            rest = suffix
        } else if let suffix = trimmed.dropPrefix("Album:") {
            kind = .album
            rest = suffix
        } else if let suffix = trimmed.dropPrefix("Playlist:") {
            kind = .playlist
            rest = suffix
        } else {
            return nil
        }
        let parts = rest.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard let title = parts.first, !title.isEmpty else { return nil }
        return Item(
            kind: kind,
            title: title,
            artist: parts.count > 1 ? parts[1] : "",
            detail: parts.count > 2 ? parts[2] : "",
            extra: parts.count > 3 ? parts[3] : ""
        )
    }

    /// A short bubble when the model wrote nothing. The card keeps every field.
    static func spoken(_ lines: [String]) -> String? {
        let items = lines.compactMap(item(from:))
        guard let first = items.first else { return nil }
        let who = first.artist.isEmpty ? first.title : "\(first.title) by \(first.artist)"
        let recent = lines.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Recent:") }
        if items.count == 1 {
            if recent { return "Last played was \(who)." }
            return who.hasSuffix(".") ? who : who + "."
        }
        let noun = switch first.kind {
        case .album: "albums"
        case .playlist: "playlists"
        case .song: "songs"
        }
        return "\(items.count) \(noun). \(who)."
    }

    static func clock(_ interval: TimeInterval) -> String? {
        guard interval.isFinite, interval > 0 else { return nil }
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }

    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "=", with: " ")
            .replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Song and album search, plus the song that is playing. A denial stays "Not allowed."
enum AskMusicRead {
    static func lines(_ request: AskMusicQuery.Request) async -> String {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { return AskAppleCopy.denied }
        switch request.kind {
        case .now:
            return await MainActor.run { nowPlaying() }
        case .recent:
            return await recentlyPlayed()
        case .song:
            return await catalog(term: request.term, album: false)
        case .album:
            return await catalog(term: request.term, album: true)
        case .playlist:
            return await playlists(term: request.term)
        case .play:
            do {
                let played = try await play(kind: .song, title: request.term, artist: "")
                return "Playing \(played)."
            } catch {
                return "Music isn't available."
            }
        case .pause:
            await MainActor.run { SystemMusicPlayer.shared.pause() }
            return "Paused."
        case .next:
            return await skip(forward: true)
        case .previous:
            return await skip(forward: false)
        }
    }

    private static func skip(forward: Bool) async -> String {
        do {
            if forward {
                try await SystemMusicPlayer.shared.skipToNextEntry()
                return "Skipped to the next song."
            }
            try await SystemMusicPlayer.shared.skipToPreviousEntry()
            return "Went back to the previous song."
        } catch {
            return "Music isn't available."
        }
    }

    private static func nowPlaying() -> String {
        guard let entry = SystemMusicPlayer.shared.queue.currentEntry else {
            return "Nothing is playing."
        }
        if let item = entry.item {
            switch item {
            case .song(let song):
                return AskMusicLine.songLine(
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle,
                    duration: song.duration
                )
            case .musicVideo(let video):
                return AskMusicLine.songLine(
                    title: video.title,
                    artist: video.artistName,
                    album: nil,
                    duration: video.duration
                )
            @unknown default:
                break
            }
        }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "Nothing is playing." }
        return AskMusicLine.songLine(title: title, artist: entry.subtitle ?? "", album: nil, duration: nil)
    }

    /// The most recent song in the person's play history. The queue's current entry is not a substitute.
    private static func recentlyPlayed() async -> String {
        do {
            var request = MusicRecentlyPlayedRequest<Song>()
            request.limit = 1
            let response = try await request.response()
            guard let song = response.items.first else { return "Nothing was played recently." }
            return AskMusicLine.recentLine(
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle,
                duration: song.duration
            )
        } catch {
            return "Music isn't available."
        }
    }

    private static func catalog(term: String, album: Bool) async -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return album ? "No matching albums." : "No matching songs." }
        do {
            let types: [any MusicCatalogSearchable.Type] = album ? [Album.self] : [Song.self]
            var request = MusicCatalogSearchRequest(term: trimmed, types: types)
            request.limit = AskMusicQuery.limit
            let response = try await request.response()
            if album {
                var lines: [String] = []
                for item in response.albums {
                    if lines.count == AskMusicQuery.limit { break }
                    lines.append(AskMusicLine.albumLine(
                        title: item.title,
                        artist: item.artistName,
                        songs: item.trackCount,
                        year: year(item.releaseDate)
                    ))
                }
                return lines.isEmpty ? "No matching albums." : lines.joined(separator: "\n")
            }
            var lines: [String] = []
            for item in response.songs {
                if lines.count == AskMusicQuery.limit { break }
                lines.append(AskMusicLine.songLine(
                    title: item.title,
                    artist: item.artistName,
                    album: item.albumTitle,
                    duration: item.duration
                ))
            }
            return lines.isEmpty ? "No matching songs." : lines.joined(separator: "\n")
        } catch {
            return "Music isn't available."
        }
    }

    private static func playlists(term: String) async -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No matching playlists." }
        do {
            var request = MusicCatalogSearchRequest(term: trimmed, types: [Playlist.self])
            request.limit = AskMusicQuery.limit
            let response = try await request.response()
            var lines: [String] = []
            for item in response.playlists {
                if lines.count == AskMusicQuery.limit { break }
                lines.append(AskMusicLine.playlistLine(
                    title: item.name,
                    curator: item.curatorName ?? "",
                    songs: 0
                ))
            }
            return lines.isEmpty ? "No matching playlists." : lines.joined(separator: "\n")
        } catch {
            return "Music isn't available."
        }
    }

    private static func year(_ date: Date?) -> String {
        guard let date else { return "" }
        return String(Calendar.current.component(.year, from: date))
    }

    /// Plays one catalog song, album, or playlist. The card calls this. Tests do not.
    static func play(kind: AskMusicKind, title: String, artist: String) async throws -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AskMusicIntentError.missing }
        let who = cleanedArtist(artist)
        let status = await MusicAuthorization.request()
        guard status == .authorized else { throw AskMusicIntentError.denied }
        if kind != .playlist, let current = try await resumeQueued(title: name, artist: who) {
            return current
        }
        let term = String([name, who].filter { !$0.isEmpty }.joined(separator: " ").prefix(200))
        do {
            switch kind {
            case .song:
                var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
                request.limit = 5
                let response = try await request.response()
                guard let song = choose(response.songs, title: name, artist: who, titleOf: \.title, artistOf: \.artistName) else {
                    throw AskMusicIntentError.missing
                }
                let played = song.title
                await MainActor.run {
                    SystemMusicPlayer.shared.queue = MusicPlayer.Queue(for: [song])
                }
                try await SystemMusicPlayer.shared.play()
                return played
            case .album:
                var request = MusicCatalogSearchRequest(term: term, types: [Album.self])
                request.limit = 5
                let response = try await request.response()
                guard let album = choose(response.albums, title: name, artist: who, titleOf: \.title, artistOf: \.artistName) else {
                    throw AskMusicIntentError.missing
                }
                let played = album.title
                await MainActor.run {
                    SystemMusicPlayer.shared.queue = MusicPlayer.Queue(for: [album])
                }
                try await SystemMusicPlayer.shared.play()
                return played
            case .playlist:
                var request = MusicCatalogSearchRequest(term: term, types: [Playlist.self])
                request.limit = 5
                let response = try await request.response()
                guard let playlist = choose(
                    response.playlists,
                    title: name,
                    artist: who,
                    titleOf: \.name,
                    artistOf: { $0.curatorName ?? "" }
                ) else {
                    throw AskMusicIntentError.missing
                }
                let played = playlist.name
                await MainActor.run {
                    SystemMusicPlayer.shared.queue = MusicPlayer.Queue(for: [playlist])
                }
                try await SystemMusicPlayer.shared.play()
                return played
            }
        } catch let error as AskMusicIntentError {
            throw error
        } catch {
            throw AskMusicIntentError.unavailable
        }
    }

    /// Starts the song already in the system queue. Nil when that song is a different one.
    @MainActor
    private static func resumeQueued(title: String, artist: String) async throws -> String? {
        guard let current = queuedTitle(matching: title, artist: artist) else { return nil }
        do {
            try await SystemMusicPlayer.shared.play()
            return current
        } catch {
            throw AskMusicIntentError.unavailable
        }
    }

    /// The song already in the system queue. Playing it does not search the catalog.
    @MainActor
    private static func queuedTitle(matching title: String, artist: String) -> String? {
        guard let entry = SystemMusicPlayer.shared.queue.currentEntry else { return nil }
        let currentTitle: String
        let currentArtist: String
        if let item = entry.item {
            switch item {
            case .song(let song):
                currentTitle = song.title
                currentArtist = song.artistName
            case .musicVideo(let video):
                currentTitle = video.title
                currentArtist = video.artistName
            @unknown default:
                currentTitle = entry.title
                currentArtist = entry.subtitle ?? ""
            }
        } else {
            currentTitle = entry.title
            currentArtist = entry.subtitle ?? ""
        }
        let wantTitle = AskAppleCopy.folded(title)
        let haveTitle = AskAppleCopy.folded(currentTitle)
        guard !haveTitle.isEmpty else { return nil }
        let titleMatches = haveTitle == wantTitle || haveTitle.contains(wantTitle) || wantTitle.contains(haveTitle)
        guard titleMatches else { return nil }
        if !artist.isEmpty {
            let wantArtist = AskAppleCopy.folded(artist)
            let haveArtist = AskAppleCopy.folded(currentArtist)
            let artistMatches = haveArtist.isEmpty
                || haveArtist == wantArtist
                || haveArtist.contains(wantArtist)
                || wantArtist.contains(haveArtist)
            guard artistMatches else { return nil }
        }
        let trimmed = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? title : trimmed
    }

    private static func cleanedArtist(_ artist: String) -> String {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if AskAppleCopy.folded(trimmed) == "unknown artist" { return "" }
        return trimmed
    }

    private static func choose<Item>(
        _ items: some Sequence<Item>,
        title: String,
        artist: String,
        titleOf: (Item) -> String,
        artistOf: (Item) -> String
    ) -> Item? {
        let list = Array(items)
        let wantTitle = AskAppleCopy.folded(title)
        let wantArtist = AskAppleCopy.folded(artist)
        var titleHit: Item?
        for item in list {
            let haveTitle = AskAppleCopy.folded(titleOf(item))
            let titleMatches = haveTitle == wantTitle || haveTitle.contains(wantTitle) || wantTitle.contains(haveTitle)
            guard titleMatches else { continue }
            if wantArtist.isEmpty { return item }
            let haveArtist = AskAppleCopy.folded(artistOf(item))
            if haveArtist == wantArtist || haveArtist.contains(wantArtist) || wantArtist.contains(haveArtist) {
                return item
            }
            if titleHit == nil { titleHit = item }
        }
        return titleHit ?? list.first
    }
}

/// Song or album. Raw values stay stable for a saved shortcut.
public enum AskMusicKind: String, AppEnum, Sendable {
    case song = "song"
    case album = "album"
    case playlist = "playlist"

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Music")

    public static let caseDisplayRepresentations: [AskMusicKind: DisplayRepresentation] = [
        .song: "Song",
        .album: "Album",
        .playlist: "Playlist"
    ]
}

public enum AskMusicIntentError: Error, CustomLocalizedStringResourceConvertible {
    case denied
    case missing
    case unavailable

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .denied:
            "AskKit doesn't have permission to play music."
        case .missing:
            "That song or album isn't available."
        case .unavailable:
            "Music isn't available."
        }
    }
}

/// Plays the song, album, or playlist named on a music card. Shortcuts can pass an ``AskMusicItemEntity`` from Ask.
public struct PlayAskMusicIntent: AppIntent {
    public static let title: LocalizedStringResource = "Play Music"
    public static let description = IntentDescription("Plays a song, album, or playlist.")

    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Music")
    public var item: AskMusicItemEntity?

    @Parameter(title: "Kind")
    public var kind: AskMusicKind

    @Parameter(title: "Title")
    public var itemTitle: String

    @Parameter(title: "Artist")
    public var artist: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$item)") {
            \.$kind
            \.$itemTitle
            \.$artist
        }
    }

    public init() {
        self.item = nil
        self.kind = .song
        self.itemTitle = ""
        self.artist = ""
    }

    public init(item: AskMusicItemEntity) {
        self.item = item
        self.kind = item.kind
        self.itemTitle = item.itemTitle
        self.artist = item.artist
    }

    public init(kind: AskMusicKind, title: String, artist: String) {
        self.item = AskMusicItemEntity(kind: kind, title: title, artist: artist)
        self.kind = kind
        self.itemTitle = title
        self.artist = artist
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let playKind = item?.kind ?? kind
        let title = item?.itemTitle.isEmpty == false ? item!.itemTitle : itemTitle
        let who = item?.artist.isEmpty == false ? item!.artist : artist
        let played = try await AskMusicRead.play(kind: playKind, title: title, artist: who)
        return .result(dialog: "Playing \(played).")
    }
}

/// The play button on a song or album card. A result dialog would open a second shortcut window on top of the snippet.
struct AskMusicPlayTap: AppIntent {
    static let title: LocalizedStringResource = "Play Music"
    static let isDiscoverable = false

    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Kind")
    var kind: AskMusicKind

    @Parameter(title: "Title")
    var itemTitle: String

    @Parameter(title: "Artist")
    var artist: String

    init() {}

    init(kind: AskMusicKind, title: String, artist: String) {
        self.kind = kind
        self.itemTitle = title
        self.artist = artist
    }

    func perform() async throws -> some IntentResult {
        _ = try await AskMusicRead.play(kind: kind, title: itemTitle, artist: artist)
        return .result()
    }
}

/// One song or one album. Several results page, the same way contacts do.
struct AskMusicCard: View {
    var item: AskMusicLine.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(plate)
                        .frame(width: 76, height: 76)
                    Image(systemName: badgeSymbol)
                        .font(.title)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                    if !item.artist.isEmpty {
                        Text(item.artist)
                            .font(.subheadline)
                    }
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AskCardBadge(
                    title: badgeTitle,
                    symbol: badgeSymbol,
                    tint: accent
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(badgeTitle)
            .accessibilityValue(spokenValue)
            AskCardCTA(
                title: playTitle,
                symbol: "play.fill",
                tint: accent,
                intent: AskMusicPlayTap(
                    kind: item.musicKind,
                    title: item.title,
                    artist: item.artist
                ),
                accessibilityLabel: Text("Play \(badgeTitle.lowercased()) \(item.title)")
            )
        }
        .askCardSurface(tint: accent)
        .accessibilityElement(children: .contain)
    }

    private var badgeTitle: String {
        switch item.kind {
        case .album: "Album"
        case .playlist: "Playlist"
        case .song: "Song"
        }
    }

    private var badgeSymbol: String {
        switch item.kind {
        case .album: "square.stack.fill"
        case .playlist: "music.note.list"
        case .song: "music.note"
        }
    }

    private var playTitle: LocalizedStringKey {
        switch item.kind {
        case .album: "Play Album"
        case .playlist: "Play Playlist"
        case .song: "Play Song"
        }
    }

    private var accent: Color {
        switch item.kind {
        case .album: .indigo
        case .playlist: .teal
        case .song: .pink
        }
    }

    private var plate: LinearGradient {
        switch item.kind {
        case .album:
            return LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .playlist:
            return LinearGradient(colors: [.teal, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .song:
            return LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var spokenValue: String {
        [item.title, item.artist, item.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

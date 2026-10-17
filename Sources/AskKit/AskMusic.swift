import AppIntents
import Foundation
import MusicKit
import SwiftUI

// Apple Watch can search the catalog but has no player, so playback there says Music isn't available.
#if os(macOS)
/// The Mac has no system Music player to drive. Songs play inside the app.
package typealias AskMusicPlayer = ApplicationMusicPlayer
#elseif !os(watchOS)
/// Plays in the Music app, so the song keeps going after Ask closes.
package typealias AskMusicPlayer = SystemMusicPlayer
#endif

/// What a music question is asking for. Tests use this so they do not open MusicKit.
enum AskMusicQuery {
    static let limit = 3

    package enum Kind: Equatable, Sendable {
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
        /// How many recently played songs to show. The last song stays 1. A listening list uses ``limit``.
        var historyLimit: Int = 1
        /// Days back for a listening list. Nil keeps the most recent songs and does not claim a week.
        var historyDays: Int? = nil
    }

    /// A title stays a search. "What is playing" stays on the current song. "Last played" is the recent song.
    /// Songs the person listened to, including top songs and the past week, stay on play history.
    static func request(in question: String) -> Request {
        let tokens = AskAppleCopy.foldedTokens(question)
        let folded = AskAppleCopy.folded(question)
        let album = tokens.contains("album") || tokens.contains("albums")
        let playlist = tokens.contains("playlist") || tokens.contains("playlists")
        if !album, !playlist, let history = listeningRequest(in: folded) {
            return history
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

    /// Play history for songs the person listened to. A named title stays a catalog search.
    private static func listeningRequest(in folded: String) -> Request? {
        let recent = isRecent(folded)
        guard recent || isOwnListening(folded) else { return nil }
        if !recent, namesACatalogTitle(folded) { return nil }
        let tokens = AskAppleCopy.foldedTokens(folded)
        let plural = tokens.contains("songs") || tokens.contains("tracks")
        let days = historyDays(in: folded)
        let list = plural || (!recent && (days != nil || folded.localizedStandardContains("most played") || folded.localizedStandardContains("top song")))
        return Request(
            kind: .recent,
            term: "",
            historyLimit: list ? limit : 1,
            historyDays: list ? days : nil
        )
    }

    /// The person is asking about their own listening, not a catalog title.
    private static func isOwnListening(_ folded: String) -> Bool {
        if isRecent(folded) { return true }
        if namesACatalogTitle(folded) { return false }
        if personalListening(folded) { return true }
        return historyDays(in: folded) != nil && mentionsMusic(folded)
    }

    private static func personalListening(_ folded: String) -> Bool {
        let phrases = [
            "listened to", "i listened", "i've listened", "i’ve listened", "ive listened",
            "been listening", "was listening", "listening history", "most played",
            "my top song", "my top songs", "top songs i", "top song i",
            "what i played", "what i play"
        ]
        return phrases.contains { folded.localizedStandardContains($0) }
    }

    private static func mentionsMusic(_ folded: String) -> Bool {
        let tokens = AskAppleCopy.foldedTokens(folded)
        return tokens.contains("song") || tokens.contains("songs")
            || tokens.contains("music") || tokens.contains("track") || tokens.contains("tracks")
    }

    /// A week, month, today, or yesterday named in the question. "Last played" has no window.
    static func historyDays(in folded: String) -> Int? {
        if folded.localizedStandardContains("past week")
            || folded.localizedStandardContains("last week")
            || folded.localizedStandardContains("this week") {
            return 7
        }
        if folded.localizedStandardContains("past month")
            || folded.localizedStandardContains("last month")
            || folded.localizedStandardContains("this month") {
            return 30
        }
        if folded.localizedStandardContains("yesterday") { return 2 }
        if folded.localizedStandardContains("today") { return 1 }
        return nil
    }

    /// Indexes inside the window. Nil when every date is missing, so the caller keeps recency and does not claim the window.
    static func recentIndexes(dates: [Date?], days: Int, now: Date) -> [Int]? {
        guard dates.contains(where: { $0 != nil }) else { return nil }
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        return dates.indices.filter { index in
            guard let played = dates[index] else { return false }
            return played >= cutoff
        }
    }

    /// True when a catalog title remains after the listening words are removed.
    private static func namesACatalogTitle(_ folded: String) -> Bool {
        let title = AskAppleCopy.foldedTokens(folded).filter { token in
            token.count > 1 && !skip.contains(token) && !historyWords.contains(token)
        }
        return !title.isEmpty
    }

    private static let historyWords: Set<String> = [
        "top", "tops", "past", "week", "weeks", "month", "months", "today", "yesterday",
        "most", "listen", "listening", "during", "over", "these", "those", "ve", "ive",
        "im", "been", "time", "times", "channel", "channels", "heavy", "rotation", "in"
    ]

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
            return !lines.contains { plain($0).hasPrefix("Now:") }
        case .recent:
            if request.historyDays != nil {
                return !lines.contains { plain($0).hasPrefix("History:") }
            }
            let recentCount = lines.filter { plain($0).hasPrefix("Recent:") }.count
            if request.historyLimit > 1 { return recentCount < request.historyLimit }
            return recentCount == 0
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
        "Nothing was played in the past week.",
        "Nothing was played in the past month.",
        "Nothing was played today.",
        "Nothing was played yesterday.",
        "Nothing was played in that time.",
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
package enum AskMusicLine {
    package struct Item: Equatable, Sendable {
        package enum Kind: Equatable, Sendable {
            case song
            case album
            case playlist
        }

        package var kind: Kind
        package var title: String
        package var artist: String
        var detail: String
        var extra: String
        /// Cover address. Share text, the poster, and speech leave it off.
        package var artwork: String = ""
        /// True when the line is what is playing now. The player card uses this.
        var nowPlaying: Bool = false

        /// Words for Copy, Share, and the trace picture. The spoken rewrite stays off this text.
        var shareText: String {
            [title, artist, detail, extra].filter { !$0.isEmpty }.joined(separator: "\n")
        }

        package var subtitle: String {
            [detail, extra].filter { !$0.isEmpty }.joined(separator: " · ")
        }

        package var musicKind: AskMusicKind {
            switch kind {
            case .song: .song
            case .album: .album
            case .playlist: .playlist
            }
        }

        /// Song length from the clock field on a song line.
        package var duration: TimeInterval? {
            guard kind == .song else { return nil }
            return seconds(from: extra)
        }
    }

    package static func songLine(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval?,
        artwork: String = ""
    ) -> String {
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
        return finished("Song:", parts, artwork: artwork)
    }

    /// The song in the queue right now. The prefix keeps the player card distinct from a search hit.
    package static func nowLine(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval?,
        artwork: String = ""
    ) -> String {
        let song = songLine(title: title, artist: artist, album: album, duration: duration, artwork: artwork)
        guard let rest = song.dropPrefix("Song:") else { return "Nothing is playing." }
        return "Now: " + rest
    }

    /// The last song that played. The prefix keeps it distinct from the song in the queue.
    static func recentLine(
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval?,
        artwork: String = ""
    ) -> String {
        let song = songLine(title: title, artist: artist, album: album, duration: duration, artwork: artwork)
        guard let rest = song.dropPrefix("Song:") else { return "Nothing was played recently." }
        return "Recent: " + rest
    }

    package static func albumLine(title: String, artist: String, songs: Int, year: String, artwork: String = "") -> String {
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
        return finished("Album:", parts, artwork: artwork)
    }

    static func playlistLine(title: String, curator: String, songs: Int, artwork: String = "") -> String {
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
        return finished("Playlist:", parts, artwork: artwork)
    }

    /// What the model may say. The cover address stays on the stored line for the card.
    static func forModel(_ output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .map { withoutArtwork(String($0)) }
            .joined(separator: "\n")
    }

    package static func item(from line: String) -> Item? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: Item.Kind
        let rest: String
        let nowPlaying: Bool
        if let suffix = trimmed.dropPrefix("Now:") {
            kind = .song
            rest = suffix
            nowPlaying = true
        } else if let suffix = trimmed.dropPrefix("Song:") ?? trimmed.dropPrefix("Recent:") {
            kind = .song
            rest = suffix
            nowPlaying = false
        } else if let suffix = trimmed.dropPrefix("Album:") {
            kind = .album
            rest = suffix
            nowPlaying = false
        } else if let suffix = trimmed.dropPrefix("Playlist:") {
            kind = .playlist
            rest = suffix
            nowPlaying = false
        } else {
            return nil
        }
        var parts = rest.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard let title = parts.first, !title.isEmpty else { return nil }
        var artwork = ""
        if parts.count > 1, let last = parts.last, isCoverAddress(last) {
            artwork = last.replacingOccurrences(of: "%3D", with: "=")
            parts.removeLast()
        }
        return Item(
            kind: kind,
            title: title,
            artist: parts.count > 1 ? parts[1] : "",
            detail: parts.count > 2 ? parts[2] : "",
            extra: parts.count > 3 ? parts[3] : "",
            artwork: artwork,
            nowPlaying: nowPlaying
        )
    }

    /// A short bubble when the model wrote nothing. The card keeps every field.
    static func spoken(_ lines: [String]) -> String? {
        let items = lines.compactMap(item(from:))
        guard let first = items.first else { return nil }
        let who = first.artist.isEmpty ? first.title : "\(first.title) by \(first.artist)"
        let recent = lines.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Recent:") }
        let playing = lines.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Now:") }
        let window = historyWindow(in: lines)
        if items.count == 1 {
            if let window { return "Played \(window): \(who)." }
            if recent { return "Last played was \(who)." }
            if playing { return "Playing \(who)." }
            return who.hasSuffix(".") ? who : who + "."
        }
        let noun = switch first.kind {
        case .album: "albums"
        case .playlist: "playlists"
        case .song: "songs"
        }
        if recent {
            return "\(items.count) \(noun) played \(window ?? "recently"). \(who)."
        }
        return "\(items.count) \(noun). \(who)."
    }

    /// The window marker written beside recent lines. Cards ignore it.
    private static func historyWindow(in lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let suffix = trimmed.dropPrefix("History:") else { continue }
            switch suffix.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "7": return "in the past week"
            case "30": return "in the past month"
            case "1": return "today"
            case "2": return "yesterday"
            default: return "recently"
            }
        }
        return nil
    }

    static func clock(_ interval: TimeInterval) -> String? {
        guard interval.isFinite, interval > 0 else { return nil }
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }

    /// Elapsed or remaining stamp for the scrubber. Zero stays `0:00`.
    package static func playhead(_ interval: TimeInterval, remaining: Bool = false) -> String {
        guard interval.isFinite else { return remaining ? "0:00" : "0:00" }
        let total = Int(max(0, interval).rounded())
        let stamped = "\(total / 60):" + String(format: "%02d", total % 60)
        if remaining {
            return total == 0 ? "0:00" : "-\(stamped)"
        }
        return stamped
    }

    static func seconds(from clock: String) -> TimeInterval? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              minutes >= 0,
              seconds >= 0,
              seconds < 60 else { return nil }
        return TimeInterval(minutes * 60 + seconds)
    }

    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "=", with: " ")
            .replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `=` is stored as `%3D`. The reply check rejects a raw equals sign, and clean() would turn it into a space.
    static func storedArtwork(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://"),
              trimmed.count <= 800,
              !trimmed.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "·" }) else { return "" }
        return trimmed.replacingOccurrences(of: "=", with: "%3D")
    }

    /// An Apple cover address. Other hosts stay off the card.
    static func coverURL(_ stored: String) -> URL? {
        let restored = stored.replacingOccurrences(of: "%3D", with: "=")
        guard !restored.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: restored),
              url.scheme?.lowercased() == "https",
              url.user == nil,
              let host = url.host?.lowercased(),
              isArtworkHost(host) else { return nil }
        return url
    }

    /// Image bytes for a cover address. Nil when the response is not a small https image.
    package static func imageData(_ stored: String) async -> Data? {
        guard let url = coverURL(stored) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("AskKit", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let final = response.url, coverURL(final.absoluteString) != nil else { return nil }
            guard data.count > 32, data.count <= 3_000_000 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func finished(_ label: String, _ parts: [String], artwork: String) -> String {
        var parts = parts
        let address = storedArtwork(artwork)
        if !address.isEmpty {
            parts.append(address)
        }
        return label + " " + parts.joined(separator: " · ")
    }

    private static func withoutArtwork(_ line: String) -> String {
        let parts = line.split(separator: "·", omittingEmptySubsequences: false)
        guard parts.count > 1,
              let last = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              isCoverAddress(last) else { return line }
        return parts.dropLast().map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " · ")
    }

    private static func isCoverAddress(_ text: some StringProtocol) -> Bool {
        text.hasPrefix("https://") || text.hasPrefix("http://")
    }

    private static func isArtworkHost(_ host: String) -> Bool {
        host == "mzstatic.com" || host.hasSuffix(".mzstatic.com")
            || host == "apple.com" || host.hasSuffix(".apple.com")
    }
}

/// Song and album search, plus the song that is playing. A denial stays "Not allowed."
package enum AskMusicRead {
    static func lines(_ request: AskMusicQuery.Request) async -> String {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { return AskAppleCopy.denied }
        switch request.kind {
        case .now:
            return await MainActor.run { nowPlaying() }
        case .recent:
            return await recentlyPlayed(limit: request.historyLimit, days: request.historyDays)
        case .song:
            return await catalog(term: request.term, album: false)
        case .album:
            return await catalog(term: request.term, album: true)
        case .playlist:
            return await playlists(term: request.term)
        case .play:
            do {
                _ = try await play(kind: .song, title: request.term, artist: "")
                let playing = await MainActor.run { nowPlaying() }
                if AskMusicLine.item(from: playing)?.nowPlaying == true {
                    return playing
                }
                return "Playing \(request.term)."
            } catch {
                return "Music isn't available."
            }
        case .pause:
#if os(watchOS)
            return "Music isn't available."
#else
            await MainActor.run { AskMusicPlayer.shared.pause() }
            return "Paused."
#endif
        case .next:
            return await skip(forward: true)
        case .previous:
            return await skip(forward: false)
        }
    }

    private static func skip(forward: Bool) async -> String {
#if os(watchOS)
        // Apple Watch has no music player to drive.
        return "Music isn't available."
#else
        do {
            if forward {
                try await AskMusicPlayer.shared.skipToNextEntry()
                return "Skipped to the next song."
            }
            try await AskMusicPlayer.shared.skipToPreviousEntry()
            return "Went back to the previous song."
        } catch {
            return "Music isn't available."
        }
#endif
    }

    private static func nowPlaying() -> String {
#if os(watchOS)
        // Apple Watch has no music player to drive.
        return "Nothing is playing."
#else
        guard let entry = AskMusicPlayer.shared.queue.currentEntry else {
            return "Nothing is playing."
        }
        if let item = entry.item {
            switch item {
            case .song(let song):
                return AskMusicLine.nowLine(
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle,
                    duration: song.duration,
                    artwork: cover(song.artwork)
                )
            case .musicVideo(let video):
                return AskMusicLine.nowLine(
                    title: video.title,
                    artist: video.artistName,
                    album: nil,
                    duration: video.duration,
                    artwork: cover(video.artwork)
                )
            @unknown default:
                break
            }
        }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "Nothing is playing." }
        return AskMusicLine.nowLine(title: title, artist: entry.subtitle ?? "", album: nil, duration: nil)
#endif
    }

    /// Play history. One song for the last track. A list keeps songs inside the asked window when the dates are present.
    private static func recentlyPlayed(limit: Int, days: Int?) async -> String {
        do {
            var request = MusicRecentlyPlayedRequest<Song>()
            let capped = min(max(limit, 1), AskMusicQuery.limit)
            request.limit = days == nil ? capped : historyFetchLimit
            let response = try await request.response()
            var songs = Array(response.items.prefix(request.limit ?? historyFetchLimit))
            if songs.isEmpty { return "Nothing was played recently." }
            var window: Int?
            if let days, let indexes = AskMusicQuery.recentIndexes(dates: songs.map(\.lastPlayedDate), days: days, now: Date()) {
                if indexes.isEmpty { return emptyHistory(days: days) }
                songs = indexes.map { songs[$0] }
                window = days
            }
            let lines = songs.prefix(capped).map { song in
                AskMusicLine.recentLine(
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle,
                    duration: song.duration,
                    artwork: cover(song.artwork)
                )
            }
            var text = lines.joined(separator: "\n")
            if let window {
                text += "\nHistory: \(window)"
            }
            return text
        } catch {
            return "Music isn't available."
        }
    }

    private static let historyFetchLimit = 30

    private static func emptyHistory(days: Int) -> String {
        switch days {
        case 7: "Nothing was played in the past week."
        case 30: "Nothing was played in the past month."
        case 1: "Nothing was played today."
        case 2: "Nothing was played yesterday."
        default: "Nothing was played in that time."
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
                        year: year(item.releaseDate),
                        artwork: cover(item.artwork)
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
                    duration: item.duration,
                    artwork: cover(item.artwork)
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
                    songs: 0,
                    artwork: cover(item.artwork)
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

    private static func cover(_ artwork: Artwork?) -> String {
        artwork?.url(width: 300, height: 300)?.absoluteString ?? ""
    }

    /// Plays one catalog song, album, or playlist. The card calls this. Tests do not.
    package static func play(kind: AskMusicKind, title: String, artist: String) async throws -> String {
#if os(watchOS)
        // Apple Watch has no music player to drive.
        throw AskMusicIntentError.unavailable
#else
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
                    AskMusicPlayer.shared.queue = .init(for: [song])
                }
                try await AskMusicPlayer.shared.play()
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
                    AskMusicPlayer.shared.queue = .init(for: [album])
                }
                try await AskMusicPlayer.shared.play()
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
                    AskMusicPlayer.shared.queue = .init(for: [playlist])
                }
                try await AskMusicPlayer.shared.play()
                return played
            }
        } catch let error as AskMusicIntentError {
            throw error
        } catch {
            throw AskMusicIntentError.unavailable
        }
#endif
    }

    /// Starts the song already in the system queue. Nil when that song is a different one.
    @MainActor
    private static func resumeQueued(title: String, artist: String) async throws -> String? {
#if os(watchOS)
        // Apple Watch has no music player to drive.
        return nil
#else
        guard let current = queuedTitle(matching: title, artist: artist) else { return nil }
        do {
            try await AskMusicPlayer.shared.play()
            return current
        } catch {
            throw AskMusicIntentError.unavailable
        }
#endif
    }

    /// The song already in the system queue. Playing it does not search the catalog.
    @MainActor
    private static func queuedTitle(matching title: String, artist: String) -> String? {
#if os(watchOS)
        // Apple Watch has no music player to drive.
        return nil
#else
        guard let entry = AskMusicPlayer.shared.queue.currentEntry else { return nil }
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
#endif
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
public enum AskMusicKind: String, AppEnum, Sendable, Equatable {
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

/// Play, pause, previous, or next on the now-playing card.
package enum AskMusicTransportAction: String, AppEnum {
    case toggle
    case previous
    case next

    package static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Music Transport")
    package static let caseDisplayRepresentations: [AskMusicTransportAction: DisplayRepresentation] = [
        .toggle: "Play or Pause",
        .previous: "Previous",
        .next: "Next"
    ]
}

extension AskMusicRead {
    /// Play, pause, or skip from the now-playing card.
    @MainActor
    package static func transport(_ action: AskMusicTransportAction) async throws {
#if os(watchOS)
        // Apple Watch has no music player to drive.
        throw AskMusicIntentError.unavailable
#else
        let status = await MusicAuthorization.request()
        guard status == .authorized else { throw AskMusicIntentError.denied }
        let player = AskMusicPlayer.shared
        do {
            switch action {
            case .toggle:
                if player.state.playbackStatus == .playing {
                    player.pause()
                } else {
                    try await player.play()
                }
            case .previous:
                try await player.skipToPreviousEntry()
            case .next:
                try await player.skipToNextEntry()
            }
        } catch let error as AskMusicIntentError {
            throw error
        } catch {
            throw AskMusicIntentError.unavailable
        }
#endif
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

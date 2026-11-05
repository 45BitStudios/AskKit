#if !os(watchOS)
import AppIntents
import AskKit
import AskKitIntents
import Foundation
import MusicKit
import SwiftUI

/// What is playing now. Artwork, scrubber, and transport sit on one card.
struct AskNowPlayingCard: View {
    var item: AskMusicLine.Item
    /// Host assistant name for "Played by …". Empty keeps a plain Now Playing label.
    var playedBy: String = ""
    /// Fixed elapsed seconds for the Cards gallery. Nil reads the system player.
    var previewElapsed: TimeInterval? = nil
    /// Fixed playing state for the Cards gallery.
    var previewPlaying: Bool? = nil

    @State private var cover: AskPlatformImage?
    @State private var elapsed: TimeInterval = 0
    @State private var playing = false
    @State private var scrubbing = false

    private let accent = Color.pink
    private let artSize: CGFloat = 64

    @Environment(\.askCardStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AskCardMark(title: "Now playing", symbol: "play.circle.fill", tint: accent)
            HStack(alignment: .center, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !item.artist.isEmpty {
                        Text(item.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !playedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Played by \(playedBy)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Now Playing")
            .accessibilityValue(spokenValue)

            if style == .fullScreen {
                scrubber
                transport
            }
        }
        .askCardSurface()
        .accessibilityElement(children: .contain)
        .task(id: item.artwork) {
            await loadCover()
        }
        .task(id: previewKey) {
            await observePlayback()
        }
    }

    private var transport: some View {
        HStack(spacing: 36) {
                transportButton(
                    symbol: "backward.fill",
                    label: "Previous song",
                    intent: AskMusicTransportTap(.previous)
                )
                transportButton(
                    symbol: playing ? "pause.fill" : "play.fill",
                    label: playing ? "Pause" : "Play",
                    intent: AskMusicTransportTap(.toggle),
                    prominent: true
                )
                transportButton(
                    symbol: "forward.fill",
                    label: "Next song",
                    intent: AskMusicTransportTap(.next)
                )
            }
            .frame(maxWidth: .infinity)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.pink, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: artSize, height: artSize)
            if let cover {
                Image(askImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: artSize, height: artSize)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 6) {
#if os(tvOS)
            // Apple TV has no slider. The remote scrubs in the Music app.
            ProgressView(value: min(max(elapsed, 0), duration), total: max(duration, 0.001))
                .tint(.primary)
                .accessibilityLabel("Playback position")
                .accessibilityValue(AskMusicLine.playhead(elapsed))
#else
            Slider(
                value: Binding(
                    get: { min(max(elapsed, 0), duration) },
                    set: { elapsed = $0 }
                ),
                in: 0...max(duration, 0.001),
                onEditingChanged: { editing in
                    if scrubbing, !editing, previewElapsed == nil {
#if !os(watchOS)
                        AskMusicPlayer.shared.playbackTime = elapsed
#endif
                    }
                    scrubbing = editing
                }
            )
            .tint(.primary)
            .disabled(duration <= 0 && previewElapsed == nil)
            .accessibilityLabel("Playback position")
            .accessibilityValue(AskMusicLine.playhead(elapsed))
#endif

            HStack {
                Text(AskMusicLine.playhead(elapsed))
                Spacer()
                Text(AskMusicLine.playhead(max(duration - elapsed, 0), remaining: true))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func transportButton(
        symbol: String,
        label: String,
        intent: AskMusicTransportTap,
        prominent: Bool = false
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(prominent ? .title2.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var duration: TimeInterval {
        item.duration ?? 0
    }

    private var spokenValue: String {
        [item.title, item.artist].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var previewKey: String {
        "\(previewElapsed ?? -1)|\(previewPlaying?.description ?? "live")|\(item.title)"
    }

    private func loadCover() async {
        cover = nil
        guard let data = await AskMusicLine.imageData(item.artwork) else { return }
        guard !Task.isCancelled, let image = AskPlatformImage(data: data) else { return }
        cover = image
    }

    @MainActor
    private func observePlayback() async {
        if let previewElapsed {
            elapsed = previewElapsed
            playing = previewPlaying ?? false
            return
        }
#if !os(watchOS)
        while !Task.isCancelled {
            let player = AskMusicPlayer.shared
            playing = player.state.playbackStatus == .playing
            if !scrubbing {
                elapsed = player.playbackTime
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
#endif
    }
}

/// One song or one album. Several results page, the same way contacts do.
struct AskMusicCard: View {
    var item: AskMusicLine.Item

    @State private var cover: AskPlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AskCardMark(title: badgeTitle, symbol: badgeSymbol, tint: accent)
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(plate)
                        .frame(width: 76, height: 76)
                    if let cover {
                        Image(askImage: cover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: badgeSymbol)
                            .font(.title)
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                    }
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
        .askCardSurface()
        .accessibilityElement(children: .contain)
        .task(id: item.artwork) {
            await loadCover()
        }
    }

    private func loadCover() async {
        cover = nil
        guard let data = await AskMusicLine.imageData(item.artwork) else { return }
        guard !Task.isCancelled, let image = AskPlatformImage(data: data) else { return }
        cover = image
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
#endif

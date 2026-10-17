import AppIntents
import AskKit
import Foundation
import MusicKit
import SwiftUI

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
package struct AskMusicPlayTap: AppIntent {
    package static let title: LocalizedStringResource = "Play Music"
    package static let isDiscoverable = false

    package static var supportedModes: IntentModes { .background }
    package static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Kind")
    var kind: AskMusicKind

    @Parameter(title: "Title")
    var itemTitle: String

    @Parameter(title: "Artist")
    var artist: String

    package init() {}

    package init(kind: AskMusicKind, title: String, artist: String) {
        self.kind = kind
        self.itemTitle = title
        self.artist = artist
    }

    package func perform() async throws -> some IntentResult {
        _ = try await AskMusicRead.play(kind: kind, title: itemTitle, artist: artist)
        return .result()
    }
}

/// Transport on the now-playing card. Undiscoverable so a tap does not open a second shortcut window.
package struct AskMusicTransportTap: AppIntent {
    package static let title: LocalizedStringResource = "Control Music"
    package static let isDiscoverable = false

    package static var supportedModes: IntentModes { .background }
    package static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Action")
    var action: AskMusicTransportAction

    package init() {
        self.action = .toggle
    }

    package init(_ action: AskMusicTransportAction) {
        self.action = action
    }

    package func perform() async throws -> some IntentResult {
        try await AskMusicRead.transport(action)
        return .result()
    }
}

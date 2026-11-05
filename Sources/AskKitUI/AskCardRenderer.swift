#if !os(watchOS)
import AskKit
import AskKitIntents
import SwiftUI

/// Draws the cards AskKit builds from Apple sources, generative trees, and the capabilities list.
///
/// ``AskChatView`` and `AskIntentClient` install this themselves. Call ``install()`` before reading
/// `AskIntentCard.view` anywhere else, or a built-in card draws nothing.
@MainActor
public enum AskCardRenderer {
    public static func install() {
        guard AskCardRendering.render == nil else { return }
        AskCardRendering.render = { AnyView(view(for: $0)) }
    }

    @ViewBuilder
    static func view(for card: AskBuiltInCard) -> some View {
        switch card {
        case .calendar(let title, let items):
            AskCalendarCard(title: title, items: items)
        case .reminders(let title, let items):
            AskReminderCard(title: title, items: items)
        case .places(let title, let places, let showsCoordinates):
            AskLocationMapCard(title: title, places: places, showsCoordinates: showsCoordinates)
        case .contact(let person):
            AskContactCard(person: person)
        case .health(let metric, let range, let lines):
            AskHealthChartCard(metric: metric, initial: range, lines: lines)
        case .nowPlaying(let item, let playedBy):
            AskNowPlayingCard(item: item, playedBy: playedBy)
        case .music(let item):
            AskMusicCard(item: item)
        case .alarm(let item):
            AskAlarmCard(item: item)
        case .weather(let forecast):
            AskWeatherCard(forecast: forecast)
        case .web(let lines):
            AskWebCard(lines: lines)
        case .photos(let title, let photos, let shareText):
            AskPhotosCard(title: title, photos: photos, shareText: shareText)
        case .generated(let root, let title):
            AskGeneratedCardView(root: root, title: title)
        case .capabilities(let groups):
            AskCapabilitiesCard(groups: groups)
        }
    }
}
#endif

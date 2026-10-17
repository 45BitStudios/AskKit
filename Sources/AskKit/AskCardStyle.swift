import AppIntents
import SwiftUI

/// Where a card is drawn. Snippet is Shortcuts/Siri. Chat is the transcript. Full screen is the zoomed detail.
/// Cards read ``EnvironmentValues/askCardStyle`` and thin or grow their chrome. Chat → full screen uses an App Store–style zoom.
public enum AskCardStyle: String, Equatable, Sendable, CaseIterable, Hashable {
    /// Compact card in the Shortcuts / Siri snippet window.
    case snippet
    /// Card under the answer bubble in ``AskChatView``.
    case chat
    /// Zoomed detail after opening an expandable chat card.
    case fullScreen

    public static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    public var padding: CGFloat {
        switch self {
        case .snippet: 12
        case .chat: 16
        case .fullScreen: 20
        }
    }

    public var contentSpacing: CGFloat {
        switch self {
        case .snippet: 6
        case .chat: 8
        case .fullScreen: 14
        }
    }

    public var valueFont: Font {
        switch self {
        case .snippet: .title3.weight(.semibold)
        case .chat: .title2.weight(.semibold)
        case .fullScreen: .largeTitle.weight(.semibold)
        }
    }

    public var titleFont: Font {
        switch self {
        case .snippet: .headline
        case .chat: .title3.weight(.semibold)
        case .fullScreen: .title2.weight(.semibold)
        }
    }

    public var detailFont: Font {
        switch self {
        case .snippet: .footnote
        case .chat, .fullScreen: .subheadline
        }
    }

    /// Hero number. Rounded and a step above the title so a stat does not look like body text.
    public var displayFont: Font {
        switch self {
        case .snippet: .system(size: 34, weight: .semibold, design: .rounded)
        case .chat: .system(size: 44, weight: .semibold, design: .rounded)
        case .fullScreen: .system(size: 64, weight: .semibold, design: .rounded)
        }
    }

    /// Sentence with no number. Medium weight, larger than a caption, smaller than the hero.
    public var quoteFont: Font {
        switch self {
        case .snippet: .title3.weight(.medium)
        case .chat: .title2.weight(.medium)
        case .fullScreen: .title.weight(.medium)
        }
    }

    public var heroSymbol: CGFloat {
        switch self {
        case .snippet: 34
        case .chat: 44
        case .fullScreen: 64
        }
    }

    public var miniSymbol: CGFloat {
        switch self {
        case .snippet: 16
        case .chat: 22
        case .fullScreen: 28
        }
    }

    public var plateSize: CGFloat {
        switch self {
        case .snippet: 52
        case .chat: 64
        case .fullScreen: 88
        }
    }

    /// Snippet keeps secondary lines to one row. Chat and full screen show them fully.
    public var detailLineLimit: Int? {
        switch self {
        case .snippet: 1
        case .chat, .fullScreen: nil
        }
    }

    /// Fixed plot height for snippet and chat. Full screen ignores this and fills the page.
    public var chartHeight: CGFloat { 168 }

    /// The zoomed page. The tint runs to the screen edges and the plot takes the leftover height.
    public var fillsPage: Bool { self == .fullScreen }
}

extension EnvironmentValues {
    @Entry public var askCardStyle: AskCardStyle = .chat
    /// Card fill in chat and snippet. Defaults to the speech-bubble color.
    @Entry public var askBubbleFill: Color = AskPlatform.bubbleFill
}

package enum AskCardSymbol {
    package static func symbol(for title: String) -> String {
        namedSymbol(for: title) ?? "sparkles"
    }

    /// A system image name for a DSL symbol node. A known card title maps to its symbol.
    /// An unknown word is dropped so the card does not invent a mark.
    package static func systemName(for raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if AskPlatform.hasSymbol(name) {
            return name
        }
        return namedSymbol(for: name)
    }

    package static func tint(for title: String) -> Color {
        switch title.lowercased() {
        case "calendar": .red
        case "reminders": .orange
        case "alarm", "alarms": .orange
        case "contact": .blue
        case "place", "location", "nearby", "coordinates": .green
        case "steps", "figure.walk", "figure.stairs", "flame", "flame.fill": .orange
        case "heart rate", "heart.fill": .pink
        case "song", "music", "music unavailable", "nothing playing", "now playing", "music.note", "play.circle.fill": .pink
        case "album": .indigo
        case "daily forecast", "hourly forecast", "weather", "no forecast", "cloud.sun.fill", "cloud.sun", "cloud.fill", "cloud.rain.fill": .blue
        case "sun.max.fill", "sun.max": .orange
        case "car.fill", "car.side": .blue
        case "checklist", "circle", "checkmark.circle": .orange
        case "moon.stars.fill", "moon.fill", "moon.stars": .indigo
        case "clock", "clock.fill": .orange
        case "web", "page": .blue
        case "photos", "photo", "screenshots": .teal
        case "capabilities": .indigo
        case "charge", "skill": .green
        default: .indigo
        }
    }

    private static func namedSymbol(for title: String) -> String? {
        switch title.lowercased() {
        case "calendar": "calendar"
        case "reminders": "checklist"
        case "alarm", "alarms": "alarm.fill"
        case "contact": "person.fill"
        case "place", "location", "nearby": "mappin.and.ellipse"
        case "coordinates": "location.circle"
        case "steps": "figure.walk"
        case "heart rate": "heart.fill"
        case "song", "music", "music unavailable", "nothing playing": "music.note"
        case "now playing": "play.circle.fill"
        case "album": "square.stack.fill"
        case "daily forecast", "weather", "no forecast": "cloud.sun.fill"
        case "hourly forecast": "clock.fill"
        case "web", "page": "globe"
        case "photos", "photo", "screenshots": "photo.on.rectangle"
        case "capabilities": "sparkles"
        case "charge", "skill": "bolt.fill"
        default: nil
        }
    }
}

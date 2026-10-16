import AppIntents
import SwiftUI
import UIKit

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
    @Entry public var askBubbleFill: Color = Color(uiColor: .secondarySystemBackground)
}

/// Opens a chat card into full screen. The chat screen owns the zoom namespace.
@MainActor
@Observable
final class AskCardExpansion {
    var pageID: UUID?
    var card: AskIntentCard?
    /// Separate from `pageID` so closing does not clear the source the dismiss animation is using.
    var presented = false

    func open(pageID: UUID, card: AskIntentCard) {
        self.pageID = pageID
        self.card = card
        presented = true
    }
}

extension EnvironmentValues {
    @Entry var cardExpansion: AskCardExpansion?
    @Entry var cardZoomNamespace: Namespace.ID?
}

/// Full-screen card after an App Store–style zoom from the transcript.
struct AskCardFullScreen: View {
    var card: AskIntentCard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { proxy in
            card.view
                .environment(\.askCardStyle, .fullScreen)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    AskCue.tap()
                    dismiss()
                }
            }
            if !card.shareText.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: card.shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .accessibilityLabel(card.title.isEmpty ? "Card" : card.title)
    }
}

/// Marks the chat card the full-screen zoom grows from. Long-press menus stay off this view.
struct AskCardZoomSource: ViewModifier {
    var pageID: UUID
    var card: AskIntentCard
    var enabled: Bool

    @Environment(\.cardZoomNamespace) private var namespace
    @Environment(\.cardExpansion) private var expansion

    func body(content: Content) -> some View {
        if enabled, let namespace, let expansion {
            content
                .contentShape(AskCardStyle.shape)
                .matchedTransitionSource(id: pageID, in: namespace) { source in
                    source.clipShape(AskCardStyle.shape)
                }
                .onTapGesture {
                    AskCue.tap()
                    expansion.open(pageID: pageID, card: card)
                }
                .accessibilityAction(named: "Open") {
                    expansion.open(pageID: pageID, card: card)
                }
        } else {
            content
        }
    }
}

/// Rounded square, gradient, and name. Sits at the top left of every card.
public struct AskCardMark: View {
    public var title: String
    public var symbol: String
    public var tint: Color

    public init(title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    private let side: CGFloat = 36

    public var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.mix(with: .white, by: 0.28), tint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Full-width action inside a card. It pages with the card. Uses prominent Liquid Glass tinted to the card.
struct AskCardCTA<I: AppIntent>: View {
    var title: LocalizedStringKey
    var symbol: String
    var tint: Color
    var intent: I
    var accessibilityLabel: Text
    /// A full-width capsule. Off for a button that sits beside a label.
    var expands: Bool = true
    /// Off for the icon-only directions control beside a place.
    var showsTitle: Bool = true

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: showsTitle ? 8 : 0) {
                Image(systemName: symbol)
                    .font(showsTitle ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    .accessibilityHidden(true)
                if showsTitle {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: showsTitle ? nil : 44, minHeight: 44)
            .padding(.horizontal, showsTitle ? 16 : 0)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .buttonBorderShape(showsTitle ? .capsule : .circle)
        .frame(maxWidth: expands ? .infinity : nil)
        .accessibilityLabel(accessibilityLabel)
    }
}

enum AskCardSymbol {
    static func symbol(for title: String) -> String {
        namedSymbol(for: title) ?? "sparkles"
    }

    /// A system image name for a DSL symbol node. A known card title maps to its symbol.
    /// An unknown word is dropped so the card does not invent a mark.
    static func systemName(for raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if UIImage(systemName: name) != nil {
            return name
        }
        return namedSymbol(for: name)
    }

    static func tint(for title: String) -> Color {
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

extension View {
    /// Shared answer-card surface. Chat and snippet use the speech-bubble fill. Full screen is the page.
    /// `tint` is unused; the color lives on ``AskCardMark``.
    public func askCardSurface(tint: Color? = nil) -> some View {
        modifier(AskCardSurfaceModifier(tint: tint))
    }
}

private struct AskCardSurfaceModifier: ViewModifier {
    /// Kept so existing call sites compile. The fill does not use it.
    var tint: Color?
    @Environment(\.askCardStyle) private var style
    @Environment(\.askBubbleFill) private var bubble

    func body(content: Content) -> some View {
        if style.fillsPage {
            content
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(.systemBackground).ignoresSafeArea())
        } else {
            content
                .padding(style.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bubble, in: AskCardStyle.shape)
        }
    }
}

import AppIntents
import AskKit
import AskKitIntents
import SwiftUI

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
        .askInlineTitle()
        .askHiddenBarBackground()
        .toolbar {
            ToolbarItem(placement: .askTrailing) {
                Button("Done") {
                    AskCue.tap()
                    dismiss()
                }
            }
#if !os(tvOS)
            if !card.shareText.isEmpty {
                ToolbarItem(placement: .askLeading) {
                    ShareLink(item: card.shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
#endif
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
#if os(visionOS)
        .buttonStyle(.borderedProminent)
#else
        .buttonStyle(.glassProminent)
#endif
        .tint(tint)
        .buttonBorderShape(showsTitle ? .capsule : .circle)
        .frame(maxWidth: expands ? .infinity : nil)
        .accessibilityLabel(accessibilityLabel)
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
                .background(AskPlatform.background.ignoresSafeArea())
        } else {
            content
                .padding(style.padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bubble, in: AskCardStyle.shape)
        }
    }
}

extension EnvironmentValues {
    @Entry var cardExpansion: AskCardExpansion?
    @Entry var cardZoomNamespace: Namespace.ID?
}

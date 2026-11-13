#if !os(watchOS)
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

    @ScaledMetric(relativeTo: .caption) private var side = 36
    @ScaledMetric(relativeTo: .caption) private var glyph = 16

    public var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: AskCardRadius.medium, style: .continuous)
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
                        .font(.system(size: glyph, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Full-width action inside a card. It pages with the card.
/// A labeled button is the primary action. An icon-only button is secondary.
/// Neither uses Liquid Glass. Apple TV keeps the system button so focus can draw it.
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

    /// Floor for the control. The glyph can grow past this with Dynamic Type.
    private static let minimumHit: CGFloat = 44

    @ScaledMetric(relativeTo: .body) private var glyph = 15
    @Environment(\.tint) private var hostTint: Color?

    /// Host `.tint` wins. Otherwise the caller’s semantic system color is used.
    private var actionTint: Color { hostTint ?? tint }

    private var hit: CGFloat { max(Self.minimumHit, glyph + 20) }

    var body: some View {
        styled
            .frame(maxWidth: expands ? .infinity : nil)
    }

    private var button: some View {
        Button(intent: intent) {
            HStack(spacing: showsTitle ? 8 : 0) {
                Image(systemName: symbol)
                    .font(.system(size: glyph, weight: .semibold))
                    .accessibilityHidden(true)
                if showsTitle {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(minWidth: showsTitle ? nil : hit, minHeight: hit)
            .padding(.horizontal, showsTitle ? 16 : 0)
            .contentShape(.rect)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var styled: some View {
#if os(tvOS)
        button.tint(actionTint)
#else
        button
            .buttonStyle(showsTitle ? .borderedProminent : .bordered)
            .buttonBorderShape(showsTitle ? .capsule : .circle)
            .tint(actionTint)
#endif
    }
}

extension View {
    /// Shared answer-card surface. Chat and snippet use ``EnvironmentValues/askCardFill``,
    /// which matches the host bubble unless the host sets a different fill. Full screen is the page.
    /// `tint` is unused; the color lives on ``AskCardMark``.
    public func askCardSurface(tint: Color? = nil) -> some View {
        modifier(AskCardSurfaceModifier(tint: tint))
    }
}

private struct AskCardSurfaceModifier: ViewModifier {
    /// Kept so existing call sites compile. The fill does not use it.
    var tint: Color?
    @Environment(\.askCardStyle) private var style
    @Environment(\.askCardFill) private var cardFill
    @Environment(\.colorSchemeContrast) private var contrast

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
                .background(cardFill, in: AskCardStyle.shape)
                .overlay {
                    if contrast == .increased {
                        AskCardStyle.shape.strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
        }
    }
}

extension EnvironmentValues {
    @Entry var cardExpansion: AskCardExpansion?
    @Entry var cardZoomNamespace: Namespace.ID?
}
#endif

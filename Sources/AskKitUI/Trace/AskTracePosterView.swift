#if DEBUG
import AskKit
import AskKitIntents
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension AskTracePoster {
    @MainActor
    static func image(for turn: AskTraceTurn) -> AskPlatformImage? {
#if os(iOS) || os(visionOS) || os(tvOS)
        let style: ColorScheme = UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
        let scale = UITraitCollection.current.displayScale
#elseif os(macOS)
        let style: ColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        let scale = NSScreen.main?.backingScaleFactor ?? 2
#else
        let style: ColorScheme = .dark
        let scale: CGFloat = 2
#endif
        let poster = AskTracePosterView(content: content(for: turn))
            .frame(width: width, alignment: .topLeading)
            .environment(\.colorScheme, style)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = scale > 1 ? scale : 3
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        return renderer.askImage
    }
}

private struct AskTracePosterView: View {
    var content: AskTracePosterContent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask Trace")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            bubble(title: "Question", text: content.question, leading: false, fill: Color.accentColor, ink: .white)
            bubble(
                title: "Answer",
                text: content.answer,
                leading: true,
                fill: AskPlatform.bubbleFill,
                ink: .primary
            )
            ForEach(content.cards.indices, id: \.self) { index in
                let card = content.cards[index]
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.headline)
                    if !card.body.isEmpty {
                        Text(card.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .askCardSurface()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AskPlatform.background)
    }

    private func bubble(title: String, text: String, leading: Bool, fill: Color, ink: Color) -> some View {
        VStack(alignment: leading ? .leading : .trailing, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .foregroundStyle(ink)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 320, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }
}
#endif

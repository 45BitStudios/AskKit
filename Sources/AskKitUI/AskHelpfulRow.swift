import AskKit
import AskKitIntents
import SwiftUI

/// The prompt and thumbs. Outline until chosen, then filled in `tint`. A second tap on the chosen thumb clears it.
public struct AskHelpfulRow: View {
    public var title: LocalizedStringResource
    public var yesLabel: LocalizedStringResource
    public var noLabel: LocalizedStringResource
    public var vote: Bool?
    public var tint: Color
    public var onVote: (Bool) -> Void

    public init(
        title: LocalizedStringResource,
        yesLabel: LocalizedStringResource,
        noLabel: LocalizedStringResource,
        vote: Bool?,
        tint: Color,
        onVote: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.yesLabel = yesLabel
        self.noLabel = noLabel
        self.vote = vote
        self.tint = tint
        self.onVote = onVote
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            AskThumbButton(
                helpful: true,
                symbol: "hand.thumbsup",
                label: yesLabel,
                selected: vote == true,
                tint: tint,
                onVote: onVote
            )
            AskThumbButton(
                helpful: false,
                symbol: "hand.thumbsdown",
                label: noLabel,
                selected: vote == false,
                tint: tint,
                onVote: onVote
            )
        }
    }
}

private struct AskThumbButton: View {
    let helpful: Bool
    let symbol: String
    let label: LocalizedStringResource
    let selected: Bool
    let tint: Color
    let onVote: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    var body: some View {
        Button {
            if !reduceMotion {
                bounce += 1
            }
            AskCue.tap()
            onVote(helpful)
        } label: {
            Image(systemName: selected ? "\(symbol).fill" : symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .symbolEffect(.bounce, value: bounce)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? tint : Color.primary)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

import SwiftUI

/// One turn in the order the chat shows it. Used to place the feedback row and to find the question.
public struct AskFeedbackTurn: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var isUser: Bool
    public var text: String

    public init(id: UUID, isUser: Bool, text: String) {
        self.id = id
        self.isUser = isUser
        self.text = text
    }
}

/// A thumb on one answer. `helpful` is nil when the person taps the selected thumb again.
/// The question is included. The answer text is not.
public struct AskAnswerVote: Sendable, Equatable {
    public var turnID: UUID
    public var helpful: Bool?
    public var question: String

    public init(turnID: UUID, helpful: Bool?, question: String) {
        self.turnID = turnID
        self.helpful = helpful
        self.question = question
    }
}

/// Where the "Was this answer helpful?" row goes, and how a second tap clears a thumb.
public enum AskFeedback {
    /// The latest answer. A question that has no answer yet keeps the row on the previous answer.
    /// Nil for a greeting, a lone question, or an answer that did not follow a question.
    public static func anchorID(in turns: [AskFeedbackTurn]) -> UUID? {
        guard let lastUser = turns.lastIndex(where: \.isUser) else { return nil }
        let after = turns.index(after: lastUser)
        if after < turns.endIndex {
            return turns[after...].last(where: { !$0.isUser })?.id
        }
        guard lastUser > turns.startIndex else { return nil }
        let previous = turns.index(before: lastUser)
        guard !turns[previous].isUser else { return nil }
        guard turns[..<previous].contains(where: \.isUser) else { return nil }
        return turns[previous].id
    }

    /// The user turn this answer is responding to. Empty when the answer has no question.
    public static func question(before id: UUID, in turns: [AskFeedbackTurn]) -> String {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return "" }
        for turn in turns[..<index].reversed() where turn.isUser {
            return turn.text
        }
        return ""
    }

    /// Selects `helpful`, or removes the vote when that same thumb is already selected.
    public static func votes(_ current: [UUID: Bool], toggling id: UUID, helpful: Bool) -> [UUID: Bool] {
        var next = current
        if current[id] == helpful {
            next.removeValue(forKey: id)
        } else {
            next[id] = helpful
        }
        return next
    }
}

/// Shows the feedback row under the latest answer. Omit it and the row stays hidden.
/// The chat keeps the selection. `votes` is what to show the first time the chat appears.
/// `onVote` is where the app records the rating.
public struct AskAnswerFeedback {
    public var title: LocalizedStringResource
    public var yesLabel: LocalizedStringResource
    public var noLabel: LocalizedStringResource
    public var votes: [UUID: Bool]
    public var onVote: @MainActor (AskAnswerVote) -> Void

    public init(
        title: LocalizedStringResource = "Was this answer helpful?",
        yesLabel: LocalizedStringResource = "Yes, this was helpful",
        noLabel: LocalizedStringResource = "No, this was not helpful",
        votes: [UUID: Bool] = [:],
        onVote: @escaping @MainActor (AskAnswerVote) -> Void = { _ in }
    ) {
        self.title = title
        self.yesLabel = yesLabel
        self.noLabel = noLabel
        self.votes = votes
        self.onVote = onVote
    }
}

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

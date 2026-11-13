#if !os(watchOS)
import AskKit
import AskKitIntents
import SwiftUI

/// Optimistic outgoing text that morphs from the composer into the transcript.
struct AskPendingSend: Equatable {
    let id: UUID
    let text: String
}

/// Kavsoft-style chat bubble send: the typed line leaves the composer and lands as the user bubble.
enum AskSendMorph {
    static let animation: Animation = .smooth(duration: 0.38)

    /// True when the composer text can fly into the transcript.
    static func shouldMorph(text: String, imageCount: Int, reduceMotion: Bool) -> Bool {
        !reduceMotion
            && imageCount == 0
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Drops the persisted user turn the pending bubble is standing in for, so the morph does not double.
    static func hidingPendingUserTurn<Turn>(
        _ turns: [Turn],
        pendingText: String?,
        role: (Turn) -> String,
        text: (Turn) -> String
    ) -> [Turn] {
        guard let pendingText else { return turns }
        guard let index = turns.lastIndex(where: { role($0) == "user" && text($0) == pendingText }) else {
            return turns
        }
        var copy = turns
        copy.remove(at: index)
        return copy
    }
}

/// Chrome shared by the composer source and the transcript destination during a send morph.
struct AskSendMorphBubble: View {
    let text: String
    let appearance: AskChatAppearance
    /// Composer source spans the field; the transcript destination hugs the text.
    var fillsWidth = false

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(appearance.userForeground)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .background(appearance.userBubble, in: RoundedRectangle(cornerRadius: AskCardRadius.large, style: .continuous))
    }
}
#endif

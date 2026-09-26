import SwiftData
import SwiftUI

/// Three chips, the saved transcript, and a composer.
/// An intent skill shows that skill's card. A reply skill shows Ask's text.
/// A search skill shows whichever its `render` returned.
public struct AskChatView: View {
    private let assistant: AskAssistant
    private let onAction: (AskAction) -> Void

    public init(assistant: AskAssistant, onAction: @escaping (AskAction) -> Void = { _ in }) {
        self.assistant = assistant
        self.onAction = onAction
    }

    public var body: some View {
        AskChatScreen(assistant: assistant, onAction: onAction)
            .modelContainer(assistant.modelContainer)
    }
}

private struct AskChatScreen: View {
    let assistant: AskAssistant
    let onAction: (AskAction) -> Void

    @Query(sort: \AskTurnRecord.createdAt) private var turns: [AskTurnRecord]
    @State private var chips: [AskChip] = []
    @State private var draft = ""
    @State private var liveCards: [UUID: AskIntentCard] = [:]
    @State private var liveReplies: [UUID: AskReply] = [:]
    @State private var replayedCards: [UUID: AskIntentCard] = [:]

    private var visibleTurns: [AskTurnRecord] {
        turns.filter { $0.thread?.assistantName == assistant.configuration.assistantName }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if visibleTurns.isEmpty {
                        Text("Ask a question, or start with a suggestion.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(visibleTurns) { turn in
                        bubble(turn)
                    }
                }
                .padding()
            }
            chipRow
            composer
        }
        .background(.background)
        .task { chips = await assistant.chips() }
    }

    private var header: some View {
        HStack {
            Text(assistant.configuration.assistantName)
                .font(.headline)
            Spacer()
            Button("Clear") {
                try? assistant.clearThread()
                liveCards = [:]
                liveReplies = [:]
                replayedCards = [:]
            }
            .disabled(visibleTurns.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func bubble(_ turn: AskTurnRecord) -> some View {
        if turn.role == "user" {
            Text(turn.text)
                .padding(12)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else if let card = liveCards[turn.id] ?? replayedCards[turn.id] {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.spoken)
                card.view
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(turn.spoken.isEmpty ? turn.text : turn.spoken)
                if let reply = liveReplies[turn.id] {
                    ForEach(reply.actions) { action in
                        Button(action.title) { onAction(action) }
                            .buttonStyle(.bordered)
                    }
                }
                if turn.skillID.isEmpty == false, assistant.configuration.skill(id: turn.skillID)?.drawsCard(turn) == true {
                    Color.clear
                        .frame(height: 1)
                        .task(id: turn.id) {
                            if let card = await assistant.intentCard(for: turn.id) {
                                replayedCards[turn.id] = card
                            }
                        }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(chips) { chip in
                    Button(chip.title) {
                        Task { await sendChip(chip) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private var composer: some View {
        HStack {
            TextField("Ask", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await sendDraft() } }
            Button("Send") { Task { await sendDraft() } }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        await remember(await assistant.handle(utterance: text))
    }

    private func sendChip(_ chip: AskChip) async {
        await remember(await assistant.handle(chip: chip))
    }

    private func remember(_ result: AskTurnResult) async {
        guard let id = try? assistant.transcript().last?.id else { return }
        switch result.fulfillment {
        case .reply(let reply):
            liveReplies[id] = reply
        case .intent(let card):
            liveCards[id] = card
        }
    }
}

private extension AskSkill {
    func drawsCard(_ turn: AskTurnRecord) -> Bool {
        switch fulfillment {
        case .intent:
            return true
        case .search:
            return turn.searchItemIDsJSON != nil
        case .reply:
            return false
        }
    }
}

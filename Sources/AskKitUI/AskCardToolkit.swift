#if !os(watchOS)
#if DEBUG
import AskKit
import AskKitIntents
import SwiftUI

/// Debug sheet for laying out a card from facts. The model composes the tree. A failure uses the fact layout.
struct AskCardToolkitScreen: View {
    let assistant: AskAssistant

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scenario = ""
    @State private var title = ""
    @State private var spoken = ""
    @State private var layoutNotes = ""
    @State private var buttonTitle = ""
    @State private var followUp = ""
    @State private var style = AskCardStyle.chat
    @State private var thread = AskGeneratedThread()
    @State private var isComposing = false
    @State private var task: Task<Void, Never>?
    @State private var composeGeneration = 0
    private let composition = AskCompositionProgress.shared

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Write the facts, then create the card. A follow-up adds another card below it. Earlier cards stay.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    AskCardToolkitExamples { example in
                        fill(example)
                        compose(example.blueprint)
                    }
                    scenarioField
                    details
                    ForEach(Array(thread.entries.enumerated()), id: \.element.id) { index, entry in
                        VStack(alignment: .leading, spacing: 8) {
                            if thread.entries.count > 1 {
                                Text(entry.question)
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            AskCardToolkitResult(
                                result: entry.card,
                                style: $style,
                                showsStylePicker: index == 0
                            )
                        }
                        .id(entry.id)
                    }
                    if isComposing {
                        if composition.isRunning {
                            AskCompositionProgressView(snapshot: composition.snapshot)
                        }
                        AskGeneratedCardPlaceholder()
                            .environment(\.askCardStyle, style)
                            .id("card-loading")
                    }
                    if !thread.entries.isEmpty {
                        followUpField
                    }
                }
                .padding(20)
                .padding(.bottom, 12)
            }
            .onChange(of: thread.entries.last?.id) { _, id in
                guard let id else { return }
                scroll(proxy, to: id)
            }
            .onChange(of: isComposing) { _, composing in
                guard composing else { return }
                scroll(proxy, to: "card-loading")
            }
            }
            .navigationTitle("Card toolkit")
            .askLargeTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AskCue.tap()
                        dismiss()
                    }
                }
            }
            .safeAreaBar(edge: .bottom) {
                createButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .onDisappear {
            task?.cancel()
        }
    }

    /// Apple TV and Apple Watch have no text editor, so a growing field stands in.
    @ViewBuilder
    private var scenarioEditor: some View {
#if os(tvOS) || os(watchOS)
        TextField("Scenario", text: $scenario, axis: .vertical)
#else
        TextEditor(text: $scenario)
#endif
    }

    private var scenarioField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenario")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            scenarioEditor
                .font(.body)
                .frame(minHeight: 140)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Scenario")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title, speech, and notes")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextField("Title", text: $title)
                .askRoundedField()
            TextField("Spoken line", text: $spoken)
                .askRoundedField()
            TextField("Button title", text: $buttonTitle)
                .askRoundedField()
            TextField("Layout notes", text: $layoutNotes, axis: .vertical)
                .lineLimit(2...4)
                .askRoundedField()
            Text("Uses \(assistant.configuration.cardSpecialist.title). Leave a field blank and the facts fill it in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var followUpField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Follow-up")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextField("Ask about this card", text: $followUp)
                .askRoundedField()
            Button {
                AskCue.tap()
                addFollowUp()
            } label: {
                Text("Add card")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isComposing || followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add a follow-up card")
        }
    }

    private var createButton: some View {
        Button {
            AskCue.tap()
            compose(nil)
        } label: {
            HStack(spacing: 8) {
                if isComposing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isComposing ? "Creating" : "Create card")
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isComposing || scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(isComposing ? "Creating" : "Create card")
    }

    private func fill(_ example: AskCardToolkitExample) {
        scenario = example.facts
        title = example.title
        spoken = example.spoken
        layoutNotes = example.notes
        buttonTitle = example.button
    }

    private func compose(_ ready: AskGeneratedBlueprint?) {
        let facts = scenario.trimmingCharacters(in: .whitespacesAndNewlines)
        let blueprint = ready ?? AskCardToolkitExample.blueprint(
            title: title,
            spoken: spoken,
            facts: facts,
            notes: layoutNotes,
            button: buttonTitle
        )
        guard !blueprint.facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        task?.cancel()
        composeGeneration += 1
        let generation = composeGeneration
        thread = AskGeneratedThread()
        followUp = ""
        isComposing = true
        task = Task {
            let composed = await assistant.composeCard(from: blueprint)
            guard generation == composeGeneration, !Task.isCancelled else { return }
            thread.append(question: blueprint.title, card: composed)
            isComposing = false
        }
    }

    private func addFollowUp() {
        let question = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !thread.entries.isEmpty else { return }
        let blueprint = AskCardToolkitExample.blueprint(
            title: "",
            spoken: "",
            facts: question,
            notes: layoutNotes,
            button: ""
        )
        followUp = ""
        task?.cancel()
        composeGeneration += 1
        let generation = composeGeneration
        isComposing = true
        let current = thread
        task = Task {
            let next = await assistant.appendCard(question, from: blueprint, to: current)
            guard generation == composeGeneration, !Task.isCancelled else { return }
            thread = next
            isComposing = false
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: some Hashable) {
        let animated = !reduceMotion
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }
}

private struct AskCardToolkitExamples: View {
    var onSelect: (AskCardToolkitExample) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenarios")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(AskCardToolkitExample.samples) { example in
                Button {
                    AskCue.tap()
                    onSelect(example)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(example.title)
                            .font(.headline)
                        Text(example.facts)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Create \(example.title)")
            }
        }
    }
}

private struct AskCardToolkitResult: View {
    var result: AskComposedCard
    @Binding var style: AskCardStyle
    var showsStylePicker = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.layout.sentence)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if showsStylePicker {
            Picker("Preview", selection: $style) {
                Text("Chat").tag(AskCardStyle.chat)
                Text("Snippet").tag(AskCardStyle.snippet)
            }
#if os(watchOS)
            .pickerStyle(.wheel)
#else
            .pickerStyle(.segmented)
#endif
            }
            result.card.view
                .environment(\.askCardStyle, style)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action = result.card.action {
                Text("Button: \(action.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let root = result.card.generatedRoot {
                Text(AskGeneratedCard.outline(root))
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .askSelectable()
                    .accessibilityLabel("Layout tree")
            }
        }
    }
}

struct AskCardToolkitExample: Identifiable {
    var id: String { title }
    var title: String
    var spoken: String
    var facts: String
    var notes: String
    var button: String
    var sources: [AskCardSource] = []

    var blueprint: AskGeneratedBlueprint {
        var blueprint = Self.blueprint(title: title, spoken: spoken, facts: facts, notes: notes, button: button)
        blueprint.sources = sources
        return blueprint
    }

    static func blueprint(
        title: String,
        spoken: String,
        facts: String,
        notes: String,
        button: String
    ) -> AskGeneratedBlueprint {
        let lines = facts
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = name.isEmpty ? String((lines.first ?? "Card").prefix(48)) : name
        let speech = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSpoken = speech.isEmpty ? facts : speech
        let label = button.trimmingCharacters(in: .whitespacesAndNewlines)
        let actions = label.isEmpty ? [] : [AskAction(id: actionID(label), title: label)]
        return AskGeneratedBlueprint(
            title: resolvedTitle,
            spoken: resolvedSpoken,
            facts: facts,
            actions: actions,
            layoutNotes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func actionID(_ title: String) -> String {
        let parts = title.lowercased().split { !$0.isLetter && !$0.isNumber }
        let id = parts.joined(separator: ".")
        return id.isEmpty ? "action" : id
    }

    static let samples: [AskCardToolkitExample] = [
        AskCardToolkitExample(
            title: "Next drive",
            spoken: "Your next drive is at 7:30 a.m.",
            facts: "7:30 a.m.\nNext drive\nFrom the calendar · about 214 miles",
            notes: "Plate car.fill, eyebrow Next drive, then a display stat for the time. Badge Trip. One row for the miles.",
            button: "Trip",
            sources: [AskCardSource(name: "Calendar")]
        ),
        AskCardToolkitExample(
            title: "Battery",
            spoken: "The battery is at 68 percent.",
            facts: "68 percent\nAbout 40 minutes until 80 percent.\nPlugged in at home.",
            notes: "Plate bolt.fill, eyebrow Charge, display stat for the percent. Short rows for the other facts.",
            button: "Charge"
        ),
        AskCardToolkitExample(
            title: "Dinner",
            spoken: "Dinner is salmon for four.",
            facts: "Salmon\nFour servings\n35 minutes\nPantry",
            notes: "Plate fork.knife, eyebrow Pantry, display stat for the dish. Rows for servings and time.",
            button: "Cook"
        ),
        AskCardToolkitExample(
            title: "Agenda",
            spoken: "Friday has three events.",
            facts: "27\nFriday\n11:00 AM Kick-off\n12:00 PM Lunch\n1:00 PM Pack",
            notes: "Plate calendar, eyebrow Friday, display stat for the day. Badge Calendar. Each event is a mini clock symbol beside a row.",
            button: "Calendar",
            sources: [AskCardSource(name: "Calendar")]
        ),
        AskCardToolkitExample(
            title: "Forecast",
            spoken: "It is 72 degrees and partly cloudy.",
            facts: "72°\nPartly cloudy\nHigh 78°\nLow 61°\n9 AM 70°\n12 PM 74°\n3 PM 76°\n6 PM 71°",
            notes: "Hero symbol cloud.sun.fill, eyebrow Partly cloudy, display stat for 72°. Badge Weather. Figures for High and Low. Each hour is a mini symbol above a figure.",
            button: "Weather",
            sources: [AskCardSource(name: "Weather", url: URL(string: "https://weather.example/today"))]
        ),
        AskCardToolkitExample(
            title: "Steps",
            spoken: "You have walked 8,420 steps.",
            facts: "8,420 steps\nDistance 3.2 mi\nFlights 12\nExercise 24 min",
            notes: "Plate figure.walk, eyebrow Today, display stat for the steps. Badge Steps. Each peer figure gets a mini symbol above it. No chart.",
            button: "Activity",
            sources: [AskCardSource(name: "Health")]
        ),
        AskCardToolkitExample(
            title: "Reminders",
            spoken: "You have 3 reminders open.",
            facts: "3 open\nBuy milk, Today\nCall the shop, Tomorrow\nPack the bag, Friday",
            notes: "Plate checklist, eyebrow Open, display stat for the count. Badge Reminders. A mini circle symbol beside each row.",
            button: "Reminders"
        ),
        AskCardToolkitExample(
            title: "Now playing",
            spoken: "Anti-Hero by Taylor Swift is playing.",
            facts: "Anti-Hero\nTaylor Swift\nNow playing",
            notes: "Plate music.note, eyebrow Now playing, display stat for the song, text for the artist. No photo.",
            button: "Play"
        ),
        AskCardToolkitExample(
            title: "Note",
            spoken: "I give myself permission to do what is right for me.",
            facts: "I give myself permission to do what is right for me.",
            notes: "Plate moon.stars.fill and badge Note, then one quote. No stat.",
            button: ""
        )
    ]
}
#endif
#endif

import AppIntents
import SwiftUI

/// The assistant ``AskIntent`` runs.
///
/// Create it on the main actor, then register it in `App.init()`:
/// `AppDependencyManager.shared.add(dependency: client)`.
/// A shortcut can launch the process before any view appears. If this registration is missing, that launch stops in the dependency getter.
@MainActor
public final class AskIntentClient {
    /// The assistant a shortcut runs. Replace this when the app swaps assistants.
    public var assistant: AskAssistant
    /// Trace entry ``AskIntent`` records. ``answer(_:using:entry:)`` uses the entry passed to that call.
    public let entry: AskTraceEntry

    public init(assistant: AskAssistant, entry: AskTraceEntry = .shortcut) {
        self.assistant = assistant
        self.entry = entry
    }
}

public enum AskIntentError: Error, CustomLocalizedStringResourceConvertible, Equatable {
    case emptyQuestion

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyQuestion:
            "Ask a question to continue."
        }
    }
}

/// One answer a host intent can place in `.result(dialog:snippetIntent:)`.
@MainActor
public struct AskIntentAnswer {
    public var turn: AskTurnResult
    /// The full spoken line, including sentences the card already shows.
    public var spoken: String
    /// The speech bubble. The snippet does not repeat it.
    public var dialog: IntentDialog
    /// The cards as a static snapshot. Buttons in this view do not run. Use ``snippet``.
    public var view: AnyView
    /// Interactive cards. A host returns `.result(dialog: dialog, snippetIntent: snippet)`.
    public var snippet: AskAnswerSnippetIntent
    /// Typed facts Shortcuts can pass to other App Intents.
    public var outputs: [AskOutput]
    /// The dialog string. The speech bubble when the chat would show one, otherwise the spoken line.
    let speech: String

    init(turn: AskTurnResult) {
        self.turn = turn
        let pages = AskIntentPresentation.pages(in: turn)
        let spoken = pages.map { $0.spoken.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let bubbles = pages.map { AskIntentPresentation.speech(for: $0) }.filter { !$0.isEmpty }
        self.spoken = spoken.joined(separator: "\n")
        let speech = bubbles.isEmpty ? self.spoken : bubbles.joined(separator: "\n")
        self.speech = speech
        if speech.isEmpty {
            self.dialog = "OK"
        } else {
            self.dialog = IntentDialog(stringLiteral: speech)
        }
        self.view = AnyView(AskIntentCards(cards: pages.compactMap { $0.card?.view }))
        self.snippet = AskAnswerSnippetIntent(turnID: turn.id)
        self.outputs = AskAnswerExport.outputs(from: turn)
    }
}

/// Reloads the cards for one saved answer. `AskIntent` returns this so the buttons on those cards run.
///
/// `perform()` only reads. A button calls its own intent, and the system runs this again to redraw.
public struct AskAnswerSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "Answer"
    public static let description = IntentDescription("Shows the cards for an answer.")
    public static let isDiscoverable = false

    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Turn")
    public var turnID: String

    @Dependency var client: AskIntentClient

    public init() {
        self.turnID = ""
    }

    public init(turnID: UUID) {
        self.turnID = turnID.uuidString
    }

    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        let id = UUID(uuidString: turnID)
        let prepared = await AskSnippetPreparation.make(turnID: id, client: client)
        return .result(view: prepared.view)
    }
}

enum AskIntentPresentation {
    static func pages(in turn: AskTurnResult) -> [AskPage] {
        if !turn.pages.isEmpty { return turn.pages }
        switch turn.fulfillment {
        case .reply(let reply):
            return [AskPage(text: reply.text, spoken: reply.spoken, skillID: turn.skillID, domainID: turn.domainID, slots: turn.slots, actions: reply.actions)]
        case .intent(let card):
            let bubble = AskCardTranscript.bubble(card.text, card: card) ?? ""
            return [AskPage(text: bubble, spoken: card.spoken, skillID: turn.skillID, domainID: turn.domainID, slots: turn.slots, card: card)]
        }
    }

    static func speech(for page: AskPage) -> String {
        let bubble = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bubble.isEmpty { return AskGuide.plainSpeech(bubble) }
        return AskGuide.plainSpeech(page.spoken)
    }
}

/// Asks one question and shows the answer.
///
/// Put `AskIntent()` in the app's `AppShortcutsProvider`, or call ``answer(_:using:)`` from an intent the app owns.
/// Another intent cannot `return` this `perform()`. Register an ``AskIntentClient`` in `App.init()`.
public struct AskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask"
    public static let description = IntentDescription("Asks a question and shows the answer.")

    /// The snippet does not need the chat on screen. The turn still runs in the app, next to that chat's assistant.
    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask?")
    public var question: String

    @Dependency var client: AskIntentClient

    public static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$question)")
    }

    public init() {}

    public init(question: String) {
        self.question = question
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<[AskOutput]> & ShowsSnippetIntent & ProvidesDialog {
        let asked = try await questionToRun()
        let answer = try await Self.answer(asked, using: client)
        return .result(value: answer.outputs, dialog: answer.dialog, snippetIntent: answer.snippet)
    }

    /// Runs one question through the registered client. ``perform()`` calls this.
    @MainActor
    public static func answer(_ question: String, using client: AskIntentClient) async throws -> AskIntentAnswer {
        try await answer(question, using: client.assistant, entry: client.entry)
    }

    /// Runs one question and records a trace. A host intent returns `.result(dialog: answer.dialog, snippetIntent: answer.snippet)`.
    @MainActor
    public static func answer(
        _ question: String,
        using assistant: AskAssistant,
        entry: AskTraceEntry = .shortcut
    ) async throws -> AskIntentAnswer {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AskIntentError.emptyQuestion }
        let turn = await assistant.handle(utterance: trimmed, entry: entry)
        return AskIntentAnswer(turn: turn)
    }

    private func questionToRun() async throws -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return try await $question.requestValue("What do you want to ask?")
    }
}

/// ``AskIntent`` lives in this package. The app's `AppIntentsPackage`
/// lists this type in `includedPackages` so Shortcuts and Siri can find it.
@available(iOS 17.0, macOS 14.0, *)
public struct AskKitAppIntents: AppIntentsPackage {}

/// Cards for the snippet. The speech stays in the dialog.
struct AskIntentCards: View {
    var cards: [AnyView]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                card
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

import Foundation

public enum AskConversationStep {
    /// Show the snippet and finish. Used after an intent card so that card stays on screen.
    case stop(AskTurnResult)
    /// Show the reply, then ask the prompt.
    case askAgain(AskTurnResult, prompt: String)
}

/// Stop or ask again after a turn. This is not an App Intent.
/// ``AskIntent`` returns one answer. A host that asks again calls ``AskIntent/answer(_:using:entry:)`` for the next question and returns that snippet.
public struct AskConversation {
    public var followUpPrompt: String

    public init(followUpPrompt: String = "What else can I help with?") {
        self.followUpPrompt = followUpPrompt
    }

    public func step(after result: AskTurnResult) -> AskConversationStep {
        switch result.fulfillment {
        case .intent:
            return .stop(result)
        case .reply:
            return .askAgain(result, prompt: followUpPrompt)
        }
    }
}

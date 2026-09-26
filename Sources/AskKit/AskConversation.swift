import Foundation

public enum AskConversationStep {
    /// Show the snippet and finish. Used after an intent card so that card stays on screen.
    case stop(AskTurnResult)
    /// Show the reply, then ask the prompt.
    case askAgain(AskTurnResult, prompt: String)
}

/// The "what else?" loop for an app's own Ask intent. This is not an App Intent.
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

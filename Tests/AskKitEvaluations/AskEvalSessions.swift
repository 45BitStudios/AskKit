import Foundation
import FoundationModels
@testable import AskKit

/// On-device sessions. The chat menu's saved model is not used, so a score is not a Private Cloud run.
enum AskEvalSessions {
    static var modelIsAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func route(_ request: AskModelRequest) async throws -> AskModelSkillChoice {
        let choice = try await respond(request, generating: AskSkillChoice.self)
        let slots = Dictionary(choice.slots.map { ($0.key, $0.value) }, uniquingKeysWith: { _, latest in latest })
        return AskModelSkillChoice(skillID: choice.skill, slots: slots, confidence: choice.confidence)
    }

    static func reply(_ request: AskModelRequest) async throws -> String {
        try await session(for: request).respond(to: request.prompt).content
    }

    static func followUp(_ request: AskModelRequest) async throws -> AskFollowUp {
        let draft = try await respond(request, generating: AskFollowUpDraft.self)
        return AskFollowUp(skillID: draft.skill, question: draft.question)
    }

    private static func respond<Value: Generable>(_ request: AskModelRequest, generating: Value.Type) async throws -> Value {
        try await session(for: request).respond(to: request.prompt, generating: Value.self).content
    }

    private static func session(for request: AskModelRequest) -> LanguageModelSession {
        LanguageModelSession(
            profile: AskRoutingProfile(
                instructions: request.instructions,
                model: SystemLanguageModel.default,
                cloud: nil
            )
        )
    }
}

enum AskEvalRun {
    /// Model evaluations stay out of the scripted suite.
    /// `xcodebuild` only forwards variables prefixed with `TEST_RUNNER_` into the simulator.
    static var isOn: Bool {
        let environment = ProcessInfo.processInfo.environment
        let enabled = environment["ASKKIT_EVALUATIONS"] == "1" || environment["TEST_RUNNER_ASKKIT_EVALUATIONS"] == "1"
        return enabled && AskEvalSessions.modelIsAvailable
    }
}

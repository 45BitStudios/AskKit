import Foundation

/// The current state of the person or the app for one turn.
///
/// `values` are for skill code. `promptBlock` is the only text sent to the model.
/// Leave a private value out of `promptBlock` when the skill needs it and the model does not.
public struct AskContext: Sendable, Equatable {
    public var values: [String: String]
    public var promptBlock: String

    public init(promptBlock: String = "", values: [String: String] = [:]) {
        self.promptBlock = promptBlock
        self.values = values
    }

    public func value(for key: String) -> String? {
        let trimmed = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Keeps `promptBlock` and the listed values. An empty key list returns this context unchanged.
    public func scoped(to keys: [String]) -> AskContext {
        guard !keys.isEmpty else { return self }
        let allowed = Set(keys)
        return AskContext(
            promptBlock: promptBlock,
            values: values.filter { allowed.contains($0.key) }
        )
    }
}

/// An app object that can answer "what is true right now?"
///
/// Override `context(forSkill:keys:)` when one skill needs a heavier snapshot
/// than the snapshot used to route the question.
public protocol AskContextSource: Sendable {
    func currentContext() async -> AskContext
    func context(forSkill id: String, keys: [String]) async -> AskContext
}

extension AskContextSource {
    public func context(forSkill id: String, keys: [String]) async -> AskContext {
        let current = await currentContext()
        return keys.isEmpty ? current : current.scoped(to: keys)
    }
}

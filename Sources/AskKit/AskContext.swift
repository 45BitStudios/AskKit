import Foundation

/// One labeled block in a reply or follow-up prompt, such as `TRIP` or `PANTRY`.
/// The title is the heading the model sees. The text is the body under it.
public struct AskPromptSection: Sendable, Equatable, Identifiable {
    public var title: String
    public var text: String

    public var id: String { title }

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

/// The current state of the person or the app for one turn.
///
/// `values` are for skill code. `promptBlock` is the CONTEXT block on a route.
/// `sections` are the named blocks on a reply and a follow-up, titled by the app.
/// Leave a private value out of both when the skill needs it and the model does not.
public struct AskContext: Sendable, Equatable {
    public var values: [String: String]
    public var promptBlock: String
    public var sections: [AskPromptSection]

    public init(promptBlock: String = "", values: [String: String] = [:], sections: [AskPromptSection] = []) {
        self.promptBlock = promptBlock
        self.values = values
        self.sections = sections
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
            values: values.filter { allowed.contains($0.key) },
            sections: sections
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

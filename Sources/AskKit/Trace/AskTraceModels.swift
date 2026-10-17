import Foundation

/// Where a turn started. The raw value is open so a host can pass `voice` or its own name.
public struct AskTraceEntry: RawRepresentable, Codable, Sendable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let composer = AskTraceEntry(rawValue: "composer")
    public static let chip = AskTraceEntry(rawValue: "chip")
    /// ``AskIntent``, unless the registered client or the caller passes another entry.
    public static let shortcut = AskTraceEntry(rawValue: "shortcut")
    public static let siri = AskTraceEntry(rawValue: "siri")
    /// Listen until a pause, then speak the answer. Not a Siri turn.
    public static let voice = AskTraceEntry(rawValue: "voice")
    /// Card toolkit. Facts in, a composed card out. Not a chat question.
    public static let toolkit = AskTraceEntry(rawValue: "toolkit")
}

/// What a span measures. `.model` spans carry a Foundation Models transcript.
public enum AskTraceSpanKind: String, Codable, Sendable, CaseIterable {
    case turn
    case function
    case model
    case tool
    /// Time spent waiting on the person. Not compute time.
    case userWait
}

#if DEBUG

/// One recorded turn: the root span plus every span opened beneath it, in start order.
/// Debug builds only. Prompts and tool output can carry private context.
public struct AskTraceTurn: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    package var question: String
    package var entry: AskTraceEntry
    package var startedAt: Date
    /// Seconds from start to end. Nil while the turn is still running.
    package var duration: TimeInterval?
    package var spans: [AskTraceSpan]
}

public struct AskTraceSpan: Codable, Sendable, Identifiable, Equatable {
    public enum Status: Codable, Sendable, Equatable {
        case ok
        case threw(String)
        /// The turn ended before this span did.
        case unfinished
    }

    public struct Attribute: Codable, Sendable, Equatable {
        package var key: String
        package var value: String
    }

    public let id: UUID
    package let parentID: UUID?
    package var name: String
    package var kind: AskTraceSpanKind
    package var function: String
    package var fileID: String
    package var line: Int
    /// Seconds since the turn started, on the turn's monotonic clock.
    package var start: TimeInterval
    package var end: TimeInterval?
    package var status: Status
    package var attributes: [Attribute]
    package var result: String?
    package var events: [AskTraceEvent]
    package var model: AskTraceModelCall?

    package var duration: TimeInterval? {
        end.map { $0 - start }
    }
}

public struct AskTraceEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case log
        case decision
    }

    package var offset: TimeInterval
    package var kind: Kind
    package var message: String
}

/// Foundation Models detail for one `respond` call, read from `session.transcript` after it returns or throws.
public struct AskTraceModelCall: Codable, Sendable, Equatable {
    package var label: String
    package var prewarmed: Bool?
    package var items: [AskTraceTranscriptItem]
    package var output: String?
    package var errorKind: String?
    package var errorDescription: String?
    package var context: AskTraceContextUsage?
}

/// Context-window use for one model call.
public struct AskTraceContextUsage: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// `Response.usage`: exact input, cached, output, and reasoning counts.
        case responseUsage
        /// The call overflowed. Counts come from `LanguageModelError.contextSizeExceeded`.
        case contextExceeded
    }

    package var source: Source
    package var contextSize: Int
    package var usedTokens: Int
    package var inputTokens: Int?
    package var cachedInputTokens: Int?
    package var outputTokens: Int?
    package var reasoningTokens: Int?

    package init(
        source: Source,
        contextSize: Int,
        usedTokens: Int,
        inputTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.source = source
        self.contextSize = contextSize
        self.usedTokens = usedTokens
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }

    package var fraction: Double {
        contextSize > 0 ? Double(usedTokens) / Double(contextSize) : 0
    }

    package var remainingTokens: Int {
        max(0, contextSize - usedTokens)
    }
}

public struct AskTraceTranscriptItem: Codable, Sendable, Equatable {
    package enum Kind: String, Codable, Sendable {
        case instructions
        case toolDefinitions
        case prompt
        case toolCall
        case toolOutput
        case response
        case reasoning
    }

    package var kind: Kind
    package var toolName: String?
    package var text: String
}

#endif

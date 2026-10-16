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
    var question: String
    var entry: AskTraceEntry
    var startedAt: Date
    /// Seconds from start to end. Nil while the turn is still running.
    var duration: TimeInterval?
    var spans: [AskTraceSpan]
}

public struct AskTraceSpan: Codable, Sendable, Identifiable, Equatable {
    public enum Status: Codable, Sendable, Equatable {
        case ok
        case threw(String)
        /// The turn ended before this span did.
        case unfinished
    }

    public struct Attribute: Codable, Sendable, Equatable {
        var key: String
        var value: String
    }

    public let id: UUID
    let parentID: UUID?
    var name: String
    var kind: AskTraceSpanKind
    var function: String
    var fileID: String
    var line: Int
    /// Seconds since the turn started, on the turn's monotonic clock.
    var start: TimeInterval
    var end: TimeInterval?
    var status: Status
    var attributes: [Attribute]
    var result: String?
    var events: [AskTraceEvent]
    var model: AskTraceModelCall?

    var duration: TimeInterval? {
        end.map { $0 - start }
    }
}

public struct AskTraceEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case log
        case decision
    }

    var offset: TimeInterval
    var kind: Kind
    var message: String
}

/// Foundation Models detail for one `respond` call, read from `session.transcript` after it returns or throws.
public struct AskTraceModelCall: Codable, Sendable, Equatable {
    var label: String
    var prewarmed: Bool?
    var items: [AskTraceTranscriptItem]
    var output: String?
    var errorKind: String?
    var errorDescription: String?
    var context: AskTraceContextUsage?
}

/// Context-window use for one model call.
public struct AskTraceContextUsage: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// `Response.usage`: exact input, cached, output, and reasoning counts.
        case responseUsage
        /// The call overflowed. Counts come from `LanguageModelError.contextSizeExceeded`.
        case contextExceeded
    }

    var source: Source
    var contextSize: Int
    var usedTokens: Int
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var outputTokens: Int?
    var reasoningTokens: Int?

    var fraction: Double {
        contextSize > 0 ? Double(usedTokens) / Double(contextSize) : 0
    }

    var remainingTokens: Int {
        max(0, contextSize - usedTokens)
    }
}

public struct AskTraceTranscriptItem: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case instructions
        case toolDefinitions
        case prompt
        case toolCall
        case toolOutput
        case response
        case reasoning
    }

    var kind: Kind
    var toolName: String?
    var text: String
}

#endif

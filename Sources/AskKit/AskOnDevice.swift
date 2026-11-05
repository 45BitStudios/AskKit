import Foundation
#if ASK_FOUNDATION_MODELS
import FoundationModels
#endif

/// Where an on-device answer came from.
public enum AskOnDeviceEngine: String, Sendable, Equatable {
    /// The persistent on-device `LanguageModelSession` produced the structured answer.
    case foundationModels
    /// The app's fallback ran.
    case fallback
}

/// Why this layer will not open an on-device session.
public enum AskOnDeviceUnavailability: String, Sendable, Equatable {
    /// Apple TV, Apple Watch, or a build compiled without Foundation Models.
    case unsupportedPlatform
    /// The operating system is older than 27.3.
    case operatingSystem
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// The caller set `allowModel` to false.
    case turnedOff
}

/// Whether the next question may open, or continue, an on-device session.
public enum AskOnDeviceAvailability: Sendable, Equatable {
    case available
    case unavailable(AskOnDeviceUnavailability)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

/// The on-device model's availability, detached from the system type so tests can supply it.
public enum AskOnDeviceModelReport: Sendable, Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
}

/// Why the fallback answered this turn.
public enum AskOnDeviceFallbackCause: Sendable, Equatable {
    /// The 27.3 session was out of bounds, or the caller turned the model off.
    case unavailable(AskOnDeviceUnavailability)
    /// The model refused the input. The fallback should not repeat the person's words.
    case blocked
    /// The session threw. The person's answer is the fallback text.
    case modelFailed
    /// The model returned a structured answer with an empty sentence.
    case emptyAnswer
    /// The instructions alone are larger than the 8,192-token on-device window.
    case instructionsTooLong
    /// Another turn is already using this responder's session.
    case busy
}

/// The structured answer a person reads.
///
/// The built-in model schema has the same three fields. An app that needs a different shape
/// passes its own `@Generable` type to `answer(_:generating:fallback:)`.
public struct AskOnDeviceAnswer: Sendable, Equatable {
    public var text: String
    /// Identifiers the tools returned, after the app's `acceptCitation` filter.
    public var citedIDs: [String]
    public var reason: String

    public init(text: String, citedIDs: [String] = [], reason: String = "") {
        self.text = text
        self.citedIDs = citedIDs
        self.reason = reason
    }
}

/// One turn from ``AskOnDeviceResponder``.
public struct AskOnDeviceTurn<Answer: Sendable>: Sendable {
    public var answer: Answer
    public var engine: AskOnDeviceEngine
    /// True when this prompt was sent to the session an earlier turn opened.
    public var continuedSession: Bool

    public init(answer: Answer, engine: AskOnDeviceEngine, continuedSession: Bool) {
        self.answer = answer
        self.engine = engine
        self.continuedSession = continuedSession
    }
}

extension AskOnDeviceTurn: Equatable where Answer: Equatable {}

/// The 27.3 line for a persistent on-device answer session.
///
/// Foundation Models exists on earlier 27 releases. This layer opens a session on iOS 27.3,
/// macOS 27.3, Mac Catalyst 27.3, and visionOS 27.3, and only when the system model reports
/// itself available. Every other case uses the app's fallback.
public enum AskOnDeviceBoundary {
    public static let major = 27
    public static let minor = 3

    /// On-device context window this layer plans for, in tokens.
    /// 27.3 raised it from 4,096 to 8,192 on most devices. Read the live `contextSize` when a session is open;
    /// this constant is the budget an app can check before it sends a prompt.
    public static let onDeviceTokenWindow = 8_192

    /// The on-device window from before that increase. Instructions that fit here also fit on 27.3.
    public static let legacyOnDeviceTokenWindow = 4_096

    /// Share of ``onDeviceTokenWindow`` that instructions should stay under so tool results still fit.
    public static let comfortableInstructionFraction = 0.25

    /// 27.3.0 is in bounds. 27.2 is not. A later major or minor version is in bounds.
    public static func allows(major: Int, minor: Int, patch: Int = 0) -> Bool {
        _ = patch
        if major > Self.major { return true }
        if major < Self.major { return false }
        return minor >= Self.minor
    }

    public static func allows(_ version: OperatingSystemVersion) -> Bool {
        allows(major: version.majorVersion, minor: version.minorVersion, patch: version.patchVersion)
    }

    public static func estimatedTokens(in text: String) -> Int {
        AskReplyBudget.estimatedTokens(for: text)
    }

    /// True when the instructions fit in the whole on-device window.
    /// The responder uses the fallback when this is false. Data belongs in tools, not in this string.
    public static func instructionsFit(_ text: String, window: Int = onDeviceTokenWindow) -> Bool {
        estimatedTokens(in: text) <= max(window, 0)
    }

    /// True when the instructions use at most a quarter of the window.
    public static func instructionsFitComfortably(_ text: String, window: Int = onDeviceTokenWindow) -> Bool {
        let budget = Int((Double(max(window, 0)) * comfortableInstructionFraction).rounded(.down))
        return estimatedTokens(in: text) <= budget
    }

    public static func availability(
        allowModel: Bool,
        platformSupportsFoundationModels: Bool,
        operatingSystemAllows: Bool,
        model: AskOnDeviceModelReport
    ) -> AskOnDeviceAvailability {
        guard allowModel else { return .unavailable(.turnedOff) }
        guard platformSupportsFoundationModels else { return .unavailable(.unsupportedPlatform) }
        guard operatingSystemAllows else { return .unavailable(.operatingSystem) }
        switch model {
        case .available:
            return .available
        case .deviceNotEligible:
            return .unavailable(.deviceNotEligible)
        case .appleIntelligenceNotEnabled:
            return .unavailable(.appleIntelligenceNotEnabled)
        case .modelNotReady:
            return .unavailable(.modelNotReady)
        }
    }

    static var platformSupportsFoundationModels: Bool {
        #if ASK_FOUNDATION_MODELS
        true
        #else
        false
        #endif
    }

    /// Compiler availability and the numeric 27.3 boundary. Both have to pass.
    static func liveOperatingSystemAllows() -> Bool {
        #if ASK_FOUNDATION_MODELS
        guard #available(iOS 27.3, macOS 27.3, macCatalyst 27.3, visionOS 27.3, *) else {
            return false
        }
        return allows(ProcessInfo.processInfo.operatingSystemVersion)
        #else
        return false
        #endif
    }

    static func liveModelReport() -> AskOnDeviceModelReport {
        #if ASK_FOUNDATION_MODELS
        report(SystemLanguageModel.default.availability)
        #else
        .modelNotReady
        #endif
    }

    #if ASK_FOUNDATION_MODELS
    static func report(_ availability: SystemLanguageModel.Availability) -> AskOnDeviceModelReport {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .modelNotReady
            }
        }
    }
    #endif
}

struct AskOnDeviceEnvironment: Sendable {
    var platformSupportsFoundationModels: Bool
    var operatingSystemAllows: @Sendable () -> Bool
    var model: @Sendable () -> AskOnDeviceModelReport

    static var live: AskOnDeviceEnvironment {
        AskOnDeviceEnvironment(
            platformSupportsFoundationModels: AskOnDeviceBoundary.platformSupportsFoundationModels,
            operatingSystemAllows: { AskOnDeviceBoundary.liveOperatingSystemAllows() },
            model: { AskOnDeviceBoundary.liveModelReport() }
        )
    }

    static func fixed(
        platformSupportsFoundationModels: Bool = true,
        operatingSystemAllows: Bool = true,
        model: AskOnDeviceModelReport = .available
    ) -> AskOnDeviceEnvironment {
        AskOnDeviceEnvironment(
            platformSupportsFoundationModels: platformSupportsFoundationModels,
            operatingSystemAllows: { operatingSystemAllows },
            model: { model }
        )
    }
}

#if ASK_FOUNDATION_MODELS
/// The model's copy of ``AskOnDeviceAnswer``. Cited ids are filtered after generation.
@Generable
struct AskOnDeviceAnswerDraft: Sendable {
    @Guide(description: "The answer, one to three sentences, using only facts the tools returned.")
    var text: String
    @Guide(description: "Identifiers the tools returned for the items this answer mentions. Empty when none.")
    var citedIDs: [String]
    @Guide(description: "Why these items answer the question, in a few words.")
    var reason: String
}

@MainActor
protocol AskOnDeviceGenerating: AnyObject {
    func respond<Answer: Generable & Sendable>(
        to prompt: String,
        generating type: Answer.Type
    ) async throws -> Answer
}

struct AskOnDeviceSessions {
    var make: @MainActor (_ instructions: String, _ tools: [any AskTool]) -> any AskOnDeviceGenerating

    static var live: AskOnDeviceSessions {
        AskOnDeviceSessions { instructions, tools in
            AskOnDeviceLiveSession(instructions: instructions, tools: tools)
        }
    }
}

@MainActor
final class AskOnDeviceLiveSession: AskOnDeviceGenerating {
    private let session: LanguageModelSession

    init(instructions: String, tools: [any AskTool]) {
        session = LanguageModelSession(
            profile: AskOnDeviceProfile(instructions: instructions, tools: tools)
        )
    }

    func respond<Answer: Generable & Sendable>(
        to prompt: String,
        generating type: Answer.Type
    ) async throws -> Answer {
        try await session.respond(to: prompt, generating: type).content
    }
}

struct AskOnDeviceProfile: LanguageModelSession.DynamicProfile {
    var instructions: String
    var tools: [any AskTool]

    /// A failed turn rolls the transcript back, so the next question still sees the earlier ones.
    var body: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instructions)
            tools
        }
        .model(SystemLanguageModel.default)
        .toolCallingMode(.allowed)
        .transcriptErrorHandlingPolicy(.revertTranscript)
    }
}
#else
struct AskOnDeviceSessions {
    static var live: AskOnDeviceSessions { AskOnDeviceSessions() }
}
#endif

/// A persistent on-device answer session for an app that supplies its own tools and prompts.
///
/// One responder keeps one `LanguageModelSession`. A follow-up is another turn in that transcript.
/// `reset()` drops the session. Instructions and tools are read when the session opens, so call
/// `reset()` when the instructions should change. A tool reads the app's data at call time.
///
/// Facts stay in the tools. The instructions are the prompt. ``AskOnDeviceBoundary/onDeviceTokenWindow``
/// is 8,192 tokens, the 27.3 on-device window on most devices.
///
/// The session opens when `allowModel` is true, the platform has Foundation Models, the OS is 27.3
/// or later, and the system model is available. Otherwise `fallback` answers. A thrown model error,
/// an empty sentence, or instructions that do not fit the window do the same.
@MainActor
public final class AskOnDeviceResponder {
    private let allowModel: Bool
    private let instructions: @MainActor () -> String
    private let tools: @MainActor () -> [any AskTool]
    private let acceptCitation: @Sendable (String) -> Bool
    private let fallback: @MainActor (String, AskOnDeviceFallbackCause) -> AskOnDeviceAnswer
    private let environment: AskOnDeviceEnvironment
    private let sessions: AskOnDeviceSessions
    private var responding = false
    #if ASK_FOUNDATION_MODELS
    private var session: (any AskOnDeviceGenerating)?
    #endif

    /// `instructions` and `tools` run on the turn that opens the session.
    /// `acceptCitation` drops identifiers the app does not have. It runs on the built-in schema only.
    /// `fallback` answers when the model does not.
    public init(
        allowModel: Bool = true,
        instructions: @escaping @MainActor () -> String,
        tools: @escaping @MainActor () -> [any AskTool] = { [] },
        acceptCitation: @escaping @Sendable (String) -> Bool = { _ in true },
        fallback: @escaping @MainActor (_ utterance: String, _ cause: AskOnDeviceFallbackCause) -> AskOnDeviceAnswer
    ) {
        self.init(
            allowModel: allowModel,
            instructions: instructions,
            tools: tools,
            acceptCitation: acceptCitation,
            fallback: fallback,
            environment: .live,
            sessions: .live
        )
    }

    init(
        allowModel: Bool = true,
        instructions: @escaping @MainActor () -> String,
        tools: @escaping @MainActor () -> [any AskTool] = { [] },
        acceptCitation: @escaping @Sendable (String) -> Bool = { _ in true },
        fallback: @escaping @MainActor (String, AskOnDeviceFallbackCause) -> AskOnDeviceAnswer,
        environment: AskOnDeviceEnvironment,
        sessions: AskOnDeviceSessions
    ) {
        self.allowModel = allowModel
        self.instructions = instructions
        self.tools = tools
        self.acceptCitation = acceptCitation
        self.fallback = fallback
        self.environment = environment
        self.sessions = sessions
    }

    public var availability: AskOnDeviceAvailability {
        AskOnDeviceBoundary.availability(
            allowModel: allowModel,
            platformSupportsFoundationModels: environment.platformSupportsFoundationModels,
            operatingSystemAllows: environment.operatingSystemAllows(),
            model: environment.model()
        )
    }

    public var modelIsAvailable: Bool { availability.isAvailable }

    /// Drops the session. The next question that reaches the model opens a new one,
    /// with whatever `instructions` and `tools` return then.
    public func reset() {
        #if ASK_FOUNDATION_MODELS
        session = nil
        #endif
    }

    /// Answers with the built-in schema: a sentence, cited identifiers, and a short reason.
    public func answer(_ utterance: String) async -> AskOnDeviceTurn<AskOnDeviceAnswer> {
        await AskTrace.span("onDevice") {
            if let turn = await exclusive({ await self.answerBuiltIn(utterance) }) {
                return turn
            }
            return self.finish(
                self.fallback(utterance, .busy),
                engine: .fallback,
                continuedSession: false,
                cause: .busy
            )
        }
    }

    #if ASK_FOUNDATION_MODELS
    /// Answers with the app's `@Generable` type. Use one answer type for the life of the responder.
    /// The built-in citation filter does not run on this type. The app checks identifiers itself.
    public func answer<Answer: Generable & Sendable>(
        _ utterance: String,
        generating type: Answer.Type,
        fallback: @escaping @MainActor (_ utterance: String, _ cause: AskOnDeviceFallbackCause) -> Answer
    ) async -> AskOnDeviceTurn<Answer> {
        await AskTrace.span("onDevice") {
            if let turn = await exclusive({ await self.answerGenerated(utterance, generating: type, fallback: fallback) }) {
                return turn
            }
            return self.finish(
                fallback(utterance, .busy),
                engine: .fallback,
                continuedSession: false,
                cause: .busy
            )
        }
    }
    #endif

    private func exclusive<T: Sendable>(_ body: () async -> T) async -> T? {
        if responding { return nil }
        responding = true
        defer { responding = false }
        return await body()
    }

    private func answerBuiltIn(_ utterance: String) async -> AskOnDeviceTurn<AskOnDeviceAnswer> {
        #if ASK_FOUNDATION_MODELS
        switch openSession() {
        case .failure(let cause):
            return finish(fallback(utterance, cause), engine: .fallback, continuedSession: false, cause: cause)
        case .success(let opened):
            do {
                let draft = try await opened.session.respond(to: utterance, generating: AskOnDeviceAnswerDraft.self)
                let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    return finish(
                        fallback(utterance, .emptyAnswer),
                        engine: .fallback,
                        continuedSession: opened.continuedSession,
                        cause: .emptyAnswer
                    )
                }
                let answer = AskOnDeviceAnswer(
                    text: text,
                    citedIDs: draft.citedIDs.compactMap { raw in
                        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !id.isEmpty, acceptCitation(id) else { return nil }
                        return id
                    },
                    reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                return finish(answer, engine: .foundationModels, continuedSession: opened.continuedSession, cause: nil)
            } catch {
                let cause: AskOnDeviceFallbackCause = AskModelSafety.isBlocked(error) ? .blocked : .modelFailed
                return finish(
                    fallback(utterance, cause),
                    engine: .fallback,
                    continuedSession: opened.continuedSession,
                    cause: cause
                )
            }
        }
        #else
        // The session factory is unused where Foundation Models is not compiled in.
        _ = sessions
        let cause = unavailableCause(availability)
        return finish(fallback(utterance, cause), engine: .fallback, continuedSession: false, cause: cause)
        #endif
    }

    #if ASK_FOUNDATION_MODELS
    private func answerGenerated<Answer: Generable & Sendable>(
        _ utterance: String,
        generating type: Answer.Type,
        fallback: @escaping @MainActor (String, AskOnDeviceFallbackCause) -> Answer
    ) async -> AskOnDeviceTurn<Answer> {
        switch openSession() {
        case .failure(let cause):
            return finish(fallback(utterance, cause), engine: .fallback, continuedSession: false, cause: cause)
        case .success(let opened):
            do {
                let answer = try await opened.session.respond(to: utterance, generating: type)
                return finish(answer, engine: .foundationModels, continuedSession: opened.continuedSession, cause: nil)
            } catch {
                let cause: AskOnDeviceFallbackCause = AskModelSafety.isBlocked(error) ? .blocked : .modelFailed
                return finish(
                    fallback(utterance, cause),
                    engine: .fallback,
                    continuedSession: opened.continuedSession,
                    cause: cause
                )
            }
        }
    }

    private struct OpenedSession {
        var session: any AskOnDeviceGenerating
        var continuedSession: Bool
    }

    private func openSession() -> Result<OpenedSession, AskOnDeviceFallbackCause> {
        let availability = self.availability
        guard availability.isAvailable else {
            return .failure(unavailableCause(availability))
        }
        if let session {
            return .success(OpenedSession(session: session, continuedSession: true))
        }
        let text = instructions()
        guard AskOnDeviceBoundary.instructionsFit(text) else {
            return .failure(.instructionsTooLong)
        }
        let toolList = tools()
        AskTrace.attribute("tools", toolList.map(\.name).joined(separator: ", "))
        let made = sessions.make(text, toolList)
        session = made
        return .success(OpenedSession(session: made, continuedSession: false))
    }
    #endif

    private func unavailableCause(_ availability: AskOnDeviceAvailability) -> AskOnDeviceFallbackCause {
        switch availability {
        case .available:
            return .unavailable(.unsupportedPlatform)
        case .unavailable(let reason):
            return .unavailable(reason)
        }
    }

    private func finish<Answer: Sendable>(
        _ answer: Answer,
        engine: AskOnDeviceEngine,
        continuedSession: Bool,
        cause: AskOnDeviceFallbackCause?
    ) -> AskOnDeviceTurn<Answer> {
        AskTrace.attribute("availability", Self.availabilityLabel(availability))
        AskTrace.attribute("engine", engine.rawValue)
        AskTrace.attribute("continued", continuedSession ? "true" : "false")
        if let cause {
            AskTrace.attribute("cause", Self.causeLabel(cause))
            AskTrace.decision("fallback")
        } else {
            AskTrace.decision("foundationModels")
        }
        return AskOnDeviceTurn(answer: answer, engine: engine, continuedSession: continuedSession)
    }

    private static func availabilityLabel(_ availability: AskOnDeviceAvailability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(let reason):
            return reason.rawValue
        }
    }

    private static func causeLabel(_ cause: AskOnDeviceFallbackCause) -> String {
        switch cause {
        case .unavailable(let reason):
            return reason.rawValue
        case .blocked:
            return "blocked"
        case .modelFailed:
            return "modelFailed"
        case .emptyAnswer:
            return "emptyAnswer"
        case .instructionsTooLong:
            return "instructionsTooLong"
        case .busy:
            return "busy"
        }
    }
}

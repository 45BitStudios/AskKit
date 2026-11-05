import Foundation
#if ASK_FOUNDATION_MODELS || os(watchOS)
import FoundationModels
#endif

/// Where an answer came from.
public enum AskOnDeviceEngine: String, Sendable, Equatable {
    /// The persistent `LanguageModelSession` produced the structured answer.
    case foundationModels
    /// The app's fallback ran.
    case fallback
}

/// Which model a responder keeps for the life of its session.
///
/// `.onDevice` is the default. `.privateCloud` uses `PrivateCloudComputeLanguageModel`.
/// Apple Watch has no on-device model and does not borrow the paired iPhone's. A watch app passes `.privateCloud`.
public enum AskAnswerModel: String, Sendable, Equatable, CaseIterable {
    case onDevice
    case privateCloud
}

/// The managed entitlement a host app adds before Private Cloud Compute will answer.
///
/// Apple's page for this key lists iOS, iPadOS, macOS, visionOS, and watchOS 27.0 and later.
/// It does not list tvOS. Adding the key does not grant access. Apple assigns the managed entitlement
/// to the developer account. See Accessing Private Cloud Compute.
public enum AskPrivateCloudEntitlement {
    public static let key = "com.apple.developer.private-cloud-compute"
}

/// Why this layer will not open a session.
public enum AskOnDeviceUnavailability: String, Sendable, Equatable {
    /// This build has neither the on-device model nor Private Cloud Compute.
    case unsupportedPlatform
    /// The operating system is older than 27.3.
    case operatingSystem
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// Private Cloud Compute is installed but not ready.
    case systemNotReady
    /// The caller set `allowModel` to false.
    case turnedOff
    /// The chosen model is the on-device system model, and this platform has none. Apple Watch is this case.
    case onDeviceUnavailable
    /// Private Cloud Compute is not part of this build. Apple's docs omit tvOS.
    case privateCloudUnavailable
    /// `quotaUsage.isLimitReached` is true, or the model threw `quotaLimitReached`.
    case quotaReached
    /// Private Cloud Compute needs a network path.
    case offline
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

/// Private Cloud Compute availability, detached from the system type so tests can supply it.
public enum AskPrivateCloudReport: Sendable, Equatable {
    case available
    case deviceNotEligible
    case systemNotReady
}

/// Why the fallback answered this turn.
public enum AskOnDeviceFallbackCause: Error, Sendable, Equatable {
    /// The 27.3 session was out of bounds, or the caller turned the model off.
    case unavailable(AskOnDeviceUnavailability)
    /// The model refused the input. The fallback should not repeat the person's words.
    case blocked
    /// The session threw. The person's answer is the fallback text.
    case modelFailed
    /// The model returned a structured answer with an empty sentence.
    case emptyAnswer
    /// The instructions alone are larger than the model's context window.
    case instructionsTooLong
    /// Another turn is already using this responder's session.
    case busy
    /// The person's Private Cloud Compute quota is used up.
    case quotaReached
    /// Private Cloud Compute needs a network path.
    case offline
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

/// The 27.3 line for a persistent answer session.
///
/// Foundation Models exists on earlier 27 releases. This layer opens a session on iOS 27.3,
/// macOS 27.3, Mac Catalyst 27.3, visionOS 27.3, and watchOS 27.3. The watch session is
/// Private Cloud Compute. Apple's Private Cloud Compute pages do not list tvOS, so Apple TV
/// stays on the fallback. Every other miss uses the app's fallback.
public enum AskOnDeviceBoundary {
    public static let major = 27
    public static let minor = 3

    /// Usual on-device window, in tokens, used only when `contextSize` cannot be read.
    /// A 27.3 device may report 8,192. Apple's Private Cloud Compute article still lists the on-device model at 4K.
    /// The responder uses the value the model reports.
    public static let onDeviceTokenWindow = 8_192

    /// Usual Private Cloud Compute window, in tokens, used only when `contextSize` throws or returns nothing.
    /// Apple documents this model at 32K. The responder uses the value the model reports.
    public static let privateCloudTokenWindow = 32_768

    /// The on-device window from before the later increase. Instructions that fit here also fit in a larger window.
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

    /// The window a session should budget against. A positive `contextSize` wins. Zero or a failed read uses the usual size for that model.
    public static func resolvedContextSize(reported: Int?, choice: AskAnswerModel) -> Int {
        if let reported, reported > 0 { return reported }
        switch choice {
        case .onDevice: return onDeviceTokenWindow
        case .privateCloud: return privateCloudTokenWindow
        }
    }

    /// True when the instructions fit in `window`.
    /// The responder passes the model's `contextSize`. Data belongs in tools, not in this string.
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
        choice: AskAnswerModel = .onDevice,
        onDeviceSupported: Bool,
        privateCloudSupported: Bool = true,
        operatingSystemAllows: Bool,
        onDevice: AskOnDeviceModelReport = .available,
        privateCloud: AskPrivateCloudReport = .available,
        quotaLimitReached: Bool = false,
        online: Bool = true
    ) -> AskOnDeviceAvailability {
        guard allowModel else { return .unavailable(.turnedOff) }
        switch choice {
        case .onDevice:
            guard onDeviceSupported else { return .unavailable(.onDeviceUnavailable) }
        case .privateCloud:
            guard privateCloudSupported else { return .unavailable(.privateCloudUnavailable) }
        }
        guard operatingSystemAllows else { return .unavailable(.operatingSystem) }
        switch choice {
        case .onDevice:
            switch onDevice {
            case .available:
                return .available
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            }
        case .privateCloud:
            guard online else { return .unavailable(.offline) }
            guard !quotaLimitReached else { return .unavailable(.quotaReached) }
            switch privateCloud {
            case .available:
                return .available
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .systemNotReady:
                return .unavailable(.systemNotReady)
            }
        }
    }

    /// The on-device system model is compiled in. Apple Watch and Apple TV are not in this set.
    /// `SystemLanguageModel` lists tvOS 27.3 as beta and does not list watchOS. This package still
    /// leaves the on-device session off tvOS, with the rest of the receptionist.
    static var onDeviceSupported: Bool {
        #if ASK_FOUNDATION_MODELS
        true
        #else
        false
        #endif
    }

    /// Private Cloud Compute is compiled in. Apple's type lists watchOS and omits tvOS.
    static var privateCloudSupported: Bool {
        #if ASK_FOUNDATION_MODELS || os(watchOS)
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
        #elseif os(watchOS)
        guard #available(watchOS 27.3, *) else {
            return false
        }
        return allows(ProcessInfo.processInfo.operatingSystemVersion)
        #else
        return false
        #endif
    }

    static func liveOnDeviceReport() -> AskOnDeviceModelReport {
        #if ASK_FOUNDATION_MODELS
        report(SystemLanguageModel.default.availability)
        #else
        .modelNotReady
        #endif
    }

    static func livePrivateCloudReport() -> AskPrivateCloudReport {
        #if ASK_FOUNDATION_MODELS || os(watchOS)
        report(PrivateCloudComputeLanguageModel().availability)
        #else
        .systemNotReady
        #endif
    }

    static func liveQuotaLimitReached() -> Bool {
        #if ASK_FOUNDATION_MODELS || os(watchOS)
        PrivateCloudComputeLanguageModel().quotaUsage.isLimitReached
        #else
        false
        #endif
    }

    static func liveContextSize(_ choice: AskAnswerModel) async -> Int {
        switch choice {
        case .onDevice:
            #if ASK_FOUNDATION_MODELS
            return resolvedContextSize(reported: SystemLanguageModel.default.contextSize, choice: .onDevice)
            #else
            return onDeviceTokenWindow
            #endif
        case .privateCloud:
            #if ASK_FOUNDATION_MODELS || os(watchOS)
            let reported = try? await PrivateCloudComputeLanguageModel().contextSize
            return resolvedContextSize(reported: reported, choice: .privateCloud)
            #else
            return privateCloudTokenWindow
            #endif
        }
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

    #if ASK_FOUNDATION_MODELS || os(watchOS)
    static func report(_ availability: PrivateCloudComputeLanguageModel.Availability) -> AskPrivateCloudReport {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .systemNotReady:
                return .systemNotReady
            @unknown default:
                return .systemNotReady
            }
        }
    }
    #endif
}

struct AskOnDeviceEnvironment: Sendable {
    var onDeviceSupported: Bool
    var privateCloudSupported: Bool
    var operatingSystemAllows: @Sendable () -> Bool
    var onDevice: @Sendable () -> AskOnDeviceModelReport
    var privateCloud: @Sendable () -> AskPrivateCloudReport
    var quotaLimitReached: @Sendable () -> Bool
    var online: @Sendable () -> Bool
    var contextSize: @Sendable () async -> Int

    static func live(choice: AskAnswerModel) -> AskOnDeviceEnvironment {
        AskOnDeviceEnvironment(
            onDeviceSupported: AskOnDeviceBoundary.onDeviceSupported,
            privateCloudSupported: AskOnDeviceBoundary.privateCloudSupported,
            operatingSystemAllows: { AskOnDeviceBoundary.liveOperatingSystemAllows() },
            onDevice: { AskOnDeviceBoundary.liveOnDeviceReport() },
            privateCloud: { AskOnDeviceBoundary.livePrivateCloudReport() },
            quotaLimitReached: { AskOnDeviceBoundary.liveQuotaLimitReached() },
            online: { AskNetwork.isOnline },
            contextSize: { await AskOnDeviceBoundary.liveContextSize(choice) }
        )
    }

    static func fixed(
        onDeviceSupported: Bool = true,
        privateCloudSupported: Bool = true,
        operatingSystemAllows: Bool = true,
        onDevice: AskOnDeviceModelReport = .available,
        privateCloud: AskPrivateCloudReport = .available,
        quotaLimitReached: Bool = false,
        online: Bool = true,
        contextSize: Int = AskOnDeviceBoundary.onDeviceTokenWindow
    ) -> AskOnDeviceEnvironment {
        AskOnDeviceEnvironment(
            onDeviceSupported: onDeviceSupported,
            privateCloudSupported: privateCloudSupported,
            operatingSystemAllows: { operatingSystemAllows },
            onDevice: { onDevice },
            privateCloud: { privateCloud },
            quotaLimitReached: { quotaLimitReached },
            online: { online },
            contextSize: { contextSize }
        )
    }
}

#if os(watchOS)
/// Apple Watch tools are Foundation Models tools. The receptionist still uses the name-only `AskTool` stub.
public typealias AskAnswerTool = Tool
#else
public typealias AskAnswerTool = AskTool
#endif

#if ASK_FOUNDATION_MODELS || os(watchOS)
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
    var make: @MainActor (_ instructions: String, _ tools: [any AskAnswerTool], _ model: AskAnswerModel) -> any AskOnDeviceGenerating

    static var live: AskOnDeviceSessions {
        AskOnDeviceSessions { instructions, tools, model in
            AskOnDeviceLiveSession(instructions: instructions, tools: tools, model: model)
        }
    }
}

@MainActor
final class AskOnDeviceLiveSession: AskOnDeviceGenerating {
    private let session: LanguageModelSession

    init(instructions: String, tools: [any AskAnswerTool], model: AskAnswerModel) {
        session = LanguageModelSession(
            profile: AskOnDeviceProfile(
                instructions: instructions,
                tools: tools,
                model: Self.languageModel(for: model)
            )
        )
    }

    private static func languageModel(for choice: AskAnswerModel) -> any LanguageModel {
        switch choice {
        case .privateCloud:
            return PrivateCloudComputeLanguageModel()
        case .onDevice:
            #if ASK_FOUNDATION_MODELS
            return SystemLanguageModel.default
            #else
            // Apple Watch has no on-device model. Availability rejects this choice before a session opens.
            preconditionFailure("Apple Watch has no on-device Foundation Model.")
            #endif
        }
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
    var tools: [any AskAnswerTool]
    var model: any LanguageModel

    /// A failed turn rolls the transcript back, so the next question still sees the earlier ones.
    var body: some LanguageModelSession.DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instructions)
            tools
        }
        .model(model)
        .toolCallingMode(.allowed)
        .transcriptErrorHandlingPolicy(.revertTranscript)
    }
}
#else
struct AskOnDeviceSessions {
    static var live: AskOnDeviceSessions { AskOnDeviceSessions() }
}
#endif

/// A persistent answer session for an app that supplies its own tools and prompts.
///
/// One responder keeps one `LanguageModelSession`. A follow-up is another turn in that transcript.
/// `reset()` drops the session. Instructions and tools are read when the session opens, so call
/// `reset()` when the instructions should change. A tool reads the app's data at call time.
///
/// `model` chooses the on-device system model or `PrivateCloudComputeLanguageModel`. The default is
/// on-device. Apple Watch passes `.privateCloud`. The watch has no on-device model and does not use
/// the paired iPhone's. Apple TV stays on the fallback: Private Cloud Compute's type and entitlement
/// omit tvOS.
///
/// Facts stay in the tools. The instructions are the prompt. The fit check reads the model's
/// `contextSize`. ``AskOnDeviceBoundary/onDeviceTokenWindow`` and ``AskOnDeviceBoundary/privateCloudTokenWindow``
/// are the usual sizes when that read fails.
///
/// The session opens when `allowModel` is true, the OS is 27.3 or later, the chosen model is
/// supported here, and that model reports itself available. Private Cloud Compute also needs a
/// network path, the managed entitlement, and `quotaUsage.isLimitReached == false`. Otherwise
/// `fallback` answers. A thrown model error, an empty sentence, or instructions that do not fit
/// the reported window do the same.
@MainActor
public final class AskOnDeviceResponder {
    private let model: AskAnswerModel
    private let allowModel: Bool
    private let instructions: @MainActor () -> String
    private let tools: @MainActor () -> [any AskAnswerTool]
    private let acceptCitation: @Sendable (String) -> Bool
    private let fallback: @MainActor (String, AskOnDeviceFallbackCause) -> AskOnDeviceAnswer
    private let environment: AskOnDeviceEnvironment
    private let sessions: AskOnDeviceSessions
    private var responding = false
    #if ASK_FOUNDATION_MODELS || os(watchOS)
    private var session: (any AskOnDeviceGenerating)?
    #endif

    /// `instructions` and `tools` run on the turn that opens the session.
    /// `acceptCitation` drops identifiers the app does not have. It runs on the built-in schema only.
    /// `fallback` answers when the model does not.
    /// `model` is fixed for the life of the responder. `.onDevice` is the default.
    /// On Apple Watch, pass `.privateCloud`.
    public convenience init(
        model: AskAnswerModel = .onDevice,
        allowModel: Bool = true,
        instructions: @escaping @MainActor () -> String,
        tools: @escaping @MainActor () -> [any AskAnswerTool] = { [] },
        acceptCitation: @escaping @Sendable (String) -> Bool = { _ in true },
        fallback: @escaping @MainActor (_ utterance: String, _ cause: AskOnDeviceFallbackCause) -> AskOnDeviceAnswer
    ) {
        self.init(
            model: model,
            allowModel: allowModel,
            instructions: instructions,
            tools: tools,
            acceptCitation: acceptCitation,
            fallback: fallback,
            environment: .live(choice: model),
            sessions: .live
        )
    }

    init(
        model: AskAnswerModel = .onDevice,
        allowModel: Bool = true,
        instructions: @escaping @MainActor () -> String,
        tools: @escaping @MainActor () -> [any AskAnswerTool] = { [] },
        acceptCitation: @escaping @Sendable (String) -> Bool = { _ in true },
        fallback: @escaping @MainActor (String, AskOnDeviceFallbackCause) -> AskOnDeviceAnswer,
        environment: AskOnDeviceEnvironment,
        sessions: AskOnDeviceSessions
    ) {
        self.model = model
        self.allowModel = allowModel
        self.instructions = instructions
        self.tools = tools
        self.acceptCitation = acceptCitation
        self.fallback = fallback
        self.environment = environment
        self.sessions = sessions
    }

    public var modelChoice: AskAnswerModel { model }

    public var availability: AskOnDeviceAvailability {
        AskOnDeviceBoundary.availability(
            allowModel: allowModel,
            choice: model,
            onDeviceSupported: environment.onDeviceSupported,
            privateCloudSupported: environment.privateCloudSupported,
            operatingSystemAllows: environment.operatingSystemAllows(),
            onDevice: environment.onDevice(),
            privateCloud: environment.privateCloud(),
            quotaLimitReached: environment.quotaLimitReached(),
            online: environment.online()
        )
    }

    public var modelIsAvailable: Bool { availability.isAvailable }

    /// Drops the session. The next question that reaches the model opens a new one,
    /// with whatever `instructions` and `tools` return then.
    public func reset() {
        #if ASK_FOUNDATION_MODELS || os(watchOS)
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

    #if ASK_FOUNDATION_MODELS || os(watchOS)
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
        #if ASK_FOUNDATION_MODELS || os(watchOS)
        switch await openSession() {
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
                    citedIDs: draft.citedIDs.compactMap { raw -> String? in
                        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !id.isEmpty, acceptCitation(id) else { return nil }
                        return id
                    },
                    reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                return finish(answer, engine: .foundationModels, continuedSession: opened.continuedSession, cause: nil)
            } catch {
                let cause = Self.failureCause(error)
                return finish(
                    fallback(utterance, cause),
                    engine: .fallback,
                    continuedSession: opened.continuedSession,
                    cause: cause
                )
            }
        }
        #else
        // Apple TV, and any build without Foundation Models, never opens a session.
        _ = sessions
        let cause = failureCause(for: availability)
        return finish(fallback(utterance, cause), engine: .fallback, continuedSession: false, cause: cause)
        #endif
    }

    #if ASK_FOUNDATION_MODELS || os(watchOS)
    private func answerGenerated<Answer: Generable & Sendable>(
        _ utterance: String,
        generating type: Answer.Type,
        fallback: @escaping @MainActor (String, AskOnDeviceFallbackCause) -> Answer
    ) async -> AskOnDeviceTurn<Answer> {
        switch await openSession() {
        case .failure(let cause):
            return finish(fallback(utterance, cause), engine: .fallback, continuedSession: false, cause: cause)
        case .success(let opened):
            do {
                let answer = try await opened.session.respond(to: utterance, generating: type)
                return finish(answer, engine: .foundationModels, continuedSession: opened.continuedSession, cause: nil)
            } catch {
                let cause = Self.failureCause(error)
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

    private func openSession() async -> Result<OpenedSession, AskOnDeviceFallbackCause> {
        let availability = self.availability
        guard availability.isAvailable else {
            return .failure(failureCause(for: availability))
        }
        if let session {
            return .success(OpenedSession(session: session, continuedSession: true))
        }
        let reported = await environment.contextSize()
        let window = AskOnDeviceBoundary.resolvedContextSize(reported: reported, choice: model)
        AskTrace.attribute("contextSize", String(window))
        AskTrace.attribute("model", model.rawValue)
        let text = instructions()
        guard AskOnDeviceBoundary.instructionsFit(text, window: window) else {
            return .failure(.instructionsTooLong)
        }
        let toolList = tools()
        AskTrace.attribute("tools", toolList.map(\.name).joined(separator: ", "))
        let made = sessions.make(text, toolList, model)
        session = made
        return .success(OpenedSession(session: made, continuedSession: false))
    }
    #endif

    private func failureCause(for availability: AskOnDeviceAvailability) -> AskOnDeviceFallbackCause {
        switch availability {
        case .available:
            return .unavailable(.unsupportedPlatform)
        case .unavailable(let reason):
            switch reason {
            case .quotaReached:
                return .quotaReached
            case .offline:
                return .offline
            default:
                return .unavailable(reason)
            }
        }
    }

    private static func failureCause(_ error: Error) -> AskOnDeviceFallbackCause {
        if AskModelSafety.isBlocked(error) { return .blocked }
        #if ASK_FOUNDATION_MODELS || os(watchOS)
        if let cloud = error as? PrivateCloudComputeLanguageModel.Error {
            switch cloud {
            case .quotaLimitReached:
                return .quotaReached
            case .networkFailure:
                return .offline
            case .serviceUnavailable:
                return .modelFailed
            @unknown default:
                return .modelFailed
            }
        }
        #endif
        return .modelFailed
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
        case .quotaReached:
            return "quotaReached"
        case .offline:
            return "offline"
        }
    }
}

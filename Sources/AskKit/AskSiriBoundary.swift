import Foundation

/// Where an answer or an action actually runs.
///
/// On-device Foundation Models, Private Cloud Compute, an ordinary App Intent, and a Siri
/// custom tool are four different paths. A tool on a `LanguageModelSession` is not a
/// `ToolIntent`. Private Cloud Compute for the answer model is not Siri's server-side tool loop.
public enum AskAnswerLane: String, Sendable, Equatable, CaseIterable {
    /// `SystemLanguageModel`. No network. Not a Siri tool. Apple Watch and Apple TV do not use this lane.
    case onDeviceModel
    /// `PrivateCloudComputeLanguageModel`. Needs a network. Available on Apple Watch. Not a Siri tool.
    case privateCloudModel
    /// Shortcuts, buttons, and other App Intents. They do not require Private Cloud Compute.
    case ordinaryAppIntent
    /// `@AppIntent(.tool)` / `ToolIntent`. The lab says this loop runs with Siri on the server.
    case siriCustomTool
}

/// One of the four ways a custom Siri tool comes into scope.
///
/// Schemas are eligible more broadly. These gates are for custom tools and Siri app skills.
public enum AskSiriContextSignal: String, Sendable, Equatable, Hashable, CaseIterable {
    case appNamed
    case appForeground
    case liveActivity
    case entityInContext
}

/// The device the person is talking to. A watch can use Private Cloud Compute and still have no custom Siri tools.
public enum AskClientPlatform: String, Sendable, Equatable, CaseIterable {
    case iPhone
    case iPad
    case mac
    case appleTV
    case appleWatch
    case vision
}

/// Why a lane does not run. `.none` means this check passed. Other checks can still fail.
public enum AskLaneBlock: String, Sendable, Equatable {
    case none
    /// Apple Watch and Apple TV are not given the on-device system model by this package.
    case onDeviceUnavailable
    /// Custom Siri tools need Private Cloud Compute connectivity. The on-device model does not.
    case siriToolsNeedNetwork
    /// Private Cloud Compute, the answer model, needs a network. This is not a Siri tool error.
    case privateCloudNeedsNetwork
    /// Apple's Private Cloud Compute type and entitlement omit Apple TV.
    case privateCloudUnavailable
    /// The lab did not announce `ToolIntent` on watchOS, and it did not announce a relay to the phone.
    case watchSiriToolsNotAnnounced
    /// None of the four custom-tool signals is present.
    case customToolNotInContext
}

/// How many custom tools the preview will take, and what the lab said about calls inside one skill.
public enum AskSiriLimits {
    /// Custom tools in the 27.3 developer preview. Schema actions are not part of this count.
    public static let previewToolCap = 40

    /// The lab said Siri can do about 30 to 32 calls within a skill. That is not a library limit.
    public static let skillCallsNotedLower = 30
    public static let skillCallsNotedUpper = 32

    public static func exposedCustomToolCount(proposed: Int) -> Int {
        min(max(proposed, 0), previewToolCap)
    }

    /// Skills do not get a hard stop at 32. The app does not drop a later call on that account.
    public static func skillCallsToAllow(proposed: Int) -> Int {
        max(proposed, 0)
    }
}

/// Schema first. Custom tools cover what the schema does not.
public enum AskToolAdoption: String, Sendable, Equatable {
    case schema
    case custom
    case schemaPlusCustom

    public static func choose(hasMatchingSchema: Bool, needsCustomBehavior: Bool) -> AskToolAdoption {
        if hasMatchingSchema && needsCustomBehavior { return .schemaPlusCustom }
        if hasMatchingSchema { return .schema }
        return .custom
    }
}

/// `EntityCollection` only when the action needs many identifiers and not the full entities.
public enum AskEntityParameter: Sendable, Equatable {
    case single
    case resolvedEntities(Int)
    case identifierCollection(Int)

    public static func choose(count: Int, performOnlyNeedsIdentifiers: Bool) -> AskEntityParameter {
        if count <= 1 { return .single }
        if performOnlyNeedsIdentifiers { return .identifierCollection(count) }
        return .resolvedEntities(count)
    }
}

/// Siri app skills (`SKILL.md`) are optional guidance. AskKit's `AskSkill` router is a different thing.
public enum AskSiriSkillGuidance {
    /// A tool has to perform when no skill is loaded. The skill is not the implementation.
    public static let toolsStandAlone = true

    /// A skill does not roll work back and does not enforce an order. The app does that.
    public static let rollsBackOrEnforcesOrder = false

    /// True when the prose names the Swift type. Siri skills should use ordinary words instead.
    public static func citesSwiftType(_ prose: String, typeName: String) -> Bool {
        let name = typeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return prose.localizedCaseInsensitiveContains(name)
    }
}

/// Lock-screen policy, property visibility, and the person's consent are three different switches.
///
/// `AskDeviceLock` maps to `IntentAuthenticationPolicy`:
/// `.alwaysAllowed`, `.requiresAuthentication`, and `.requiresLocalDeviceAuthentication`.
/// `AskFieldVisibility.internal` maps to `visibility: .internal` on `@Property` and `@ComputedProperty`.
/// The app still validates the business rule in `perform()`. None of these is that check.
public enum AskDeviceLock: String, Sendable, Equatable, CaseIterable {
    case alwaysAllowed
    case requiresAuthentication
    case requiresLocalDeviceAuthentication

    public var allowsLockedDevice: Bool { self == .alwaysAllowed }
}

public enum AskFieldVisibility: String, Sendable, Equatable, CaseIterable {
    /// Siri and Shortcuts may read the property. This is the default. The library does not hide fields on its own.
    case visible
    /// The app and its widgets keep the value. Siri and Shortcuts do not read it.
    case `internal`
}

public enum AskConsumerConsent: String, Sendable, Equatable, CaseIterable {
    case notRequired
    case granted
    case withheld
}

public struct AskDisclosedField: Sendable, Equatable, Identifiable {
    public var id: String
    public var visibility: AskFieldVisibility
    public var lock: AskDeviceLock
    public var consent: AskConsumerConsent

    /// Visible, allowed while locked, and no extra consent. The app opts into a tighter policy per field.
    public init(
        id: String,
        visibility: AskFieldVisibility = .visible,
        lock: AskDeviceLock = .alwaysAllowed,
        consent: AskConsumerConsent = .notRequired
    ) {
        self.id = id
        self.visibility = visibility
        self.lock = lock
        self.consent = consent
    }

    public var modelMayReadWhenUnlocked: Bool {
        AskDisclosure.modelMayRead(self, deviceUnlocked: true)
    }
}

public enum AskDisclosure {
    /// The model may see this field. Hidden, locked, or unconsented fields stay out.
    /// A true result is not permission to perform the action. ``performMustValidate`` stays true.
    public static func modelMayRead(_ field: AskDisclosedField, deviceUnlocked: Bool) -> Bool {
        guard field.visibility == .visible else { return false }
        guard field.consent != .withheld else { return false }
        if !field.lock.allowsLockedDevice && !deviceUnlocked { return false }
        return true
    }

    public static func modelVisible(_ fields: [AskDisclosedField], deviceUnlocked: Bool) -> [AskDisclosedField] {
        fields.filter { modelMayRead($0, deviceUnlocked: deviceUnlocked) }
    }

    /// The perform method checks the business rule. Visibility, consent, and the lock do not.
    public static let performMustValidate = true
}

/// A disruptive or physical action confirms inside `perform()` with `requestConfirmation`.
/// The model is not that check.
public enum AskPerformConfirmation: String, Sendable, Equatable {
    case notNeeded
    case confirmInPerform

    public static func choose(changesDataIrrevocably: Bool, physicalEffect: Bool) -> AskPerformConfirmation {
        if changesDataIrrevocably || physicalEffect { return .confirmInPerform }
        return .notNeeded
    }
}

/// Which process runs an intent that lives in a shared framework.
public enum AskIntentProcess: String, Sendable, Equatable {
    /// Something is already running, so the system uses it.
    case alreadyRunning
    /// Nothing is running. The system prefers the extension.
    case appExtension

    public static func preference(processAlreadyRunning: Bool) -> AskIntentProcess {
        processAlreadyRunning ? .alreadyRunning : .appExtension
    }

    /// There is no automatic handoff from iPhone to Mac. Each app ships its own intents.
    public static let crossesFromIPhoneToMac = false
}

/// AskKit does not adopt `LongRunningIntent`.
///
/// Its intents answer, change one reminder, or run a card button. None of those is the
/// long operation the protocol is for. The lab did not promise that Siri waits without a limit.
/// Progress and cancellation belong on an intent that actually runs that long.
public enum AskLongRun {
    public static let adoptsLongRunningIntent = false
    public static let reason = "No AskKit intent runs long enough to need a progress UI. Siri is not promised an unlimited wait."
}

/// What a library test can decide. Running `SiriService` is a device check, not this type.
public enum AskSiriScenarioKind: String, Sendable, Equatable, CaseIterable {
    case discovery
    case paraphrase
    case directTool
    case skillOnly
    case missingEntity
    case privateField
    case offlineCustomTool
}

public struct AskSiriScenario: Sendable, Equatable, Identifiable {
    public var id: String
    public var utterance: String
    public var kind: AskSiriScenarioKind

    public init(id: String, utterance: String, kind: AskSiriScenarioKind) {
        self.id = id
        self.utterance = utterance
        self.kind = kind
    }
}

public enum AskSiriScenarioOutcome: String, Sendable, Equatable {
    /// The in-app capabilities answer. Not a Siri tool call.
    case capabilities
    /// The same custom tool can run. A paraphrase is not a different tool. A skill is not required.
    case toolWithoutSkill
    /// The entity is not there. The answer does not invent it.
    case entityMissing
    /// The field is internal. The model does not read it.
    case fieldHidden
    /// Custom tools stay off. The on-device lane is a separate question.
    case customToolOffline
    /// Only a device running SiriEvaluations can score this utterance. This library does not.
    case deviceSiriEvaluation
}

/// SiriEvaluations runs on a signed device build. It is not in the simulator SDK and it is not an LLM judge.
public enum AskSiriEvaluationRuntime {
    public static let runsInLibraryUnitTests = false
    public static let requiresPhysicalDevice = true
    public static let simulatorSupported = false
    public static let usesLLMJudge = false
    /// Instruments measures latency. It is not this evaluation.
    public static let measuresLatency = false
}

public enum AskSiriBoundary {
    public static let scenarios: [AskSiriScenario] = [
        AskSiriScenario(id: "discover", utterance: "What can I do with this app?", kind: .discovery),
        AskSiriScenario(id: "paraphrase", utterance: "Stick this on my list", kind: .paraphrase),
        AskSiriScenario(id: "direct", utterance: "Add pasta to the list", kind: .directTool),
        AskSiriScenario(id: "skill", utterance: "Plan dinner from the skill", kind: .skillOnly),
        AskSiriScenario(id: "missing", utterance: "Open the missing jar", kind: .missingEntity),
        AskSiriScenario(id: "private", utterance: "Read the internal note", kind: .privateField),
        AskSiriScenario(id: "offline", utterance: "Use the custom tool", kind: .offlineCustomTool)
    ]

    public static func block(
        lane: AskAnswerLane,
        online: Bool,
        platform: AskClientPlatform,
        signals: Set<AskSiriContextSignal>
    ) -> AskLaneBlock {
        switch lane {
        case .ordinaryAppIntent:
            return .none
        case .onDeviceModel:
            if platform == .appleWatch || platform == .appleTV { return .onDeviceUnavailable }
            return .none
        case .privateCloudModel:
            if platform == .appleTV { return .privateCloudUnavailable }
            return online ? .none : .privateCloudNeedsNetwork
        case .siriCustomTool:
            if platform == .appleWatch { return .watchSiriToolsNotAnnounced }
            if !online { return .siriToolsNeedNetwork }
            if signals.isEmpty { return .customToolNotInContext }
            return .none
        }
    }

    public static func message(for block: AskLaneBlock) -> String? {
        switch block {
        case .none:
            return nil
        case .onDeviceUnavailable:
            return "This device has no on-device system model. On Apple Watch, Private Cloud Compute can still answer, and that answer is not a Siri tool."
        case .siriToolsNeedNetwork:
            return "Custom Siri tools need a network connection because that loop uses Private Cloud Compute. An on-device answer can still run."
        case .privateCloudNeedsNetwork:
            return "Private Cloud Compute needs a network connection. This is the answer model, not a Siri tool."
        case .privateCloudUnavailable:
            return "Private Cloud Compute is not available on Apple TV."
        case .watchSiriToolsNotAnnounced:
            return "Custom Siri tools are not available on Apple Watch. A Private Cloud Compute answer on the watch is separate and still needs the network."
        case .customToolNotInContext:
            return "Siri uses this app's custom tools when the app is named, in the foreground, showing a Live Activity, or after one of its entities is already in the conversation."
        }
    }

    /// The safe library result for a catalog scenario.
    /// Paraphrase wording is scored on device. The library only checks that it is the same tool path as a direct request.
    public static func outcome(_ scenario: AskSiriScenario, online: Bool, entityFound: Bool) -> AskSiriScenarioOutcome {
        switch scenario.kind {
        case .discovery:
            return .capabilities
        case .paraphrase, .directTool:
            return .toolWithoutSkill
        case .skillOnly:
            return .toolWithoutSkill
        case .missingEntity:
            return entityFound ? .toolWithoutSkill : .entityMissing
        case .privateField:
            return .fieldHidden
        case .offlineCustomTool:
            return online ? .toolWithoutSkill : .customToolOffline
        }
    }

    public static let missingEntityMessage = "That item is not available."
    public static let onDeviceStillAvailableOffline = true
}

/// The system model is not a coding model. AskKit does not add a custom-model backend for that.
public enum AskCodingModel {
    public static let systemModelRecommended = false
    public static let customBackendIncluded = false
}

import Foundation
import os
import Testing
@testable import AskKit
@testable import AskKitIntents

@Suite("Siri and on-device boundaries")
struct AskSiriBoundaryTests {
    @Test func lanesStaySeparateWhenTheNetworkIsDown() {
        #expect(AskSiriBoundary.block(lane: .onDeviceModel, online: false, platform: .iPhone, signals: []) == .none)
        #expect(AskSiriBoundary.block(lane: .ordinaryAppIntent, online: false, platform: .iPhone, signals: []) == .none)
        #expect(AskSiriBoundary.block(lane: .privateCloudModel, online: false, platform: .appleWatch, signals: []) == .privateCloudNeedsNetwork)
        #expect(AskSiriBoundary.block(lane: .siriCustomTool, online: false, platform: .iPhone, signals: [.appNamed]) == .siriToolsNeedNetwork)
        let toolMessage = AskSiriBoundary.message(for: .siriToolsNeedNetwork)
        let cloudMessage = AskSiriBoundary.message(for: .privateCloudNeedsNetwork)
        #expect(toolMessage != cloudMessage)
        #expect(toolMessage?.contains("on-device") == true)
        #expect(AskSiriBoundary.onDeviceStillAvailableOffline)
    }

    @Test func watchKeepsPrivateCloudAndDoesNotGainSiriTools() {
        #expect(AskSiriBoundary.block(lane: .onDeviceModel, online: true, platform: .appleWatch, signals: []) == .onDeviceUnavailable)
        #expect(AskSiriBoundary.block(lane: .privateCloudModel, online: true, platform: .appleWatch, signals: []) == .none)
        #expect(AskSiriBoundary.block(lane: .privateCloudModel, online: true, platform: .appleTV, signals: []) == .privateCloudUnavailable)
        #expect(AskSiriBoundary.block(lane: .siriCustomTool, online: true, platform: .appleWatch, signals: [.appForeground]) == .watchSiriToolsNotAnnounced)
    }

    @Test func customToolsNeedOneOfTheFourSignals() {
        let signals = Set(AskSiriContextSignal.allCases)
        #expect(signals.count == 4)
        #expect(AskSiriBoundary.block(lane: .siriCustomTool, online: true, platform: .iPhone, signals: []) == .customToolNotInContext)
        #expect(signals.allSatisfy({ signal in
            AskSiriBoundary.block(lane: .siriCustomTool, online: true, platform: .mac, signals: [signal]) == .none
        }))
    }

    @Test func thePreviewCapsToolsAndDoesNotCapSkillCalls() {
        #expect(AskSiriLimits.previewToolCap == 40)
        #expect(AskSiriLimits.exposedCustomToolCount(proposed: 48) == 40)
        #expect(AskSiriLimits.exposedCustomToolCount(proposed: 3) == 3)
        #expect(AskSiriLimits.skillCallsNotedLower == 30)
        #expect(AskSiriLimits.skillCallsNotedUpper == 32)
        #expect(AskSiriLimits.skillCallsToAllow(proposed: 33) == 33)
        #expect(!AskSiriSkillGuidance.rollsBackOrEnforcesOrder)
        #expect(AskSiriSkillGuidance.toolsStandAlone)
    }

    @Test func schemaComesFirstAndBatchesStayNarrow() {
        #expect(AskToolAdoption.choose(hasMatchingSchema: true, needsCustomBehavior: false) == .schema)
        #expect(AskToolAdoption.choose(hasMatchingSchema: true, needsCustomBehavior: true) == .schemaPlusCustom)
        #expect(AskToolAdoption.choose(hasMatchingSchema: false, needsCustomBehavior: true) == .custom)
        #expect(AskEntityParameter.choose(count: 1, performOnlyNeedsIdentifiers: true) == .single)
        #expect(AskEntityParameter.choose(count: 12, performOnlyNeedsIdentifiers: false) == .resolvedEntities(12))
        #expect(AskEntityParameter.choose(count: 12, performOnlyNeedsIdentifiers: true) == .identifierCollection(12))
    }

    @Test func skillProseDoesNotCiteTheSwiftType() {
        #expect(AskSiriSkillGuidance.citesSwiftType("Call CreateBlogPostIntent.", typeName: "CreateBlogPostIntent"))
        #expect(!AskSiriSkillGuidance.citesSwiftType("Create a blog post.", typeName: "CreateBlogPostIntent"))
    }

    @Test func disclosureKeepsVisibilityConsentAndTheLockApart() {
        let balance = AskDisclosedField(id: "balance", lock: .requiresLocalDeviceAuthentication)
        let lastFour = AskDisclosedField(id: "lastFour")
        let note = AskDisclosedField(id: "note", visibility: .internal)
        let secret = AskDisclosedField(id: "secret", consent: .withheld)
        #expect(!AskDisclosure.modelMayRead(balance, deviceUnlocked: false))
        #expect(AskDisclosure.modelMayRead(balance, deviceUnlocked: true))
        #expect(AskDisclosure.modelMayRead(lastFour, deviceUnlocked: false))
        #expect(!AskDisclosure.modelMayRead(note, deviceUnlocked: true))
        #expect(!AskDisclosure.modelMayRead(secret, deviceUnlocked: true))
        let visible = AskDisclosure.modelVisible([balance, lastFour, note, secret], deviceUnlocked: true)
        #expect(visible.map(\.id) == ["balance", "lastFour"])
        #expect(AskDisclosure.performMustValidate)
        #expect(AskDisclosedField(id: "title").visibility == .visible)
        #expect(AskDisclosedField(id: "title").lock == .alwaysAllowed)
    }

    @Test func confirmationStaysInTheApp() {
        #expect(AskPerformConfirmation.choose(changesDataIrrevocably: false, physicalEffect: false) == .notNeeded)
        #expect(AskPerformConfirmation.choose(changesDataIrrevocably: true, physicalEffect: false) == .confirmInPerform)
        #expect(AskPerformConfirmation.choose(changesDataIrrevocably: false, physicalEffect: true) == .confirmInPerform)
    }

    @Test func theRunningProcessWinsAndDevicesDoNotHandOff() {
        #expect(AskIntentProcess.preference(processAlreadyRunning: true) == .alreadyRunning)
        #expect(AskIntentProcess.preference(processAlreadyRunning: false) == .appExtension)
        #expect(!AskIntentProcess.crossesFromIPhoneToMac)
        #expect(!AskLongRun.adoptsLongRunningIntent)
        #expect(!AskLongRun.reason.isEmpty)
        #expect(!AskCodingModel.systemModelRecommended)
        #expect(!AskCodingModel.customBackendIncluded)
    }

    @Test func discoveryPhrasesIncludeTheAppQuestion() {
        let phrases = [
            "What can I do with this app?",
            "What can I do with the app",
            "What can you do with this app?",
            "What can I ask this app?",
            "What can this app do?"
        ]
        #expect(phrases.allSatisfy({ AskCapabilities.isQuestion($0) }))
        let routed = ["What can I do about the battery?", "What can I do with the pasta?"]
        #expect(routed.allSatisfy({ !AskCapabilities.isQuestion($0) }))
    }

    @Test func catalogOutcomesFailClosedWithoutCallingSiri() {
        let byKind = Dictionary(uniqueKeysWithValues: AskSiriBoundary.scenarios.map { ($0.kind, $0) })
        #expect(AskSiriScenarioKind.allCases.allSatisfy({ byKind[$0] != nil }))
        #expect(AskSiriBoundary.outcome(scenario(.discovery), online: false, entityFound: false) == .capabilities)
        #expect(AskSiriBoundary.outcome(scenario(.directTool), online: true, entityFound: true) == .toolWithoutSkill)
        #expect(AskSiriBoundary.outcome(scenario(.paraphrase), online: true, entityFound: true) == .toolWithoutSkill)
        #expect(AskSiriBoundary.outcome(scenario(.skillOnly), online: true, entityFound: true) == .toolWithoutSkill)
        #expect(AskSiriBoundary.outcome(scenario(.missingEntity), online: true, entityFound: false) == .entityMissing)
        #expect(AskSiriBoundary.outcome(scenario(.privateField), online: true, entityFound: true) == .fieldHidden)
        #expect(AskSiriBoundary.outcome(scenario(.offlineCustomTool), online: false, entityFound: true) == .customToolOffline)
        #expect(AskSiriBoundary.missingEntityMessage == "That item is not available.")
        #expect(!AskSiriEvaluationRuntime.runsInLibraryUnitTests)
        #expect(AskSiriEvaluationRuntime.requiresPhysicalDevice)
        #expect(!AskSiriEvaluationRuntime.simulatorSupported)
        #expect(!AskSiriEvaluationRuntime.usesLLMJudge)
        #expect(!AskSiriEvaluationRuntime.measuresLatency)
    }

    @Test func theSnippetButtonIntentPerformsWithoutSiri() async throws {
        let type = "boundary-\(UUID().uuidString)"
        let seen = OSAllocatedUnfairLock(initialState: [String]())
        AskSnippetActionCenter.shared.register(entityType: type) { request in
            seen.withLock { $0.append(request.actionID) }
        }
        defer { AskSnippetActionCenter.shared.remove(entityType: type) }
        let request = AskSnippetActionRequest(entityType: type, entityID: "pasta", actionID: "favorite", role: .favorite)
        _ = try await AskSnippetButtonIntent(request: request).perform()
        #expect(seen.withLock({ $0 }) == ["favorite"])
    }

    private func scenario(_ kind: AskSiriScenarioKind) -> AskSiriScenario {
        AskSiriBoundary.scenarios.first(where: { $0.kind == kind })
            ?? AskSiriScenario(id: "missing", utterance: "", kind: kind)
    }
}

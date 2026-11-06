#if ASK_SAMPLE_SIRI_TOOLS
import AppIntentsTesting
import Evaluations
import Foundation
import SiriEvaluations
import Testing

// Device UI-test target. Not part of `swift test`.
// Symbols used, from the iOS 27.3 Siri Evaluations docs and Apple's SiriService sample
// (the same set ConferenceKit cites, plus Loads and Calls matching from the bundled reference):
//   SiriService.run(scenario:)
//   SiriScenario, SiriScenarioLoader, SiriScenarioSubject
//   UserTurn
//   Calls(.ordered), Calls(.disallowed)
//   Loads(.required)
//   SiriResponse(.contains(_:caseSensitive:))
//   SiriExpectationEvaluator
//   Evaluation.subject(from:), Evaluation.computeSiriMetrics(into:)
//   IntentDefinitions(bundleIdentifier:), .intents, .skills
//   Test.evaluates, EvaluationContext.current.result
//   MetricsAggregator mean of .intentsAllPass and .skillsLoadedAllPass
// The four tools have no parameters, so Calls does not use expect(parameter:).

struct AskGarageSiriEvaluation: Evaluation {
    let name: String
    let dataset: SiriScenarioLoader

    func subject(from sample: SiriScenario) async throws -> SiriScenarioSubject {
        try await SiriService.run(scenario: sample)
    }

    var evaluators: Evaluators {
        SiriExpectationEvaluator()
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        Self.computeSiriMetrics(into: &aggregator)
    }
}

private final class EvaluationBundleMarker {}

private let askHostBundleIdentifier: String = {
    guard let id = Bundle(for: EvaluationBundleMarker.self)
        .object(forInfoDictionaryKey: "AskHostBundleIdentifier") as? String,
        !id.isEmpty
    else {
        fatalError("AskHostBundleIdentifier is missing from the evaluations Info.plist.")
    }
    return id
}()

private let askIntents = IntentDefinitions(bundleIdentifier: askHostBundleIdentifier)

@Suite(.serialized)
struct AskGarageSiriEvaluationTests {
    @Test(.evaluates(AskGarageSiriEvaluation(name: "Garage readings", dataset: toolScenarios)))
    func garageReadings() async throws {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
    }

    @Test(.evaluates(AskGarageSiriEvaluation(name: "Garage skills", dataset: skillScenarios)))
    func garageSkills() async throws {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
        #expect(result.aggregateValue(.mean(of: .skillsLoadedAllPass)) == 1)
    }

    @Test(.evaluates(AskGarageSiriEvaluation(name: "Out of scope", dataset: negativeScenarios)))
    func outOfScope() async throws {
        let result = EvaluationContext.current.result
        #expect(result.aggregateValue(.mean(of: .intentsAllPass)) == 1)
    }
}

private let toolScenarios = SiriScenarioLoader {
    SiriScenario { charge("charge-direct") }
    SiriScenario { charge("charge-paraphrase") }
    SiriScenario { range("range-direct") }
    SiriScenario { range("range-paraphrase") }
    SiriScenario { charger("charger-direct") }
    SiriScenario { charger("charger-no-navigation") }
    SiriScenario { cabinReading("cabin-direct") }
    SiriScenario { cabinReading("cabin-paraphrase") }
}

private let skillScenarios = SiriScenarioLoader {
    SiriScenario { readyDrive("ready-drive") }
    SiriScenario { readyCharge("ready-charge-first") }
    SiriScenario { cabinComfort("cabin-comfort") }
    SiriScenario { cabinComfort("cabin-warm-enough") }
}

private let negativeScenarios = SiriScenarioLoader {
    SiriScenario { blocked("out-of-scope-dinner") }
    SiriScenario { blocked("out-of-scope-unlock") }
    SiriScenario { blocked("out-of-scope-headlights") }
    SiriScenario { blocked("out-of-scope-delete") }
}

private func item(_ id: String) -> GarageSiriEvalCase {
    guard let found = GarageSiriEvalCatalog.cases.first(where: { $0.id == id }) else {
        fatalError("Missing eval case \(id)")
    }
    return found
}

private func charge(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Calls(.ordered) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
        }
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.range]
            askIntents.intents[GarageSiriEvalCatalog.charger]
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
        SiriResponse(.contains(sample.responseContains[0], caseSensitive: false))
    }
}

private func range(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Calls(.ordered) {
            askIntents.intents[GarageSiriEvalCatalog.range]
        }
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
            askIntents.intents[GarageSiriEvalCatalog.charger]
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
        SiriResponse(.contains(sample.responseContains[0], caseSensitive: false))
    }
}

private func charger(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Calls(.ordered) {
            askIntents.intents[GarageSiriEvalCatalog.charger]
        }
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
            askIntents.intents[GarageSiriEvalCatalog.range]
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
        SiriResponse(.contains(sample.responseContains[0], caseSensitive: false))
    }
}

private func cabinReading(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Calls(.ordered) {
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
            askIntents.intents[GarageSiriEvalCatalog.range]
            askIntents.intents[GarageSiriEvalCatalog.charger]
        }
        SiriResponse(.contains(sample.responseContains[0], caseSensitive: false))
    }
}

private func readyDrive(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Loads(.required) {
            askIntents.skills[GarageSiriEvalCatalog.ready]
        }
        Calls(.ordered) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
            askIntents.intents[GarageSiriEvalCatalog.range]
        }
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
    }
}

private func readyCharge(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Loads(.required) {
            askIntents.skills[GarageSiriEvalCatalog.ready]
        }
        Calls(.ordered) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
            askIntents.intents[GarageSiriEvalCatalog.range]
            askIntents.intents[GarageSiriEvalCatalog.charger]
        }
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
    }
}

private func cabinComfort(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Loads(.required) {
            askIntents.skills[GarageSiriEvalCatalog.cabinSkill]
        }
        Calls(.ordered) {
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
            askIntents.intents[GarageSiriEvalCatalog.range]
            askIntents.intents[GarageSiriEvalCatalog.charger]
        }
    }
}

private func blocked(_ id: String) -> UserTurn {
    let sample = item(id)
    return UserTurn(sample.utterance) {
        Calls(.disallowed) {
            askIntents.intents[GarageSiriEvalCatalog.charge]
            askIntents.intents[GarageSiriEvalCatalog.range]
            askIntents.intents[GarageSiriEvalCatalog.charger]
            askIntents.intents[GarageSiriEvalCatalog.cabin]
        }
    }
}
#endif

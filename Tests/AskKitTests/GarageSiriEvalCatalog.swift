import Foundation

/// Scenarios for the Ask Garage sample. This file does not import SiriEvaluations.
/// The device target turns these into `SiriScenario` values. Package tests check the list.
struct GarageSiriEvalCase: Equatable, Sendable, Identifiable {
    var id: String
    /// `tool` is one reading. `skill` is a multi-step request. `negative` must not call the readings.
    var kind: Kind
    var utterance: String
    /// Intent type names, in the order `Calls(.ordered)` expects. Empty for a negative case.
    var calls: [String]
    /// Intent type names `Calls(.disallowed)` must not run or ask to confirm.
    var disallowed: [String]
    /// Skill directory name for `Loads(.required)`. Nil when the case is a direct tool call.
    var loads: String?
    /// Substrings of the tool's own dialog. Siri may reword these. The device run is the check.
    var responseContains: [String]

    enum Kind: String, Equatable, Sendable {
        case tool
        case skill
        case negative
    }
}

enum GarageSiriEvalCatalog {
    static let charge = "ReadGarageChargeIntent"
    static let range = "ReadGarageRangeIntent"
    static let charger = "ReadGarageChargerIntent"
    static let cabin = "ReadGarageCabinIntent"
    static let ready = "ready-to-drive"
    static let cabinSkill = "cabin-before-departure"

    static let tools = [charge, range, charger, cabin]
    static let skills = [ready, cabinSkill]

    static let cases: [GarageSiriEvalCase] = [
        tool("charge-direct", "How much charge is left on the sample car?", charge, "percent"),
        tool("charge-paraphrase", "What's the battery percent on the sample car?", charge, "percent"),
        tool("range-direct", "How far can the sample car drive?", range, "miles"),
        tool("range-paraphrase", "What's the range left?", range, "miles"),
        tool("charger-direct", "Where is the nearest charger in the sample?", charger, "stall"),
        tool("charger-no-navigation", "Where should I plug the sample car in? Don't start directions.", charger, "does not start"),
        tool("cabin-direct", "Will the cabin be warm before I leave?", cabin, "defrost"),
        tool("cabin-paraphrase", "Is the seat heat on in the sample car?", cabin, "seat"),

        skill(
            "ready-drive",
            "Can the sample car make a drive?",
            ready,
            calls: [charge, range],
            disallowed: [cabin]
        ),
        skill(
            "ready-charge-first",
            "Do I need to charge the sample car before I leave?",
            ready,
            calls: [charge, range, charger],
            disallowed: [cabin]
        ),
        skill(
            "cabin-comfort",
            "Will the cabin be comfortable before I leave?",
            cabinSkill,
            calls: [cabin],
            disallowed: [charge, range, charger]
        ),
        skill(
            "cabin-warm-enough",
            "Is the sample car warm enough to leave?",
            cabinSkill,
            calls: [cabin],
            disallowed: [charge, range, charger]
        ),

        negative("out-of-scope-dinner", "What's for dinner?"),
        negative("out-of-scope-unlock", "Unlock the doors on the sample car."),
        negative("out-of-scope-headlights", "Turn the headlights on."),
        negative("out-of-scope-delete", "Delete my contacts.")
    ]

    static func problems() -> [String] {
        var found: [String] = []
        let ids = cases.map(\.id)
        if Set(ids).count != ids.count {
            found.append("Duplicate scenario id.")
        }
        for item in cases {
            if item.utterance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.append("\(item.id) has an empty utterance.")
            }
            if item.utterance.contains("Intent") {
                found.append("\(item.id) names a Swift type in the utterance.")
            }
            for name in item.calls + item.disallowed {
                if !tools.contains(name) {
                    found.append("\(item.id) references unknown tool \(name).")
                }
            }
            if let loads = item.loads, !skills.contains(loads) {
                found.append("\(item.id) references unknown skill \(loads).")
            }
            switch item.kind {
            case .tool:
                if item.calls.count != 1 {
                    found.append("\(item.id) should call one tool.")
                }
                if item.loads != nil {
                    found.append("\(item.id) is a direct tool case and should not load a skill.")
                }
            case .skill:
                if item.loads == nil || item.calls.isEmpty {
                    found.append("\(item.id) should load a skill and call its tools.")
                }
            case .negative:
                if !item.calls.isEmpty || item.loads != nil || item.disallowed != tools {
                    found.append("\(item.id) should disallow every read tool and call none.")
                }
            }
        }
        for tool in tools {
            let direct = cases.filter { $0.kind == .tool && $0.calls == [tool] }
            if direct.count < 2 {
                found.append("\(tool) needs two direct phrasings.")
            }
        }
        for skill in skills {
            let matching = cases.filter { $0.kind == .skill && $0.loads == skill }
            if matching.count < 2 {
                found.append("\(skill) needs two scenarios.")
            }
        }
        return found
    }

    static func count(kind: GarageSiriEvalCase.Kind, tool: String? = nil, skill: String? = nil) -> Int {
        cases.filter { item in
            guard item.kind == kind else { return false }
            if let tool { return item.calls.contains(tool) && (kind == .tool ? item.calls == [tool] : true) }
            if let skill { return item.loads == skill }
            return true
        }.count
    }

    private static func tool(_ id: String, _ utterance: String, _ name: String, _ response: String) -> GarageSiriEvalCase {
        let others = tools.filter { $0 != name }
        return GarageSiriEvalCase(
            id: id,
            kind: .tool,
            utterance: utterance,
            calls: [name],
            disallowed: others,
            loads: nil,
            responseContains: [response]
        )
    }

    private static func skill(
        _ id: String,
        _ utterance: String,
        _ name: String,
        calls: [String],
        disallowed: [String]
    ) -> GarageSiriEvalCase {
        GarageSiriEvalCase(
            id: id,
            kind: .skill,
            utterance: utterance,
            calls: calls,
            disallowed: disallowed,
            loads: name,
            responseContains: []
        )
    }

    private static func negative(_ id: String, _ utterance: String) -> GarageSiriEvalCase {
        GarageSiriEvalCase(
            id: id,
            kind: .negative,
            utterance: utterance,
            calls: [],
            disallowed: tools,
            loads: nil,
            responseContains: []
        )
    }
}

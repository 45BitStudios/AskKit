import Foundation
import Testing

/// Checks the eval catalog without importing SiriEvaluations or starting Siri.
@Suite("Garage Siri eval fixtures")
struct AskGarageSiriEvalFixtureTests {
    @Test func everyToolAndSkillIsCoveredAndReferencesResolve() {
        let problems = GarageSiriEvalCatalog.problems()
        #expect(problems.isEmpty)
        #expect(GarageSiriEvalCatalog.count(kind: .tool, tool: GarageSiriEvalCatalog.charge) == 2)
        #expect(GarageSiriEvalCatalog.count(kind: .tool, tool: GarageSiriEvalCatalog.range) == 2)
        #expect(GarageSiriEvalCatalog.count(kind: .tool, tool: GarageSiriEvalCatalog.charger) == 2)
        #expect(GarageSiriEvalCatalog.count(kind: .tool, tool: GarageSiriEvalCatalog.cabin) == 2)
        #expect(GarageSiriEvalCatalog.count(kind: .skill, skill: GarageSiriEvalCatalog.ready) == 2)
        #expect(GarageSiriEvalCatalog.count(kind: .skill, skill: GarageSiriEvalCatalog.cabinSkill) == 2)
        #expect(GarageSiriEvalCatalog.count(kind: .negative) == 4)
    }

    @Test func theDeviceFileNamesEveryCaseAndTheToolsHaveNoParameters() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let evaluation = try String(
            contentsOf: root.appendingPathComponent("AskKit/AskKitSiriEvaluations/AskGarageSiriEvaluation.swift"),
            encoding: .utf8
        )
        let tools = try String(
            contentsOf: root.appendingPathComponent("AskKit/AskKit/Siri/GarageSiriTools.swift"),
            encoding: .utf8
        )
        #expect(tools.contains("@Parameter") == false)
        #expect(evaluation.contains("ASK_SAMPLE_SIRI_TOOLS"))
        #expect(evaluation.contains("SiriService.run(scenario:)"))
        #expect(evaluation.contains("Calls(.ordered)"))
        #expect(evaluation.contains("Calls(.disallowed)"))
        #expect(evaluation.contains("Loads(.required)"))
        for item in GarageSiriEvalCatalog.cases {
            #expect(evaluation.contains(item.id))
        }
        let skillsRoot = root.appendingPathComponent("AskKit/AskKit/Skills.skillsbundle/Skills")
        for name in GarageSiriEvalCatalog.skills {
            let skill = skillsRoot.appendingPathComponent(name).appendingPathComponent("SKILL.md")
            #expect(FileManager.default.fileExists(atPath: skill.path))
        }
        for name in GarageSiriEvalCatalog.tools {
            #expect(tools.contains("struct \(name)"))
        }
    }
}

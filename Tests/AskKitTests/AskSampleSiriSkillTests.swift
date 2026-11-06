import Foundation
import Testing

/// Checks the sample host's Siri skill bundle and that its tools read the Garage sample.
/// This does not run Siri and does not compile `ToolIntent`.
@Suite("Sample Siri skills")
struct AskSampleSiriSkillTests {
    private static let skillNames = ["ready-to-drive", "cabin-before-departure"]

    @Test func theSkillsBundleMatchesApplesLayout() throws {
        let bundle = try Self.skillsBundle()
        let skillsRoot = bundle.appendingPathComponent("Skills")
        let children = try FileManager.default.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .filter { $0 != ".DS_Store" }
        #expect(children == ["Skills"])

        let folders = try FileManager.default.contentsOfDirectory(at: skillsRoot, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        #expect(folders.map(\.lastPathComponent).sorted() == Self.skillNames.sorted())
        #expect(folders.allSatisfy({ url in
            let files = ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .map(\.lastPathComponent)
                .filter { $0 != ".DS_Store" }
            return files == ["SKILL.md"]
        }))
    }

    @Test func frontMatterIsOnlyNameAndDescription() throws {
        let skills = try Self.loadSkills()
        #expect(skills.map(\.name).sorted() == Self.skillNames.sorted())
        #expect(skills.allSatisfy({ skill in
            skill.name == skill.folder
                && skill.name.count >= 1
                && skill.name.count <= 64
                && skill.name.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression) != nil
                && !skill.description.isEmpty
                && !skill.description.contains("\n")
                && skill.description.count <= 1024
                && skill.body.count <= 10_000
                && skill.extraKeys.isEmpty
        }))
    }

    @Test func theDriveSkillCallsChargeThenRangeAndTheChargerOnlyWhenAsked() throws {
        let drive = try Self.skill("ready-to-drive")
        let cabin = try Self.skill("cabin-before-departure")
        #expect(drive.body.contains("charge status tool"))
        #expect(drive.body.contains("driving range tool"))
        #expect(drive.body.contains("nearest charger tool"))
        #expect(drive.body.contains("Ask Garage chat"))
        #expect(drive.body.contains("do not change data"))
        #expect(!drive.body.contains("cabin tool"))
        #expect(cabin.body.contains("cabin tool"))
        #expect(cabin.body.contains("not available from Siri"))
        #expect(cabin.body.contains("Ask Garage chat"))
        let forbidden = ["Intent", "AskSkill", "ToolIntent", "GarageSample", "chargeStatus", "rangeLeft", "findCharger"]
        #expect(Self.skillNames.allSatisfy({ name in
            let text = (try? Self.skill(name).raw) ?? ""
            return forbidden.allSatisfy({ !text.contains($0) })
        }))
    }

    @Test func theHostCopiesTheBundleAndGatesToolIntent() throws {
        let project = try String(contentsOf: Self.repoRoot().appendingPathComponent("AskKit/AskKit.xcodeproj/project.pbxproj"), encoding: .utf8)
        #expect(project.contains("Skills.skillsbundle in Resources"))
        #expect(project.contains("AskKit/Skills.skillsbundle"))
        #expect(project.contains("membershipExceptions"))
        #expect(project.contains("ASK_SAMPLE_SIRI_TOOLS"))

        let tools = try String(contentsOf: Self.repoRoot().appendingPathComponent("AskKit/AskKit/Siri/GarageSiriTools.swift"), encoding: .utf8)
        #expect(tools.contains("#if ASK_SAMPLE_SIRI_TOOLS && (os(iOS) || os(macOS) || os(visionOS))"))
        #expect(tools.contains("extension ReadGarageChargeIntent: ToolIntent {}"))
        #expect(tools.contains("GarageSiriWork.chargeStatus()"))
        #expect(tools.contains("GarageSiriWork.drivingRange()"))
        #expect(tools.contains("GarageSiriWork.nearestCharger()"))
        #expect(tools.contains("GarageSiriWork.cabin()"))
        #expect(!tools.contains("68 percent"))

        let work = try String(contentsOf: Self.repoRoot().appendingPathComponent("AskKit/AskKit/Siri/GarageSiriWork.swift"), encoding: .utf8)
        let fields = ["GarageSample.vehicle", "GarageSample.battery", "GarageSample.chargeRate", "GarageSample.minutesTo80", "GarageSample.chargeLimit", "GarageSample.range", "GarageSample.chargerName", "GarageSample.chargerDistance", "GarageSample.openStalls", "GarageSample.cabin", "GarageSample.departure", "GarageSample.seatHeat", "GarageSample.defrost"]
        #expect(fields.allSatisfy({ work.contains($0) }))
        #expect(work.contains("AskKit.selectedSample") == false)
        #expect(work.contains("SampleProject.selected"))
        #expect(!work.contains("68 percent"))
    }

    private struct SkillFile {
        var folder: String
        var name: String
        var description: String
        var body: String
        var extraKeys: [String]
        var raw: String
    }

    private static func skill(_ name: String) throws -> SkillFile {
        let match = try loadSkills().first { $0.name == name }
        if let match { return match }
        throw SkillCheckError.missing(name)
    }

    private static func loadSkills() throws -> [SkillFile] {
        let root = try skillsBundle().appendingPathComponent("Skills")
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try folders.map { folder in
            let file = folder.appendingPathComponent("SKILL.md")
            let raw = try String(contentsOf: file, encoding: .utf8)
            let parsed = try parse(raw)
            return SkillFile(
                folder: folder.lastPathComponent,
                name: parsed.name,
                description: parsed.description,
                body: parsed.body,
                extraKeys: parsed.extraKeys,
                raw: raw
            )
        }
    }

    private static func parse(_ raw: String) throws -> (name: String, description: String, body: String, extraKeys: [String]) {
        let parts = raw.components(separatedBy: "---\n")
        guard parts.count >= 3, parts[0].isEmpty else { throw SkillCheckError.frontMatter }
        let header = parts[1]
        let body = parts.dropFirst(2).joined(separator: "---\n")
        var name = ""
        var description = ""
        var extra: [String] = []
        for line in header.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard !line.isEmpty else { continue }
            guard let split = line.firstIndex(of: ":") else { throw SkillCheckError.frontMatter }
            let key = String(line[..<split]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "name": name = value
            case "description": description = value
            default: extra.append(key)
            }
        }
        return (name, description, body, extra)
    }

    private static func skillsBundle() throws -> URL {
        let url = repoRoot().appendingPathComponent("AskKit/AskKit/Skills.skillsbundle")
        guard FileManager.default.fileExists(atPath: url.path) else { throw SkillCheckError.missing(url.path) }
        return url
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum SkillCheckError: Error {
    case frontMatter
    case missing(String)
}

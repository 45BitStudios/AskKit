import Foundation
import Testing
@testable import AskKit

@Suite("Card layout presets")
struct AskCardLayoutPresetTests {
    @Test func presetsAreUniqueAndStayOnTheExistingDSL() {
        let ids = AskCardLayoutPreset.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == ["weather", "schedule", "health", "comparison", "stat"])
        for preset in AskCardLayoutPreset.all {
            #expect(!preset.layoutNotes.isEmpty)
            #expect(!preset.summary.isEmpty)
            #expect(AskCardLayoutPreset.named(preset.id) == preset)
            #expect(AskCardLayoutPreset.named(preset.title) == nil)
        }
        #expect(AskCardLayoutPreset.named("Weather") == .weather)
        #expect(AskCardLayoutPreset.named("  ") == nil)
        #expect(AskCardLayoutPreset.named("nope") == nil)
    }

    @Test func inferencePicksOneDomainOrAThinStat() {
        #expect(infer("Forecast", "72°\nCloudy") == .weather)
        #expect(infer("Outside", "72 degrees and cloudy") == .weather)
        #expect(infer("Friday", "Calendar\n11:00 AM Kick-off") == .schedule)
        #expect(infer("Agenda", "3 events") == .schedule)
        #expect(infer("Today", "8,420 steps") == .health)
        #expect(infer("Activity", "Exercise 24 min\nFlights 12") == .health)
        #expect(infer("Resting", "62 bpm\nHeart") == .health)
        #expect(infer("Week", "Today vs yesterday") == .comparison)
        #expect(infer("Battery", "68 percent\nAbout 40 minutes until 80 percent.") == .singleStat)
        #expect(infer("Drive", "7:30 a.m.") == nil)
        #expect(infer("Pantry", "Salmon\nFour servings\n35 minutes\nPantry") == nil)
        #expect(infer("Today", "Weather on the calendar") == nil)
        #expect(infer("Lunch", "A hearty soup") == .singleStat)
        #expect(infer("Walk", "A few footsteps") == .singleStat)
        #expect(infer("Lunch", "A hearty soup") != .health)
        #expect(infer("Walk", "A few footsteps") != .health)
    }

    @Test func hostChoiceBeatsTheSpecialistAndNotesBlockInference() {
        let battery = ("Battery", "68 percent", "68 percent")
        #expect(resolve(battery, notes: "", preset: "weather", specialist: "health") == .weather)
        #expect(resolve(battery, notes: "", preset: "", specialist: "health") == .health)
        #expect(resolve(battery, notes: "Badge says Charge.", preset: "", specialist: "") == nil)
        #expect(resolve(battery, notes: "Badge says Charge.", preset: "comparison", specialist: "health") == .comparison)

        let weatherNotes = AskCardLayoutPreset.weather.layoutNotes
        #expect(AskCardLayoutPreset.notes(from: .weather, layoutNotes: "") == weatherNotes)
        #expect(AskCardLayoutPreset.notes(from: .weather, layoutNotes: weatherNotes) == weatherNotes)
        #expect(AskCardLayoutPreset.notes(from: .weather, layoutNotes: weatherNotes + "\nBadge says Trip.") == weatherNotes + "\nBadge says Trip.")
        let merged = AskCardLayoutPreset.notes(from: .weather, layoutNotes: "Badge says Trip.")
        #expect(merged.hasPrefix(weatherNotes))
        #expect(merged.hasSuffix("Badge says Trip."))
        #expect(AskCardLayoutPreset.notes(from: nil, layoutNotes: "Badge says Trip.") == "Badge says Trip.")
    }

    @Test @MainActor func composeWritesTheChosenPresetIntoLayoutNotes() async throws {
        let model = ScriptedCardModel()
        model.composeError = AskCardComposeError.unavailable
        let assistant = try makeAssistant(model: model, specialist: AskCardSpecialist(
            instructions: .append("Keep one primary stat.")
        ))
        _ = await assistant.composeCard(from: AskGeneratedBlueprint(
            title: "Battery",
            spoken: "The battery is at 68 percent.",
            facts: "68 percent\nAbout 40 minutes until 80 percent.",
            layoutNotes: "Badge says Charge.",
            layoutPresetID: AskCardLayoutPreset.weather.id
        ))
        let request = try #require(model.composeRequests.last)
        #expect(request.instructions.contains("Keep one primary stat."))
        #expect(request.instructions.contains(AskCardLayoutPreset.weather.layoutNotes))
        #expect(request.instructions.contains("Badge says Charge."))
        #expect(request.instructions.contains("LAYOUT"))
    }

    @Test @MainActor func emptyNotesInferAPresetAndHostNotesDoNot() async throws {
        let model = ScriptedCardModel()
        model.composeError = AskCardComposeError.unavailable
        let assistant = try makeAssistant(model: model, specialist: .default)
        _ = await assistant.composeCard(from: AskGeneratedBlueprint(
            title: "Battery",
            spoken: "The battery is at 68 percent.",
            facts: "68 percent\nAbout 40 minutes until 80 percent."
        ))
        let inferred = try #require(model.composeRequests.last)
        #expect(inferred.instructions.contains("Single stat."))

        _ = await assistant.composeCard(from: AskGeneratedBlueprint(
            title: "Battery",
            spoken: "The battery is at 68 percent.",
            facts: "68 percent\nAbout 40 minutes until 80 percent.",
            layoutNotes: "Badge says Charge."
        ))
        let noted = try #require(model.composeRequests.last)
        #expect(noted.instructions.contains("Badge says Charge."))
        #expect(!noted.instructions.contains("Single stat."))
    }

    @Test @MainActor func specialistPresetWinsWhenTheBlueprintDoesNotChoose() async throws {
        let model = ScriptedCardModel()
        model.composeError = AskCardComposeError.unavailable
        let assistant = try makeAssistant(model: model, specialist: AskCardSpecialist(
            layoutPresetID: AskCardLayoutPreset.health.id
        ))
        _ = await assistant.composeCard(from: AskGeneratedBlueprint(
            title: "Battery",
            spoken: "The battery is at 68 percent.",
            facts: "68 percent"
        ))
        let request = try #require(model.composeRequests.last)
        #expect(request.instructions.contains("Health summary."))
        #expect(!request.instructions.contains("Single stat."))
    }

    private func infer(_ title: String, _ facts: String) -> AskCardLayoutPreset? {
        AskCardLayoutPreset.infer(title: title, facts: facts, spoken: facts)
    }

    private func resolve(
        _ parts: (String, String, String),
        notes: String,
        preset: String,
        specialist: String
    ) -> AskCardLayoutPreset? {
        AskCardLayoutPreset.resolved(
            title: parts.0,
            facts: parts.1,
            spoken: parts.2,
            layoutNotes: notes,
            layoutPresetID: preset,
            specialistPresetID: specialist
        )
    }

    @MainActor
    private func makeAssistant(model: ScriptedCardModel, specialist: AskCardSpecialist) throws -> AskAssistant {
        try AskAssistant(
            AskConfiguration(
                assistantName: "Presets",
                persistence: .memory,
                domains: [AskDomain(id: "battery", summary: "Battery", routingNotes: "Battery")],
                skills: [],
                context: { AskContext() },
                chips: { _ in [] },
                fastPath: { _ in nil },
                guide: AskGuide(replyInstructions: "", followUpInstructions: ""),
                cardSpecialist: specialist
            ),
            model: model.client
        )
    }
}

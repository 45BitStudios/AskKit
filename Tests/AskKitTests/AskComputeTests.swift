import FoundationModels
import XCTest
@testable import AskKit
@testable import AskKitIntents
@testable import AskKitSurface
@testable import AskKitUI

final class AskComputeTests: XCTestCase {
    func testPreferredModelRunsWhenItIsAvailable() {
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .privateCloud, onDevice: true, cloud: true, online: true),
            .privateCloud
        )
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .onDevice, onDevice: true, cloud: false, online: true),
            .onDevice
        )
    }

    func testUnavailablePreferenceUsesTheOtherModel() {
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .privateCloud, onDevice: true, cloud: false, online: true),
            .onDevice
        )
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .onDevice, onDevice: false, cloud: true, online: true),
            .privateCloud
        )
    }

    func testOfflinePrivateCloudFallsBackToOnDevice() {
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .privateCloud, onDevice: true, cloud: true, online: false),
            .onDevice
        )
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .onDevice, onDevice: false, cloud: true, online: false),
            .onDevice
        )
    }

    func testBothUnavailableKeepsThePreference() {
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .privateCloud, onDevice: false, cloud: false, online: true),
            .privateCloud
        )
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .onDevice, onDevice: false, cloud: false, online: true),
            .onDevice
        )
        XCTAssertEqual(
            AskComputeChoice.resolved(preferred: .privateCloud, onDevice: false, cloud: true, online: false),
            .privateCloud
        )
    }

    func testRouterHistoryKeepsPromptsAndDropsToolsAndReasoning() {
        let entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: "Route."))],
                toolDefinitions: []
            )),
            .prompt(Transcript.Prompt(
                segments: [.text(Transcript.TextSegment(content: "What's on Saturday?"))]
            )),
            .reasoning(Transcript.Reasoning(
                segments: [.text(Transcript.TextSegment(content: "think"))],
                signature: Data([1, 2, 3])
            )),
            .toolCalls(Transcript.ToolCalls([
                Transcript.ToolCall(id: "c1", toolName: "calendar", arguments: "day".generatedContent)
            ])),
            .toolOutput(Transcript.ToolOutput(
                id: "o1",
                toolName: "calendar",
                segments: [.text(Transcript.TextSegment(content: "Dinner"))]
            )),
            .response(Transcript.Response(
                segments: [.text(Transcript.TextSegment(content: "Dinner at 7."))]
            ))
        ]
        let kept = AskTranscript.forRouting(entries)
        XCTAssertEqual(kept.map(Self.entryKind), ["instructions", "prompt", "response"])
    }

    private static func entryKind(_ entry: Transcript.Entry) -> String {
        switch entry {
        case .instructions: "instructions"
        case .prompt: "prompt"
        case .toolCalls: "toolCalls"
        case .toolOutput: "toolOutput"
        case .response: "response"
        case .reasoning: "reasoning"
        @unknown default: "other"
        }
    }

    func testCloudOptionsRoundTripAndDropABadTemperature() {
        let suite = UserDefaults(suiteName: "AskCloudOptionsTests")!
        suite.removePersistentDomain(forName: "AskCloudOptionsTests")
        XCTAssertEqual(AskCloudSettings.read(suite), .standard)

        let chosen = AskCloudOptions(reasoning: .deep, temperature: 0.25, length: .short)
        AskCloudSettings.write(chosen, to: suite)
        XCTAssertEqual(AskCloudSettings.read(suite), chosen)
        XCTAssertEqual(AskCloudReasoning.light.level, .light)
        XCTAssertEqual(AskCloudReasoning.moderate.level, .moderate)
        XCTAssertEqual(AskCloudReasoning.deep.level, .deep)
        XCTAssertEqual(chosen.length.maximumResponseTokens, 256)
        XCTAssertNil(AskCloudLength.automatic.maximumResponseTokens)

        AskCloudSettings.write(AskCloudOptions(reasoning: .light, temperature: 4, length: .long), to: suite)
        let stored = AskCloudSettings.read(suite)
        XCTAssertNil(stored.temperature)
        XCTAssertEqual(stored.length, .long)
        XCTAssertEqual(stored.length.maximumResponseTokens, 1024)
        suite.removePersistentDomain(forName: "AskCloudOptionsTests")
    }

    func testQuotaLineNamesTheDailyLimit() {
        XCTAssertEqual(AskCloudQuotaText.line(reached: false, approaching: false), "Within the daily limit")
        XCTAssertEqual(AskCloudQuotaText.line(reached: false, approaching: true), "Near the daily limit")
        XCTAssertEqual(AskCloudQuotaText.line(reached: true, approaching: true), "Daily limit reached")
    }
}

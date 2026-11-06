import SwiftData
import XCTest
@testable import AskKit

/// The sample app's local file. A private directory stands in for Application Support.
@MainActor
final class AskSampleStoreTests: XCTestCase {
    func testARelaunchKeepsTheThreadAndClearRemovesOnlyThatAssistant() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AskKitSampleTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = AskLocalStore.directory(in: root)
        let persistence = try AskLocalStore.persistence(directory: directory)
        let configuration = try XCTUnwrap(AskStoreBuilder.modelConfiguration(for: persistence))
        XCTAssertFalse(configuration.isStoredInMemoryOnly)
        XCTAssertEqual(
            String(describing: configuration.cloudKitDatabase),
            String(describing: ModelConfiguration.CloudKitDatabase.none)
        )
        XCTAssertEqual(directory.lastPathComponent, AskLocalStore.folderName)
        XCTAssertTrue(directory.path.hasPrefix(root.path))

        try await ask("Ask Garage", chip: AskChip(id: "charge", skillID: "charge", title: "Charge status"), persistence: persistence)
        let reopened = try userTexts("Ask Garage", persistence: persistence)
        XCTAssertEqual(reopened, ["Charge status"])

        try await ask("Ask Pantry", chip: AskChip(id: "dinner", skillID: "dinner", title: "What's for dinner?"), persistence: persistence)
        try clear("Ask Garage", persistence: persistence)

        let garageAfterClear = try userTexts("Ask Garage", persistence: persistence)
        XCTAssertTrue(garageAfterClear.isEmpty)
        let pantry = try userTexts("Ask Pantry", persistence: persistence)
        XCTAssertEqual(pantry, ["What's for dinner?"])

        let memory = try makeAssistant(name: "Ask Garage", persistence: .memory)
        XCTAssertTrue(try memory.transcript().isEmpty)
    }

    private func ask(_ name: String, chip: AskChip, persistence: AskPersistence) async throws {
        let assistant = try makeAssistant(name: name, persistence: persistence)
        _ = await assistant.handle(chip: chip)
    }

    private func userTexts(_ name: String, persistence: AskPersistence) throws -> [String] {
        let assistant = try makeAssistant(name: name, persistence: persistence)
        return try assistant.transcript().filter { $0.role == "user" }.map(\.text)
    }

    private func clear(_ name: String, persistence: AskPersistence) throws {
        let assistant = try makeAssistant(name: name, persistence: persistence)
        try assistant.clearThread()
    }

    private func makeAssistant(name: String, persistence: AskPersistence) throws -> AskAssistant {
        try AskAssistant(AskConfiguration(
            assistantName: name,
            persistence: persistence,
            domains: [AskDomain(id: "sample", summary: "Sample", routingNotes: "The sample.")],
            skills: [
                AskSkill(
                    id: "charge",
                    domainID: "sample",
                    title: "Charge",
                    summary: "Battery",
                    routingNotes: "Battery.",
                    fulfillment: .reply { _ in AskReply(text: "68 percent.", spoken: "68 percent.") }
                ),
                AskSkill(
                    id: "dinner",
                    domainID: "sample",
                    title: "Dinner",
                    summary: "Dinner",
                    routingNotes: "Dinner.",
                    fulfillment: .reply { _ in AskReply(text: "Pasta.", spoken: "Pasta.") }
                )
            ],
            context: { AskContext() },
            chips: { _ in [] }
        ))
    }
}

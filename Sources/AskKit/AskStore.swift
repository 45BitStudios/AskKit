import Foundation
import SwiftData

/// Where conversation turns live. One schema, three stores.
public enum AskPersistence {
    /// Process memory. Previews and tests.
    case memory
    /// A local SwiftData store. No iCloud.
    case swiftData(storeURL: URL?)
    /// The same SwiftData models, mirrored to the user's private CloudKit database.
    case privateCloud(containerIdentifier: String, storeURL: URL?)
    /// An app-owned container that already includes ``AskThread`` and ``AskTurnRecord``.
    case container(ModelContainer)
}

public enum AskSchema {
    public static let schema = Schema([AskThread.self, AskTurnRecord.self])
}

public enum AskStoreBuilder {
    /// The configuration Ask will open. `.container` returns nil because the app already opened one.
    public static func modelConfiguration(for persistence: AskPersistence) -> ModelConfiguration? {
        switch persistence {
        case .memory:
            return ModelConfiguration(
                "AskKit",
                schema: AskSchema.schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        case .swiftData(let storeURL):
            return configuration(storeURL: storeURL, cloudKitDatabase: .none)
        case .privateCloud(let containerIdentifier, let storeURL):
            return configuration(storeURL: storeURL, cloudKitDatabase: .private(containerIdentifier))
        case .container:
            return nil
        }
    }

    private static func configuration(storeURL: URL?, cloudKitDatabase: ModelConfiguration.CloudKitDatabase) -> ModelConfiguration {
        if let storeURL {
            return ModelConfiguration(
                "AskKit",
                schema: AskSchema.schema,
                url: storeURL,
                cloudKitDatabase: cloudKitDatabase
            )
        }
        return ModelConfiguration(
            "AskKit",
            schema: AskSchema.schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitDatabase
        )
    }
}

@Model
public final class AskThread {
    public var id: UUID = UUID()
    public var assistantName: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \AskTurnRecord.thread)
    public var turns: [AskTurnRecord]? = []

    public init(id: UUID = UUID(), assistantName: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.assistantName = assistantName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.turns = []
    }
}

@Model
public final class AskTurnRecord {
    public var id: UUID = UUID()
    public var role: String = "user"
    public var text: String = ""
    public var spoken: String = ""
    public var skillID: String = ""
    public var domainID: String = ""
    public var slotsJSON: String = "{}"
    /// Item identifiers behind a search card, so the card can be drawn again. Nil for every other turn.
    public var searchItemIDsJSON: String?
    public var createdAt: Date = Date()
    public var thread: AskThread?

    public init(
        id: UUID = UUID(),
        role: String,
        text: String,
        spoken: String = "",
        skillID: String = "",
        domainID: String = "",
        slotsJSON: String = "{}",
        searchItemIDsJSON: String? = nil,
        createdAt: Date = Date(),
        thread: AskThread? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.spoken = spoken
        self.skillID = skillID
        self.domainID = domainID
        self.slotsJSON = slotsJSON
        self.searchItemIDsJSON = searchItemIDsJSON
        self.createdAt = createdAt
        self.thread = thread
    }
}

public struct AskTranscriptTurn: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var role: String
    public var text: String
    public var spoken: String
    public var skillID: String
    public var domainID: String
    public var slotsJSON: String
    /// Set only on a search card turn.
    public var searchItemIDs: [String]?
    public var createdAt: Date

    public init(
        id: UUID,
        role: String,
        text: String,
        spoken: String,
        skillID: String,
        domainID: String,
        slotsJSON: String,
        searchItemIDs: [String]? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.spoken = spoken
        self.skillID = skillID
        self.domainID = domainID
        self.slotsJSON = slotsJSON
        self.searchItemIDs = searchItemIDs
        self.createdAt = createdAt
    }
}

enum AskSlots {
    static func json(_ slots: [String: String], omitting keys: Set<String>) -> String {
        let kept = slots.filter { !keys.contains($0.key) && !$0.value.isEmpty }
        guard JSONSerialization.isValidJSONObject(kept),
              let data = try? JSONSerialization.data(withJSONObject: kept, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    static func decode(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return object
    }

    static func idsJSON(_ ids: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ids),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    static func decodeIDs(_ json: String?) -> [String]? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String]
    }

    static func hasValues(_ slots: [String: String], for required: [String]) -> Bool {
        required.allSatisfy { key in
            !(slots[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    static func merging(_ filled: [String: String], into slots: [String: String]) -> [String: String] {
        var merged = slots
        for (key, value) in filled where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let existing = merged[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if existing.isEmpty {
                merged[key] = value
            }
        }
        return merged
    }
}

@MainActor
final class AskStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(persistence: AskPersistence) throws {
        switch persistence {
        case .container(let existing):
            container = existing
        default:
            guard let configuration = AskStoreBuilder.modelConfiguration(for: persistence) else {
                throw AskStoreError.missingConfiguration
            }
            container = try ModelContainer(for: AskSchema.schema, configurations: [configuration])
        }
    }

    func appendUser(assistantName: String, text: String) throws {
        let thread = try thread(named: assistantName)
        let turn = AskTurnRecord(role: "user", text: text, thread: thread)
        context.insert(turn)
        thread.updatedAt = Date()
        try context.save()
    }

    @discardableResult
    func appendAssistant(
        assistantName: String,
        text: String,
        spoken: String,
        skillID: String,
        domainID: String,
        slots: [String: String],
        omitting keys: Set<String>,
        searchItemIDs: [String]? = nil
    ) throws -> UUID {
        let thread = try thread(named: assistantName)
        let turn = AskTurnRecord(
            role: "assistant",
            text: text,
            spoken: spoken,
            skillID: skillID,
            domainID: domainID,
            slotsJSON: AskSlots.json(slots, omitting: keys),
            searchItemIDsJSON: searchItemIDs.map(AskSlots.idsJSON),
            thread: thread
        )
        context.insert(turn)
        thread.updatedAt = Date()
        try context.save()
        return turn.id
    }

    func recentUserTexts(assistantName: String, limit: Int = 8) throws -> [String] {
        guard let thread = try existingThread(named: assistantName) else { return [] }
        let texts = (thread.turns ?? [])
            .filter { $0.role == "user" }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.text)
        return Array(texts.suffix(limit))
    }

    func transcript(assistantName: String) throws -> [AskTranscriptTurn] {
        guard let thread = try existingThread(named: assistantName) else { return [] }
        return (thread.turns ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map { turn in
                AskTranscriptTurn(
                    id: turn.id,
                    role: turn.role,
                    text: turn.text,
                    spoken: turn.spoken,
                    skillID: turn.skillID,
                    domainID: turn.domainID,
                    slotsJSON: turn.slotsJSON,
                    searchItemIDs: AskSlots.decodeIDs(turn.searchItemIDsJSON),
                    createdAt: turn.createdAt
                )
            }
    }

    func clear(assistantName: String) throws {
        guard let thread = try existingThread(named: assistantName) else { return }
        context.delete(thread)
        try context.save()
    }

    private func thread(named name: String) throws -> AskThread {
        if let existing = try existingThread(named: name) {
            return existing
        }
        let created = AskThread(assistantName: name)
        context.insert(created)
        try context.save()
        return created
    }

    private func existingThread(named name: String) throws -> AskThread? {
        let descriptor = FetchDescriptor<AskThread>()
        return try context.fetch(descriptor).first { $0.assistantName == name }
    }
}

enum AskStoreError: Error {
    case missingConfiguration
}

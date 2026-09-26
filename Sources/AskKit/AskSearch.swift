import CoreSpotlight
import Foundation
import FoundationModels
import Synchronization

/// One item the search tool returned from the app's Core Spotlight index.
public struct AskSearchItem: Sendable, Equatable, Identifiable {
    /// The `CSSearchableItem.uniqueIdentifier` the app donated.
    public var id: String
    public var domainIdentifier: String?
    public var title: String?
    public var contentDescription: String?

    public init(id: String, domainIdentifier: String? = nil, title: String? = nil, contentDescription: String? = nil) {
        self.id = id
        self.domainIdentifier = domainIdentifier
        self.title = title
        self.contentDescription = contentDescription
    }

    public init(_ item: CSSearchableItem) {
        self.init(
            id: item.uniqueIdentifier,
            domainIdentifier: item.domainIdentifier,
            title: item.attributeSet.title,
            contentDescription: item.attributeSet.contentDescription
        )
    }
}

/// What one search session found.
public struct AskSearchResult: Sendable, Equatable {
    /// The model's answer, written from the search results. Empty when the search could not run.
    public var answer: String
    /// Every item the tool returned this turn, in order, without duplicates.
    public var items: [AskSearchItem]
    /// Set when the model asked Spotlight for a count instead of items.
    public var count: Int?

    public init(answer: String, items: [AskSearchItem] = [], count: Int? = nil) {
        self.answer = answer
        self.items = items
        self.count = count
    }
}

/// A skill answered from the app's Core Spotlight index.
///
/// Ask opens one session that carries only the search tool. The model searches, answers from what it found,
/// and `render` turns that into a reply or a card.
public struct AskSearchSkill {
    /// Built once per turn. The default uses focused guidance, which suits the on-device context size.
    public var makeTool: @MainActor () -> SpotlightSearchTool
    /// Added to Ask's search instructions. Say what the index holds and which attributes matter.
    public var instructions: String
    /// Draws the turn. Also called when a saved card is shown again, with `answer` set to the saved spoken text.
    public var render: @MainActor (AskInvocation, AskSearchResult) async -> AskTurnFulfillment
    /// Rebuilds items from saved identifiers when a card is shown again.
    /// Only identifiers are saved. When this is nil, replayed items carry only `id`.
    public var restore: (@MainActor ([String]) async -> [AskSearchItem])?

    public init(
        makeTool: @escaping @MainActor () -> SpotlightSearchTool = AskSearchSkill.focusedTool,
        instructions: String = "",
        restore: (@MainActor ([String]) async -> [AskSearchItem])? = nil,
        render: @escaping @MainActor (AskInvocation, AskSearchResult) async -> AskTurnFulfillment
    ) {
        self.makeTool = makeTool
        self.instructions = instructions
        self.restore = restore
        self.render = render
    }

    @MainActor
    public static func focusedTool() -> SpotlightSearchTool {
        SpotlightSearchTool(configuration: .init(guide: .init(level: .focused(.items))))
    }
}

/// Collects the tool's partial replies while the session runs.
final class AskSearchCollector: Sendable {
    private struct State {
        var items: [AskSearchItem] = []
        var seen: Set<String> = []
        var count: Int?
    }

    private let state = Mutex(State())

    func append(_ items: [AskSearchItem]) {
        state.withLock { state in
            for item in items where state.seen.insert(item.id).inserted {
                state.items.append(item)
            }
        }
    }

    func setCount(_ count: Int) {
        state.withLock { $0.count = count }
    }

    func result(answer: String) -> AskSearchResult {
        state.withLock { AskSearchResult(answer: answer, items: $0.items, count: $0.count) }
    }
}

extension AskFoundationSessions {
    static func search(_ request: AskModelRequest, tool: SpotlightSearchTool) async throws -> AskSearchResult {
        let collector = AskSearchCollector()
        let listener = Task {
            for await reply in tool.searchResults {
                switch reply.content {
                case .items(let items):
                    collector.append(items.map(AskSearchItem.init))
                case .count(let count):
                    collector.setCount(count)
                default:
                    continue
                }
            }
        }
        defer { listener.cancel() }
        let session = LanguageModelSession(
            profile: AskSkillProfile(instructions: request.instructions, tools: [tool])
        )
        let response = try await session.respond(to: request.prompt)
        // The tool has finished by now. Let the listener drain what it already yielded.
        await Task.yield()
        return collector.result(answer: response.content)
    }
}

extension AskPrompts {
    static func searchInstructions(assistantName: String, skill: AskSkill, notes: String) -> String {
        let extra = notes.isEmpty ? "" : "\n\(notes)"
        return """
        You are \(assistantName). \(skill.summary).
        Search the app's index with the tool, then answer in one or two sentences.
        Use only what the search returned. If it found nothing, say so. Do not invent facts.\(extra)
        """
    }
}

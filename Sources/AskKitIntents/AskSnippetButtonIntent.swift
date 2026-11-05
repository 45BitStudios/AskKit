import AppIntents
import AskKit

extension AskSnippetActionError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        "That card action is not available."
    }
}

enum AskSnippetIntentRunner {
    static func perform(entityType: String, entityID: String, actionID: String, role: String) async throws {
        try await AskSnippetActionCenter.shared.perform(
            AskSnippetActionRequest(
                entityType: entityType,
                entityID: entityID,
                actionID: actionID,
                intentRole: role
            )
        )
    }
}

/// Favorite, remind, and custom buttons on an entity card.
///
/// Hidden from Shortcuts. A dialog would open a second window on top of the card, so this only runs the handler.
/// Register the handler on ``AskSnippetActionCenter``.
public struct AskSnippetButtonIntent: AppIntent {
    public static let title: LocalizedStringResource = "Entity Action"
    public static let description = IntentDescription("Runs a button on an entity card.")
    public static let isDiscoverable = false

    public static var supportedModes: IntentModes { .background }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Entity Type")
    public var entityType: String

    @Parameter(title: "Entity")
    public var entityID: String

    @Parameter(title: "Action")
    public var actionID: String

    @Parameter(title: "Role")
    public var role: String

    public init() {
        entityType = ""
        entityID = ""
        actionID = ""
        role = AskSnippetActionRole.custom.rawValue
    }

    public init(request: AskSnippetActionRequest) {
        entityType = request.entityType
        entityID = request.entityID
        actionID = request.actionID
        role = request.role.rawValue
    }

    public func perform() async throws -> some IntentResult {
        try await AskSnippetIntentRunner.perform(
            entityType: entityType,
            entityID: entityID,
            actionID: actionID,
            role: role
        )
        return .result()
    }
}

/// The open button on an entity card. Brings the app forward, then runs the same handler.
///
/// Hidden from Shortcuts. The handler reads `request.role == .open`.
public struct AskSnippetOpenIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Entity"
    public static let description = IntentDescription("Opens an entity from its card.")
    public static let isDiscoverable = false
    public static let openAppWhenRun = true

    public static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Entity Type")
    public var entityType: String

    @Parameter(title: "Entity")
    public var entityID: String

    @Parameter(title: "Action")
    public var actionID: String

    @Parameter(title: "Role")
    public var role: String

    public init() {
        entityType = ""
        entityID = ""
        actionID = ""
        role = AskSnippetActionRole.open.rawValue
    }

    public init(request: AskSnippetActionRequest) {
        entityType = request.entityType
        entityID = request.entityID
        actionID = request.actionID
        role = request.role.rawValue
    }

    public func perform() async throws -> some IntentResult {
        try await AskSnippetIntentRunner.perform(
            entityType: entityType,
            entityID: entityID,
            actionID: actionID,
            role: role
        )
        return .result()
    }
}

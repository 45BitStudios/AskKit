import Foundation
import os

/// How many rows, fields, and buttons a Siri entity card keeps.
public enum AskSnippetLimits {
    /// Favorite, remind, and open. A fourth action is left off.
    public static let actions = 3
    /// Primary fields kept when the card is compact.
    public static let compactPrimaryFields = 2
    /// Rows kept when a list card is compact.
    public static let compactListRows = 2
}

/// The three cards ConferenceKit drew for a session, a schedule, and a compact row.
public enum AskSnippetShape: String, Sendable, Equatable, Hashable, CaseIterable {
    /// Title, subtitle, fields, an optional image, and up to three actions.
    case detail
    /// A heading plus rows. My Schedule is this shape.
    case list
    /// One line: a symbol, a title, and a subtitle. No actions.
    case row
}

/// Standard is the Siri card. Compact is every other family, and the row shape.
public enum AskSnippetDensity: String, Sendable, Equatable, Hashable {
    case standard
    case compact
}

/// `CardSnippetFamily` is a struct. The bridge compares it with `==` and stores the result here.
public enum AskSnippetFamily: String, Sendable, Equatable, Hashable {
    case standard
    /// Anything other than `CardSnippetFamily.standard`.
    case other

    public var density: AskSnippetDensity {
        self == .standard ? .standard : .compact
    }

    public init(isStandardFamily: Bool) {
        self = isStandardFamily ? .standard : .other
    }
}

/// A color the card can draw without SwiftUI. Components stay in 0...1.
public struct AskSnippetAccent: Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
        self.opacity = Self.unit(opacity)
    }

    public static let indigo = AskSnippetAccent(red: 0.345, green: 0.337, blue: 0.839)
    public static let orange = AskSnippetAccent(red: 1, green: 0.584, blue: 0)
    public static let blue = AskSnippetAccent(red: 0, green: 0.478, blue: 1)
    public static let green = AskSnippetAccent(red: 0.204, green: 0.780, blue: 0.349)
    public static let pink = AskSnippetAccent(red: 1, green: 0.176, blue: 0.333)
    public static let teal = AskSnippetAccent(red: 0.188, green: 0.690, blue: 0.780)

    /// A known name, or indigo when the name is not one of the presets.
    public static func named(_ name: String) -> AskSnippetAccent {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "orange": .orange
        case "blue": .blue
        case "green": .green
        case "pink": .pink
        case "teal": .teal
        case "indigo": .indigo
        default: .indigo
        }
    }

    public var name: String {
        if self == .indigo { return "indigo" }
        if self == .orange { return "orange" }
        if self == .blue { return "blue" }
        if self == .green { return "green" }
        if self == .pink { return "pink" }
        if self == .teal { return "teal" }
        return "custom"
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return value > 0 ? 1 : 0 }
        return min(max(value, 0), 1)
    }
}

/// Primary fields stay on a compact detail card. Secondary fields are the extra lines.
public enum AskSnippetFieldRank: String, Sendable, Equatable, Hashable {
    case primary
    case secondary
}

/// One labeled fact on a detail card.
public struct AskSnippetField: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var value: String
    public var symbolName: String?
    public var rank: AskSnippetFieldRank

    public init(
        id: String,
        title: String,
        value: String,
        symbolName: String? = nil,
        rank: AskSnippetFieldRank = .primary
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.symbolName = symbolName
        self.rank = rank
    }
}

/// One line in a list card.
public struct AskSnippetRow: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var symbolName: String?

    public init(id: String, title: String, subtitle: String? = nil, symbolName: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
    }
}

/// What a card button asks the app to do.
public enum AskSnippetActionRole: String, Sendable, Equatable, Hashable, CaseIterable {
    case favorite
    case remind
    case open
    case custom

    /// The SF Symbol used when the action does not name one.
    public var defaultSymbolName: String {
        switch self {
        case .favorite: "star"
        case .remind: "bell"
        case .open: "arrow.up.forward"
        case .custom: "circle"
        }
    }

    /// The role stored on the button intent. An unknown string is `.custom`.
    public init(intentValue: String) {
        self = Self(rawValue: intentValue) ?? .custom
    }
}

/// A button on the card. At most three survive on the snippet.
public struct AskSnippetAction: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var symbolName: String?
    public var role: AskSnippetActionRole

    public init(
        id: String,
        title: String,
        symbolName: String? = nil,
        role: AskSnippetActionRole = .custom
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.role = role
    }

    public static func favorite(
        id: String = "favorite",
        title: String = "Favorite",
        symbolName: String = "star"
    ) -> AskSnippetAction {
        AskSnippetAction(id: id, title: title, symbolName: symbolName, role: .favorite)
    }

    public static func remind(
        id: String = "remind",
        title: String = "Remind",
        symbolName: String = "bell"
    ) -> AskSnippetAction {
        AskSnippetAction(id: id, title: title, symbolName: symbolName, role: .remind)
    }

    public static func open(
        id: String = "open",
        title: String = "Open",
        symbolName: String = "arrow.up.forward"
    ) -> AskSnippetAction {
        AskSnippetAction(id: id, title: title, symbolName: symbolName, role: .open)
    }

    /// The symbol the button draws.
    public var resolvedSymbolName: String {
        let trimmed = symbolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? role.defaultSymbolName : trimmed
    }
}

/// The card an app describes. Siri does not see this value. ``AskSnippetCard`` is the mapped card.
///
/// Leave `entityType` and `entityID` empty when the entity conforms to `AskSnippetEntity`.
/// The bridge fills the type from `String(reflecting:)` and the id from `String(describing:)` of the entity id.
public struct AskEntitySnippet: Sendable, Equatable {
    public var shape: AskSnippetShape
    public var entityType: String
    public var entityID: String
    public var title: String
    public var subtitle: String?
    public var fields: [AskSnippetField]
    public var rows: [AskSnippetRow]
    public var symbolName: String?
    public var imageName: String?
    public var accent: AskSnippetAccent
    public var actions: [AskSnippetAction]

    public init(
        shape: AskSnippetShape,
        entityType: String = "",
        entityID: String = "",
        title: String,
        subtitle: String? = nil,
        fields: [AskSnippetField] = [],
        rows: [AskSnippetRow] = [],
        symbolName: String? = nil,
        imageName: String? = nil,
        accent: AskSnippetAccent = .indigo,
        actions: [AskSnippetAction] = []
    ) {
        let cleaned = Self.clean(
            shape: shape,
            entityType: entityType,
            entityID: entityID,
            title: title,
            subtitle: subtitle,
            fields: fields,
            rows: rows,
            symbolName: symbolName,
            imageName: imageName,
            accent: accent,
            actions: actions
        )
        self.shape = cleaned.shape
        self.entityType = cleaned.entityType
        self.entityID = cleaned.entityID
        self.title = cleaned.title
        self.subtitle = cleaned.subtitle
        self.fields = cleaned.fields
        self.rows = cleaned.rows
        self.symbolName = cleaned.symbolName
        self.imageName = cleaned.imageName
        self.accent = cleaned.accent
        self.actions = cleaned.actions
    }

    /// Title, fields, an optional image or symbol, and up to three actions.
    public static func detail(
        entityType: String = "",
        entityID: String = "",
        title: String,
        subtitle: String? = nil,
        fields: [AskSnippetField] = [],
        symbolName: String? = nil,
        imageName: String? = nil,
        accent: AskSnippetAccent = .indigo,
        actions: [AskSnippetAction] = []
    ) -> AskEntitySnippet {
        AskEntitySnippet(
            shape: .detail,
            entityType: entityType,
            entityID: entityID,
            title: title,
            subtitle: subtitle,
            fields: fields,
            symbolName: symbolName,
            imageName: imageName,
            accent: accent,
            actions: actions
        )
    }

    /// A heading and rows. Pass an empty subtitle such as "Nothing saved yet." when the list is empty.
    public static func list(
        entityType: String = "",
        entityID: String = "",
        title: String,
        subtitle: String? = nil,
        rows: [AskSnippetRow] = [],
        symbolName: String? = nil,
        accent: AskSnippetAccent = .indigo,
        actions: [AskSnippetAction] = []
    ) -> AskEntitySnippet {
        AskEntitySnippet(
            shape: .list,
            entityType: entityType,
            entityID: entityID,
            title: title,
            subtitle: subtitle,
            rows: rows,
            symbolName: symbolName,
            accent: accent,
            actions: actions
        )
    }

    /// One compact line. Fields, rows, images, and actions are dropped.
    public static func row(
        entityType: String = "",
        entityID: String = "",
        title: String,
        subtitle: String? = nil,
        symbolName: String? = nil,
        accent: AskSnippetAccent = .indigo
    ) -> AskEntitySnippet {
        AskEntitySnippet(
            shape: .row,
            entityType: entityType,
            entityID: entityID,
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            accent: accent
        )
    }

    /// Fills a blank type or id. A value the app already set is kept.
    public func stamped(entityType: String, entityID: String) -> AskEntitySnippet {
        var copy = self
        if Self.blank(copy.entityType), !Self.blank(entityType) {
            copy.entityType = entityType.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if Self.blank(copy.entityID), !Self.blank(entityID) {
            copy.entityID = entityID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return copy
    }

    /// Runs the same cleanup as the initializer. ``AskSnippetCard/make(from:density:)`` calls this.
    public func normalized() -> AskEntitySnippet {
        AskEntitySnippet(
            shape: shape,
            entityType: entityType,
            entityID: entityID,
            title: title,
            subtitle: subtitle,
            fields: fields,
            rows: rows,
            symbolName: symbolName,
            imageName: imageName,
            accent: accent,
            actions: actions
        )
    }

    private struct Cleaned {
        var shape: AskSnippetShape
        var entityType: String
        var entityID: String
        var title: String
        var subtitle: String?
        var fields: [AskSnippetField]
        var rows: [AskSnippetRow]
        var symbolName: String?
        var imageName: String?
        var accent: AskSnippetAccent
        var actions: [AskSnippetAction]
    }

    private static func clean(
        shape: AskSnippetShape,
        entityType: String,
        entityID: String,
        title: String,
        subtitle: String?,
        fields: [AskSnippetField],
        rows: [AskSnippetRow],
        symbolName: String?,
        imageName: String?,
        accent: AskSnippetAccent,
        actions: [AskSnippetAction]
    ) -> Cleaned {
        let keptFields = shape == .detail ? cleanedFields(fields) : []
        let keptRows = shape == .list ? cleanedRows(rows) : []
        let keptActions = shape == .row ? [] : cleanedActions(actions)
        let keptImage = shape == .detail ? optionalText(imageName) : nil
        return Cleaned(
            shape: shape,
            entityType: entityType.trimmingCharacters(in: .whitespacesAndNewlines),
            entityID: entityID.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: optionalText(subtitle),
            fields: keptFields,
            rows: keptRows,
            symbolName: optionalText(symbolName),
            imageName: keptImage,
            accent: accent,
            actions: keptActions
        )
    }

    private static func cleanedFields(_ fields: [AskSnippetField]) -> [AskSnippetField] {
        var seen = Set<String>()
        var kept: [AskSnippetField] = []
        for field in fields {
            let id = field.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !value.isEmpty, seen.insert(id).inserted else { continue }
            kept.append(AskSnippetField(
                id: id,
                title: field.title.trimmingCharacters(in: .whitespacesAndNewlines),
                value: value,
                symbolName: optionalText(field.symbolName),
                rank: field.rank
            ))
        }
        return kept
    }

    private static func cleanedRows(_ rows: [AskSnippetRow]) -> [AskSnippetRow] {
        var seen = Set<String>()
        var kept: [AskSnippetRow] = []
        for row in rows {
            let id = row.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { continue }
            kept.append(AskSnippetRow(
                id: id,
                title: title,
                subtitle: optionalText(row.subtitle),
                symbolName: optionalText(row.symbolName)
            ))
        }
        return kept
    }

    private static func cleanedActions(_ actions: [AskSnippetAction]) -> [AskSnippetAction] {
        var seen = Set<String>()
        var kept: [AskSnippetAction] = []
        for action in actions {
            let id = action.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { continue }
            kept.append(AskSnippetAction(
                id: id,
                title: title,
                symbolName: optionalText(action.symbolName),
                role: action.role
            ))
            if kept.count == AskSnippetLimits.actions { break }
        }
        return kept
    }

    private static func optionalText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func blank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The card Siri is asked to draw. Built from an ``AskEntitySnippet`` and a density.
public struct AskSnippetCard: Sendable, Equatable {
    public var shape: AskSnippetShape
    public var density: AskSnippetDensity
    public var entityType: String
    public var entityID: String
    public var title: String
    public var subtitle: String?
    public var primaryFields: [AskSnippetField]
    public var secondaryFields: [AskSnippetField]
    public var rows: [AskSnippetRow]
    public var symbolName: String?
    public var imageName: String?
    public var showsImage: Bool
    public var accent: AskSnippetAccent
    public var actions: [AskSnippetAction]
    public var showsActions: Bool
    public var titleLineLimit: Int
    public var subtitleLineLimit: Int
    public var bodyLineLimit: Int
    public var accessibilityText: String

    /// The requests the visible buttons send. Empty when the card hides its actions.
    public var actionRequests: [AskSnippetActionRequest] {
        guard showsActions else { return [] }
        return actions.map {
            AskSnippetActionRequest(entityType: entityType, entityID: entityID, actionID: $0.id, role: $0.role)
        }
    }

    /// Maps a descriptor onto one card.
    ///
    /// A standard detail card keeps every field, the image, and the actions.
    /// A compact detail card keeps two primary fields and hides the image, the secondary lines, and the buttons.
    /// A standard list keeps every row. A compact list keeps two.
    /// A row is always compact and never shows buttons.
    public static func make(from snippet: AskEntitySnippet, density: AskSnippetDensity) -> AskSnippetCard {
        let source = snippet.normalized()
        switch source.shape {
        case .row:
            return card(
                source: source,
                density: .compact,
                primary: [],
                secondary: [],
                rows: [],
                imageName: nil,
                showsImage: false,
                actions: [],
                showsActions: false,
                titleLineLimit: 1,
                subtitleLineLimit: 1,
                bodyLineLimit: 1
            )
        case .detail:
            let primary = source.fields.filter { $0.rank == .primary }
            let secondary = source.fields.filter { $0.rank == .secondary }
            if density == .compact {
                return card(
                    source: source,
                    density: .compact,
                    primary: Array(primary.prefix(AskSnippetLimits.compactPrimaryFields)),
                    secondary: [],
                    rows: [],
                    imageName: nil,
                    showsImage: false,
                    actions: [],
                    showsActions: false,
                    titleLineLimit: 2,
                    subtitleLineLimit: 1,
                    bodyLineLimit: 1
                )
            }
            return card(
                source: source,
                density: .standard,
                primary: primary,
                secondary: secondary,
                rows: [],
                imageName: source.imageName,
                showsImage: source.imageName != nil,
                actions: source.actions,
                showsActions: !source.actions.isEmpty,
                titleLineLimit: 3,
                subtitleLineLimit: 2,
                bodyLineLimit: 3
            )
        case .list:
            if density == .compact {
                return card(
                    source: source,
                    density: .compact,
                    primary: [],
                    secondary: [],
                    rows: Array(source.rows.prefix(AskSnippetLimits.compactListRows)),
                    imageName: nil,
                    showsImage: false,
                    actions: [],
                    showsActions: false,
                    titleLineLimit: 1,
                    subtitleLineLimit: 1,
                    bodyLineLimit: 1
                )
            }
            return card(
                source: source,
                density: .standard,
                primary: [],
                secondary: [],
                rows: source.rows,
                imageName: nil,
                showsImage: false,
                actions: source.actions,
                showsActions: !source.actions.isEmpty,
                titleLineLimit: 2,
                subtitleLineLimit: 2,
                bodyLineLimit: 2
            )
        }
    }

    private static func card(
        source: AskEntitySnippet,
        density: AskSnippetDensity,
        primary: [AskSnippetField],
        secondary: [AskSnippetField],
        rows: [AskSnippetRow],
        imageName: String?,
        showsImage: Bool,
        actions: [AskSnippetAction],
        showsActions: Bool,
        titleLineLimit: Int,
        subtitleLineLimit: Int,
        bodyLineLimit: Int
    ) -> AskSnippetCard {
        let built = AskSnippetCard(
            shape: source.shape,
            density: density,
            entityType: source.entityType,
            entityID: source.entityID,
            title: source.title,
            subtitle: source.subtitle,
            primaryFields: primary,
            secondaryFields: secondary,
            rows: rows,
            symbolName: source.symbolName,
            imageName: imageName,
            showsImage: showsImage,
            accent: source.accent,
            actions: showsActions ? actions : [],
            showsActions: showsActions,
            titleLineLimit: titleLineLimit,
            subtitleLineLimit: subtitleLineLimit,
            bodyLineLimit: bodyLineLimit,
            accessibilityText: ""
        )
        var copy = built
        copy.accessibilityText = accessibilityText(for: copy)
        return copy
    }

    private static func accessibilityText(for card: AskSnippetCard) -> String {
        var lines: [String] = []
        if !card.title.isEmpty { lines.append(card.title) }
        if let subtitle = card.subtitle, !subtitle.isEmpty { lines.append(subtitle) }
        for field in card.primaryFields + card.secondaryFields {
            if field.title.isEmpty {
                lines.append(field.value)
            } else {
                lines.append("\(field.title) \(field.value)")
            }
        }
        for row in card.rows {
            if let subtitle = row.subtitle, !subtitle.isEmpty {
                lines.append("\(row.title) \(subtitle)")
            } else {
                lines.append(row.title)
            }
        }
        if card.showsActions {
            lines.append(contentsOf: card.actions.map(\.title))
        }
        return lines.joined(separator: "\n")
    }
}

/// One button press. The id is what the app registered, not a Siri-only token.
public struct AskSnippetActionRequest: Sendable, Equatable, Hashable {
    public var entityType: String
    public var entityID: String
    public var actionID: String
    public var role: AskSnippetActionRole

    public init(entityType: String, entityID: String, actionID: String, role: AskSnippetActionRole) {
        self.entityType = entityType.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entityID = entityID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.actionID = actionID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.role = role
    }

    /// Builds the request a button intent sends. An unknown role string is `.custom`.
    public init(entityType: String, entityID: String, actionID: String, intentRole: String) {
        self.init(
            entityType: entityType,
            entityID: entityID,
            actionID: actionID,
            role: AskSnippetActionRole(intentValue: intentRole)
        )
    }
}

/// No handler is registered for that entity type.
public struct AskSnippetActionError: Error, Equatable, Sendable {
    public var entityType: String
    public var actionID: String

    public init(entityType: String, actionID: String) {
        self.entityType = entityType
        self.actionID = actionID
    }
}

/// Handlers for the buttons on an entity card.
///
/// Register from `App.init`, the same place as the ask intent client.
/// A shortcut can launch the process before any view appears.
/// The card closure only reads the entity. This handler runs later, when the button is pressed.
public final class AskSnippetActionCenter: @unchecked Sendable {
    public static let shared = AskSnippetActionCenter()

    private typealias Handler = @Sendable (AskSnippetActionRequest) async throws -> Void
    private let handlers = OSAllocatedUnfairLock(initialState: [String: Handler]())

    public init() {}

    /// Replaces a handler already stored for this type name.
    /// A blank type name is ignored.
    public func register(
        entityType: String,
        handler: @escaping @Sendable (AskSnippetActionRequest) async throws -> Void
    ) {
        let key = entityType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        handlers.withLock { $0[key] = handler }
    }

    public func remove(entityType: String) {
        let key = entityType.trimmingCharacters(in: .whitespacesAndNewlines)
        handlers.withLock { $0.removeValue(forKey: key) }
    }

    public func removeAll() {
        handlers.withLock { $0.removeAll() }
    }

    public func perform(_ request: AskSnippetActionRequest) async throws {
        let handler = handlers.withLock { $0[request.entityType] }
        guard let handler else {
            throw AskSnippetActionError(entityType: request.entityType, actionID: request.actionID)
        }
        try await handler(request)
    }
}

import AppIntents
import CoreTransferable
import Foundation

/// Typed facts an Ask answer can hand to Shortcuts and other App Intents.
@UnionValue
public enum AskOutput: Sendable, Equatable {
    case place(AskPlaceEntity)
    case contact(AskContactEntity)
    case reminder(AskReminderEntity)
    case music(AskMusicItemEntity)
    case text(String)
}

/// A place from a location answer. Shortcuts can pass this to Get Directions.
public struct AskPlaceEntity: AppEntity, Sendable, Equatable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Place")
    public static let defaultQuery = AskPlaceQueryEntity()

    public var id: String

    @Property(title: "Name")
    public var name: String

    @Property(title: "Latitude")
    public var latitude: Double

    @Property(title: "Longitude")
    public var longitude: Double

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public init(id: String = UUID().uuidString, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    init(place: AskLocationPin.Place) {
        self.init(id: place.id, name: place.shortName.isEmpty ? place.label : place.shortName, latitude: place.latitude, longitude: place.longitude)
    }

    /// `@Property` stores an `EntityProperty`, which is a class and is not `Equatable`.
    public static func == (lhs: AskPlaceEntity, rhs: AskPlaceEntity) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension AskPlaceEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.name)
    }
}

public struct AskPlaceQueryEntity: EntityQuery {
    public init() {}

    public func entities(for identifiers: [AskPlaceEntity.ID]) async throws -> [AskPlaceEntity] {
        []
    }

    public func suggestedEntities() async throws -> [AskPlaceEntity] {
        []
    }
}

/// A person from a contacts answer. Shortcuts can pass this to Call or Email.
public struct AskContactEntity: AppEntity, Sendable, Equatable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Contact")
    public static let defaultQuery = AskContactQueryEntity()

    public var id: String

    @Property(title: "Name")
    public var name: String

    @Property(title: "Phone")
    public var phone: String

    @Property(title: "Email")
    public var email: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public init(id: String = UUID().uuidString, name: String, phone: String = "", email: String = "") {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
    }

    init(person: AskContactLine.Person) {
        self.init(name: person.name, phone: person.phone, email: person.email)
    }

    /// `@Property` stores an `EntityProperty`, which is a class and is not `Equatable`.
    public static func == (lhs: AskContactEntity, rhs: AskContactEntity) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.phone == rhs.phone && lhs.email == rhs.email
    }
}

extension AskContactEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.phone)
        ProxyRepresentation(exporting: \.email)
        ProxyRepresentation(exporting: \.name)
    }
}

public struct AskContactQueryEntity: EntityQuery {
    public init() {}

    public func entities(for identifiers: [AskContactEntity.ID]) async throws -> [AskContactEntity] {
        []
    }

    public func suggestedEntities() async throws -> [AskContactEntity] {
        []
    }
}

/// A song, album, or playlist from a music answer. Shortcuts can pass this to Play Music.
public struct AskMusicItemEntity: AppEntity, Sendable, Equatable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Music Item")
    public static let defaultQuery = AskMusicItemQueryEntity()

    public var id: String

    @Property(title: "Kind")
    public var kind: AskMusicKind

    @Property(title: "Title")
    public var itemTitle: String

    @Property(title: "Artist")
    public var artist: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(itemTitle)")
    }

    public init(id: String = UUID().uuidString, kind: AskMusicKind, title: String, artist: String = "") {
        self.id = id
        self.kind = kind
        self.itemTitle = title
        self.artist = artist
    }

    init(item: AskMusicLine.Item) {
        self.init(kind: item.musicKind, title: item.title, artist: item.artist)
    }

    /// `@Property` stores an `EntityProperty`, which is a class and is not `Equatable`.
    public static func == (lhs: AskMusicItemEntity, rhs: AskMusicItemEntity) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.itemTitle == rhs.itemTitle && lhs.artist == rhs.artist
    }
}

extension AskMusicItemEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.itemTitle)
    }
}

public struct AskMusicItemQueryEntity: EntityQuery {
    public init() {}

    public func entities(for identifiers: [AskMusicItemEntity.ID]) async throws -> [AskMusicItemEntity] {
        []
    }

    public func suggestedEntities() async throws -> [AskMusicItemEntity] {
        []
    }
}

extension AskReminderEntity: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.title)
    }
}

/// Maps a finished turn into typed outputs for Shortcuts chaining.
public enum AskAnswerExport {
    /// One output per structured Apple fact on the turn. Reply-only pages become `.text`.
    public static func outputs(from turn: AskTurnResult) -> [AskOutput] {
        let pages = AskIntentPresentation.pages(in: turn)
        var values: [AskOutput] = []
        var seen = Set<String>()

        for page in pages {
            let before = values.count
            if let reading = page.appleReading {
                values.append(contentsOf: outputs(from: reading, seen: &seen))
            }
            if values.count == before {
                let spoken = page.spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                let text = spoken.isEmpty
                    ? page.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    : spoken
                if !text.isEmpty {
                    let key = "text:\(text)"
                    if seen.insert(key).inserted {
                        values.append(.text(text))
                    }
                }
            }
        }

        if values.isEmpty {
            let spoken = pages
                .map { $0.spoken.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !spoken.isEmpty {
                values.append(.text(spoken))
            }
        }
        return values
    }

    static func outputs(from reading: AskAppleReading, seen: inout Set<String>) -> [AskOutput] {
        switch reading.name {
        case "location":
            return AskLocationPin.places(in: reading.lines).compactMap { place in
                let key = "place:\(place.id)"
                guard seen.insert(key).inserted else { return nil }
                return .place(AskPlaceEntity(place: place))
            }
        case "contacts":
            return reading.lines.compactMap { line in
                let person = AskContactLine.person(from: line)
                guard person.isPerson else { return nil }
                let key = "contact:\(person.name)|\(person.phone)|\(person.email)"
                guard seen.insert(key).inserted else { return nil }
                return .contact(AskContactEntity(person: person))
            }
        case "reminders":
            return AskReminderItem.tasks(in: reading.lines).compactMap { task in
                let key = "reminder:\(task.id)"
                guard seen.insert(key).inserted else { return nil }
                return .reminder(AskReminderEntity(id: task.id, title: task.title))
            }
        case "music":
            return reading.lines.compactMap { line in
                guard let item = AskMusicLine.item(from: line) else { return nil }
                let key = "music:\(item.kind)|\(item.title)|\(item.artist)"
                guard seen.insert(key).inserted else { return nil }
                return .music(AskMusicItemEntity(item: item))
            }
        default:
            let text = reading.lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !text.isEmpty else { return [] }
            let key = "text:\(reading.name):\(text)"
            guard seen.insert(key).inserted else { return [] }
            return [.text(text)]
        }
    }
}

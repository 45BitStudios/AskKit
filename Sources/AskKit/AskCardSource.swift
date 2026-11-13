import Foundation

/// Where a fact on a generative card came from.
/// A name such as Calendar, Health, or Weather, plus an optional http or https link.
public struct AskCardSource: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// Shown after "Source:" and used when ``id`` is left empty.
    public var name: String
    /// An http or https link. Any other scheme is dropped.
    public var url: URL?
    public var id: String

    public init(name: String, url: URL? = nil, id: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = Self.accepted(url)
        self.name = trimmedName
        self.url = link
        let trimmedID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedID.isEmpty || Self.rejects(id: trimmedID, name: trimmedName, original: url, accepted: link) {
            self.id = Self.makeID(name: trimmedName, url: link)
        } else {
            self.id = trimmedID
        }
    }

    /// How many sources one node keeps.
    public static let maximum = 4

    /// How many sources the card footer reads from the whole tree.
    public static let footerLimit = 6

    public static func makeID(name: String, url: URL?) -> String {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let url else { return key }
        return "\(key)|\(url.absoluteString)"
    }

    /// Drops empty names, non-http(s) links, and repeated ids. Keeps the first ``maximum``.
    public static func sanitized(_ sources: [AskCardSource], limit: Int = maximum) -> [AskCardSource] {
        var seen = Set<String>()
        var kept: [AskCardSource] = []
        for source in sources {
            let clean = AskCardSource(name: source.name, url: source.url, id: source.id)
            guard !clean.name.isEmpty else { continue }
            guard seen.insert(clean.id).inserted else { continue }
            kept.append(clean)
            if kept.count == limit { break }
        }
        return kept
    }

    /// http and https only. `javascript:`, file URLs, and strings that are not URLs are dropped.
    static func accepted(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        guard url.host != nil else { return nil }
        return url
    }

    /// An id minted from a rejected URL should not survive after that URL is dropped.
    private static func rejects(id: String, name: String, original: URL?, accepted: URL?) -> Bool {
        guard original != nil, accepted == nil else { return false }
        return id == makeID(name: name, url: original)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case url
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let url = try container.decodeIfPresent(URL.self, forKey: .url)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
        self.init(name: name, url: url, id: id)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let url {
            try container.encode(url, forKey: .url)
        }
        try container.encode(id, forKey: .id)
    }
}

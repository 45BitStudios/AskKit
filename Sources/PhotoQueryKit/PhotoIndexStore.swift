// Photos is not on Apple Watch, so this file builds empty there.
#if canImport(Photos)
import Foundation

/// On-device snapshot of the Vision photo index. Not CloudKit — Application Support only.
struct PhotoIndexSnapshot: Codable, Sendable, Equatable {
    var version: Int
    var lastIndexedAt: Date?
    var entries: [VisionIndexer.IndexEntry]

    static let currentVersion = 1

    init(version: Int = currentVersion, lastIndexedAt: Date? = nil, entries: [VisionIndexer.IndexEntry] = []) {
        self.version = version
        self.lastIndexedAt = lastIndexedAt
        self.entries = entries
    }
}

/// Loads and saves the Vision index under Application Support.
struct PhotoIndexStore: Sendable {
    var fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }
    }

    static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = root.appendingPathComponent("PhotoQueryKit", isDirectory: true)
        return folder.appendingPathComponent("vision-index.json", isDirectory: false)
    }

    func load() -> PhotoIndexSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PhotoIndexSnapshot()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try Self.makeDecoder().decode(PhotoIndexSnapshot.self, from: data)
            guard decoded.version <= PhotoIndexSnapshot.currentVersion else {
                return PhotoIndexSnapshot()
            }
            return decoded
        } catch {
            return PhotoIndexSnapshot()
        }
    }

    func save(_ snapshot: PhotoIndexSnapshot) throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(snapshot)
        let temp = fileURL.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: fileURL)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
#endif

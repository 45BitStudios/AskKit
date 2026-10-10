#if DEBUG
import Foundation
import os

/// Persists turns so a turn can still be inspected after the process ends.
/// One JSON file per turn. Newest `limit` kept.
public struct AskTraceStore: Sendable {
    var save: @Sendable (AskTraceTurn) -> Void
    var loadAll: @Sendable () -> [AskTraceTurn]
    var delete: @Sendable (UUID) -> Void
    var clear: @Sendable () -> Void
    var exportFile: @Sendable (AskTraceTurn) -> URL?
}

extension AskTraceStore {
    public static let defaultLimit = 20

    public static func cachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AskKitTraces", isDirectory: true)
    }

    public static func live(directory: URL? = nil, appGroup: String? = nil, limit: Int = defaultLimit) -> Self {
        let writing = directory ?? sharedDirectory(appGroup: appGroup) ?? cachesDirectory()
        let reading = readDirectories(writing: writing, appGroup: appGroup)
        return make(writing: writing, reading: reading, limit: limit)
    }

    public static func mock(turns: [AskTraceTurn] = []) -> Self {
        let box = OSAllocatedUnfairLock(initialState: turns)
        return Self(
            save: { turn in box.withLock { $0.insert(turn, at: 0) } },
            loadAll: { box.withLock { $0 } },
            delete: { id in box.withLock { $0.removeAll { $0.id == id } } },
            clear: { box.withLock { $0.removeAll() } },
            exportFile: { _ in nil }
        )
    }

    public static func failing() -> Self {
        Self(
            save: { _ in assertionFailure("AskTraceStore.save called") },
            loadAll: {
                assertionFailure("AskTraceStore.loadAll called")
                return []
            },
            delete: { _ in assertionFailure("AskTraceStore.delete called") },
            clear: { assertionFailure("AskTraceStore.clear called") },
            exportFile: { _ in
                assertionFailure("AskTraceStore.exportFile called")
                return nil
            }
        )
    }

    private static let logger = Logger(subsystem: "com.studio45.askkit", category: "AskTrace")

    static func fileName(for turn: AskTraceTurn) -> String {
        "\(Int64(turn.startedAt.timeIntervalSince1970 * 1000))-\(turn.id.uuidString).json"
    }

    /// The saved answer for this question closest to when the trace started.
    static func assistantTurn(matching question: String, near date: Date, turns: [AskTranscriptTurn]) -> UUID? {
        let needle = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        var best: (id: UUID, distance: TimeInterval)?
        for index in turns.indices {
            let turn = turns[index]
            guard turn.role == "assistant" else { continue }
            let asked = turns[..<index].last { $0.role == "user" }?.text
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard asked == needle else { continue }
            let distance = abs(turn.createdAt.timeIntervalSince(date))
            if best == nil || distance < best!.distance {
                best = (turn.id, distance)
            }
        }
        return best?.id
    }

    /// The trace for this question closest to when the answer was saved.
    static func match(question: String, near date: Date, turns: [AskTraceTurn]) -> UUID? {
        let needle = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return turns
            .filter { $0.question.trimmingCharacters(in: .whitespacesAndNewlines) == needle }
            .min { abs($0.startedAt.timeIntervalSince(date)) < abs($1.startedAt.timeIntervalSince(date)) }?
            .id
    }

    private static func sharedDirectory(appGroup: String?) -> URL? {
        guard let appGroup else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("AskKitTraces", isDirectory: true)
    }

    private static func readDirectories(writing: URL, appGroup: String?) -> [URL] {
        var directories = [writing]
        let caches = cachesDirectory()
        if directories[0] != caches {
            directories.append(caches)
        }
        if let shared = sharedDirectory(appGroup: appGroup), !directories.contains(shared) {
            directories.insert(shared, at: 0)
        }
        return directories
    }

    private static func make(writing: URL, reading: [URL], limit: Int) -> Self {
        @Sendable func files() -> [URL] {
            var byName: [String: URL] = [:]
            for directory in reading {
                let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                for url in urls where url.pathExtension == "json" && byName[url.lastPathComponent] == nil {
                    byName[url.lastPathComponent] = url
                }
            }
            return byName.values.sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        return Self(
            save: { turn in
                do {
                    try FileManager.default.createDirectory(at: writing, withIntermediateDirectories: true)
                    let data = try encoder(pretty: false).encode(turn)
                    try data.write(
                        to: writing.appendingPathComponent(fileName(for: turn)),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    )
                    for stale in files().dropFirst(limit) {
                        try? FileManager.default.removeItem(at: stale)
                    }
                } catch {
                    logger.error("save failed: \(String(describing: error), privacy: .public)")
                }
            },
            loadAll: {
                let decoder = JSONDecoder()
                return files().compactMap { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? decoder.decode(AskTraceTurn.self, from: data)
                }
            },
            delete: { id in
                for url in files() where url.lastPathComponent.contains(id.uuidString) {
                    try? FileManager.default.removeItem(at: url)
                }
            },
            clear: {
                for url in files() {
                    try? FileManager.default.removeItem(at: url)
                }
            },
            exportFile: { turn in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("AskTrace-\(fileName(for: turn))")
                do {
                    try encoder(pretty: true).encode(turn).write(to: url, options: .atomic)
                    return url
                } catch {
                    logger.error("export failed: \(String(describing: error), privacy: .public)")
                    return nil
                }
            }
        )
    }

    private static func encoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        if pretty {
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }
}
#endif

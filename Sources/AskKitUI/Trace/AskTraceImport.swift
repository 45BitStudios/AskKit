#if !os(watchOS)
#if DEBUG
import AskKit
import AskKitIntents
import Foundation

/// Reads a trace JSON for viewing. One turn or an array, from a share file or a store file.
enum AskTraceImport {
    static func turns(in data: Data) -> [AskTraceTurn] {
        if let turns = decode(data, dates: .iso8601) { return turns }
        return decode(data, dates: .deferredToDate) ?? []
    }

    private static func decode(_ data: Data, dates: JSONDecoder.DateDecodingStrategy) -> [AskTraceTurn]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dates
        if let turn = try? decoder.decode(AskTraceTurn.self, from: data) {
            return [turn]
        }
        if let turns = try? decoder.decode([AskTraceTurn].self, from: data), !turns.isEmpty {
            return turns
        }
        return nil
    }
}
#endif
#endif

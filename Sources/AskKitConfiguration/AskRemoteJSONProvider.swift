import Configuration
import CoreFoundation
import Foundation

/// The bytes were not a JSON object this provider can store.
public struct AskRemoteJSONError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Experimental. A feature-flag document already fetched by the host, read as a `ConfigProvider`.
///
/// The host performs any request. This type only parses `Data`, so tests never open a socket and the type holds no URL and no secret.
/// A kill switch is a bool in that document. Put this provider ahead of the app's defaults and a `false` value turns the flag off.
///
/// Nested objects become key components. `cloud.reasoning` in the document and `{ "cloud": { "reasoning": "deep" } }` are the same key.
/// Dots in a name are separators. Context on a lookup is ignored.
///
/// A real backend would replace `init(data:)` with a `fetchValue` that downloads a new document. This sketch keeps the bytes it was given.
public struct AskRemoteJSONProvider: Sendable {
    private let state: Snapshot

    /// Parses a JSON object of flags.
    /// - Parameters:
    ///   - data: A UTF-8 JSON object. Arrays of strings, bools, or numbers are values. Nested objects are groups of keys.
    ///   - name: Shown in the provider name. The snapshot does not change after this returns.
    public init(data: Data, name: String? = nil) throws {
        self.state = Snapshot(name: name, values: try Parser.parse(data))
    }
}

extension AskRemoteJSONProvider: ConfigProvider {
    public var providerName: String { state.providerName }

    public func value(forKey key: AbsoluteConfigKey, type: ConfigType) throws -> LookupResult {
        try state.value(forKey: key, type: type)
    }

    public func fetchValue(forKey key: AbsoluteConfigKey, type: ConfigType) async throws -> LookupResult {
        try value(forKey: key, type: type)
    }

    public func watchValue<Return: ~Copyable>(
        forKey key: AbsoluteConfigKey,
        type: ConfigType,
        updatesHandler: nonisolated(nonsending) (
            _ updates: ConfigUpdatesAsyncSequence<Result<LookupResult, any Error>, Never>
        ) async throws -> Return
    ) async throws -> Return {
        try await watchValueFromValue(forKey: key, type: type, updatesHandler: updatesHandler)
    }

    public func snapshot() -> any ConfigSnapshot {
        state
    }

    public func watchSnapshot<Return: ~Copyable>(
        updatesHandler: nonisolated(nonsending) (
            _ updates: ConfigUpdatesAsyncSequence<any ConfigSnapshot, Never>
        ) async throws -> Return
    ) async throws -> Return {
        try await watchSnapshotFromSnapshot(updatesHandler: updatesHandler)
    }
}

extension AskRemoteJSONProvider: CustomStringConvertible {
    public var description: String {
        "AskRemoteJSONProvider[\(state.values.count) values]"
    }
}

extension AskRemoteJSONProvider {
    fileprivate struct Snapshot: ConfigSnapshot, Sendable {
        let providerName: String
        let values: [AbsoluteConfigKey: Stored]

        init(name: String?, values: [AbsoluteConfigKey: Stored]) {
            self.providerName = "AskRemoteJSONProvider[\(name ?? "")]"
            self.values = values
        }

        func value(forKey key: AbsoluteConfigKey, type: ConfigType) throws -> LookupResult {
            let encoded = key.components.joined(separator: ".")
            let storedKey = AbsoluteConfigKey(key.components)
            guard let stored = values[storedKey] else {
                return LookupResult(encodedKey: encoded, value: nil)
            }
            let content = try stored.content(as: type, key: encoded)
            return LookupResult(encodedKey: encoded, value: ConfigValue(content, isSecret: false))
        }
    }
}

extension AskRemoteJSONProvider {
    fileprivate enum Stored: Sendable, Equatable {
        case string(String)
        case bool(Bool)
        case number(Double)
        case strings([String])
        case bools([Bool])
        case numbers([Double])
        case emptyArray

        func content(as type: ConfigType, key: String) throws -> ConfigContent {
            switch (self, type) {
            case (.string(let value), .string):
                return .string(value)
            case (.bool(let value), .bool):
                return .bool(value)
            case (.number(let value), .double):
                return .double(value)
            case (.number(let value), .int):
                guard let int = Int(exactly: value) else {
                    throw AskRemoteJSONError(message: "\(key) is not an integer.")
                }
                return .int(int)
            case (.strings(let values), .stringArray):
                return .stringArray(values)
            case (.bools(let values), .boolArray):
                return .boolArray(values)
            case (.numbers(let values), .doubleArray):
                return .doubleArray(values)
            case (.numbers(let values), .intArray):
                let ints = try values.map { value -> Int in
                    guard let int = Int(exactly: value) else {
                        throw AskRemoteJSONError(message: "\(key) is not an integer array.")
                    }
                    return int
                }
                return .intArray(ints)
            case (.emptyArray, .stringArray):
                return .stringArray([])
            case (.emptyArray, .boolArray):
                return .boolArray([])
            case (.emptyArray, .intArray):
                return .intArray([])
            case (.emptyArray, .doubleArray):
                return .doubleArray([])
            default:
                throw AskRemoteJSONError(message: "\(key) is not a \(type.rawValue).")
            }
        }
    }
}

extension AskRemoteJSONProvider {
    fileprivate enum Parser {
        static func parse(_ data: Data) throws -> [AbsoluteConfigKey: Stored] {
            let root: Any
            do {
                root = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw AskRemoteJSONError(message: "The document is not JSON.")
            }
            guard let object = root as? [String: Any] else {
                throw AskRemoteJSONError(message: "The document must be a JSON object.")
            }
            var values: [AbsoluteConfigKey: Stored] = [:]
            try store(object, prefix: [], into: &values)
            return values
        }

        private static func store(
            _ object: [String: Any],
            prefix: [String],
            into values: inout [AbsoluteConfigKey: Stored]
        ) throws {
            for (name, raw) in object {
                let path = try components(name: name, prefix: prefix)
                switch try classify(raw, key: path.joined(separator: ".")) {
                case .object(let nested):
                    try store(nested, prefix: path, into: &values)
                case .null:
                    continue
                case .value(let stored):
                    let key = AbsoluteConfigKey(path)
                    if values[key] != nil {
                        throw AskRemoteJSONError(message: "Duplicate key \(path.joined(separator: ".")).")
                    }
                    values[key] = stored
                }
            }
        }

        private static func components(name: String, prefix: [String]) throws -> [String] {
            let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else {
                throw AskRemoteJSONError(message: "A key name is empty.")
            }
            return prefix + parts
        }

        private enum Node {
            case object([String: Any])
            case null
            case value(Stored)
        }

        private static func classify(_ raw: Any, key: String) throws -> Node {
            if raw is NSNull { return .null }
            if let object = raw as? [String: Any] { return .object(object) }
            if let string = raw as? String { return .value(.string(string)) }
            if let items = raw as? [Any] { return .value(try array(items, key: key)) }
            if let number = raw as? NSNumber {
                if isBool(number) { return .value(.bool(number.boolValue)) }
                let value = number.doubleValue
                guard value.isFinite else {
                    throw AskRemoteJSONError(message: "\(key) is not a finite number.")
                }
                return .value(.number(value))
            }
            throw AskRemoteJSONError(message: "\(key) is not a flag value.")
        }

        private enum ArrayKind {
            case string
            case bool
            case number
        }

        private static func array(_ items: [Any], key: String) throws -> Stored {
            if items.isEmpty { return .emptyArray }
            var strings: [String] = []
            var bools: [Bool] = []
            var numbers: [Double] = []
            var kind: ArrayKind?
            for item in items {
                switch try classify(item, key: key) {
                case .object, .null:
                    throw AskRemoteJSONError(message: "\(key) holds a value this provider does not store.")
                case .value(let stored):
                    switch stored {
                    case .string(let value):
                        try require(kind, is: .string, key: key)
                        kind = .string
                        strings.append(value)
                    case .bool(let value):
                        try require(kind, is: .bool, key: key)
                        kind = .bool
                        bools.append(value)
                    case .number(let value):
                        try require(kind, is: .number, key: key)
                        kind = .number
                        numbers.append(value)
                    case .strings, .bools, .numbers, .emptyArray:
                        throw AskRemoteJSONError(message: "\(key) nests another array.")
                    }
                }
            }
            switch kind {
            case .string: return .strings(strings)
            case .bool: return .bools(bools)
            case .number: return .numbers(numbers)
            case nil: return .emptyArray
            }
        }

        private static func require(_ kind: ArrayKind?, is expected: ArrayKind, key: String) throws {
            guard kind == nil || kind == expected else {
                throw AskRemoteJSONError(message: "\(key) mixes flag types.")
            }
        }

        /// JSON booleans arrive as `NSNumber`. `0` and `1` also bridge to `Bool`, so the CoreFoundation type id is what keeps them numbers.
        private static func isBool(_ number: NSNumber) -> Bool {
            CFGetTypeID(number) == CFBooleanGetTypeID()
        }
    }
}

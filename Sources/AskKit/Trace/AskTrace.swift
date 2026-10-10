import Foundation

/// Debug function-call tracing for one Ask turn.
///
/// A turn is one question. A span is one instrumented call. Nesting comes from a task-local, so `async let` keeps
/// its parent. A span opened when no turn is running runs its body and records nothing. A turn started inside
/// another turn becomes a span of the outer one.
///
/// Time is a monotonic clock. A span's duration includes its children and any awaiting. Model calls record the
/// session transcript and context-window use after `respond` returns. See `AskTrace+FoundationModels.swift`.
///
/// Every call compiles in Release and does nothing there. The recorder, store, and viewer exist only in Debug.
public enum AskTrace {
    public static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    nonisolated(nonsending) public static func turn<T>(
        _ question: String,
        entry: AskTraceEntry = .composer,
        record: Bool = true,
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line,
        _ body: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        #if DEBUG
        guard record else { return try await body() }
        if let parent = current {
            guard let context = recorder.openSpan(
                parent: parent,
                name: "turn (\(entry.rawValue))",
                kind: .function,
                attributes: [.init(key: "question", value: question)],
                function: function,
                fileID: fileID,
                line: line
            ) else {
                return try await body()
            }
            return try await run(context, body)
        }
        let context = recorder.beginTurn(question: question, entry: entry, function: function, fileID: fileID, line: line)
        do {
            let value = try await $current.withValue(context, operation: body)
            recorder.endSpan(context, status: .ok)
            recorder.endTurn(context.turnID)
            return value
        } catch {
            recorder.endSpan(context, status: .threw(String(describing: error)))
            recorder.endTurn(context.turnID)
            throw error
        }
        #else
        _ = (question, entry, record, function, fileID, line)
        return try await body()
        #endif
    }

    nonisolated(nonsending) public static func span<T>(
        _ name: String,
        kind: AskTraceSpanKind = .function,
        _ attributes: @autoclosure () -> KeyValuePairs<String, String> = [:],
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line,
        _ body: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        #if DEBUG
        guard let context = open(name, kind: kind, attributes: attributes(), function: function, fileID: fileID, line: line) else {
            return try await body()
        }
        return try await run(context, body)
        #else
        _ = (name, kind, function, fileID, line)
        return try await body()
        #endif
    }

    public static func span<T>(
        _ name: String,
        kind: AskTraceSpanKind = .function,
        _ attributes: @autoclosure () -> KeyValuePairs<String, String> = [:],
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line,
        _ body: () throws -> T
    ) rethrows -> T {
        #if DEBUG
        guard let context = open(name, kind: kind, attributes: attributes(), function: function, fileID: fileID, line: line) else {
            return try body()
        }
        do {
            let value = try $current.withValue(context, operation: body)
            recorder.endSpan(context, status: .ok)
            return value
        } catch {
            recorder.endSpan(context, status: .threw(String(describing: error)))
            throw error
        }
        #else
        _ = (name, kind, function, fileID, line)
        return try body()
        #endif
    }

    nonisolated(nonsending) public static func userWait<T>(
        _ name: String,
        function: String = #function,
        fileID: String = #fileID,
        line: Int = #line,
        _ body: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await span(name, kind: .userWait, function: function, fileID: fileID, line: line, body)
    }

    public static func event(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard let current else { return }
        recorder.addEvent(current, kind: .log, message: message())
        #endif
    }

    public static func decision(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard let current else { return }
        recorder.addEvent(current, kind: .decision, message: message())
        #endif
    }

    public static func attribute(_ key: String, _ value: @autoclosure () -> String) {
        #if DEBUG
        guard let current else { return }
        recorder.setAttribute(current, key: key, value: value())
        #endif
    }

    /// What the person was shown. Empty strings are skipped. Replaces the same key.
    public static func shown(_ answer: String, cards: String) {
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty {
            attribute("shownAnswer", answer)
        }
        let cards = cards.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cards.isEmpty {
            attribute("shownCards", cards)
        }
    }

    public static func result(_ value: @autoclosure () -> String) {
        #if DEBUG
        guard let current else { return }
        recorder.setResult(current, value: value())
        #endif
    }
}

#if DEBUG
extension AskTrace {
    @TaskLocal static var current: AskTraceContext?
    @TaskLocal static var recorder = AskTraceRecorder.live

    private static func open(
        _ name: String,
        kind: AskTraceSpanKind,
        attributes: KeyValuePairs<String, String>,
        function: String,
        fileID: String,
        line: Int
    ) -> AskTraceContext? {
        guard let parent = current ?? (kind == .tool ? recorder.openModelContext() : nil) else { return nil }
        return recorder.openSpan(
            parent: parent,
            name: name,
            kind: kind,
            attributes: attributes.map { AskTraceSpan.Attribute(key: $0.key, value: $0.value) },
            function: function,
            fileID: fileID,
            line: line
        )
    }

    nonisolated(nonsending) private static func run<T>(
        _ context: AskTraceContext,
        _ body: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        do {
            let value = try await $current.withValue(context, operation: body)
            recorder.endSpan(context, status: .ok)
            return value
        } catch {
            recorder.endSpan(context, status: .threw(String(describing: error)))
            throw error
        }
    }
}
#endif

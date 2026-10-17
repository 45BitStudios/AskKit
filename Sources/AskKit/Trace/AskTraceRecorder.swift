#if DEBUG
import Foundation
import os

struct AskTraceContext: Sendable, Equatable {
    let turnID: UUID
    let spanID: UUID
}

extension Notification.Name {
    package static let askTraceDidRecord = Notification.Name("AskTraceDidRecord")
}

package enum AskTraceNotifications {
    package static let darwinName = "com.studio45.askkit.trace.didRecord"

    static func recordDidSave() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinName as CFString),
            nil,
            nil,
            true
        )
        NotificationCenter.default.post(name: .askTraceDidRecord, object: nil)
    }
}

/// Builds turns from span open/close calls made on any thread. Finished turns go to `onTurnFinished`.
final class AskTraceRecorder: Sendable {
    private struct Running {
        var turn: AskTraceTurn
        let clockStart: ContinuousClock.Instant
        var indexByID: [UUID: Int]
        var openModelSpans: [UUID]
    }

    private let state = OSAllocatedUnfairLock(initialState: [UUID: Running]())
    private let onTurnFinished: @Sendable (AskTraceTurn) -> Void
    private let onTurnCheckpoint: @Sendable (AskTraceTurn) -> Void

    init(
        onTurnFinished: @escaping @Sendable (AskTraceTurn) -> Void,
        onTurnCheckpoint: @escaping @Sendable (AskTraceTurn) -> Void = { _ in }
    ) {
        self.onTurnFinished = onTurnFinished
        self.onTurnCheckpoint = onTurnCheckpoint
    }

    static let live: AskTraceRecorder = {
        // Unit tests bind their own recorder. The default must not write the developer's Caches folder.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return AskTraceRecorder(onTurnFinished: { _ in })
        }
        return AskTraceRecorder(
            onTurnFinished: { turn in
                AskTraceStore.live().save(turn)
                AskTraceNotifications.recordDidSave()
            },
            onTurnCheckpoint: { turn in
                AskTraceStore.live().save(turn)
                AskTraceNotifications.recordDidSave()
            }
        )
    }()

    func beginTurn(
        question: String,
        entry: AskTraceEntry,
        function: String,
        fileID: String,
        line: Int
    ) -> AskTraceContext {
        let turnID = UUID()
        let root = AskTraceSpan(
            id: UUID(),
            parentID: nil,
            name: "Ask turn (\(entry.rawValue))",
            kind: .turn,
            function: function,
            fileID: fileID,
            line: line,
            start: 0,
            end: nil,
            status: .ok,
            attributes: [.init(key: "question", value: question)],
            result: nil,
            events: [],
            model: nil
        )
        let running = Running(
            turn: AskTraceTurn(id: turnID, question: question, entry: entry, startedAt: Date(), duration: nil, spans: [root]),
            clockStart: .now,
            indexByID: [root.id: 0],
            openModelSpans: []
        )
        state.withLock { $0[turnID] = running }
        checkpoint(turnID)
        return AskTraceContext(turnID: turnID, spanID: root.id)
    }

    func endTurn(_ turnID: UUID) {
        let finished: AskTraceTurn? = state.withLock { turns in
            guard var running = turns.removeValue(forKey: turnID) else { return nil }
            let now = Self.offset(since: running.clockStart)
            running.turn.duration = now
            for index in running.turn.spans.indices where running.turn.spans[index].end == nil {
                running.turn.spans[index].end = now
                running.turn.spans[index].status = .unfinished
            }
            return running.turn
        }
        if let finished {
            onTurnFinished(finished)
        }
    }

    func openSpan(
        parent: AskTraceContext,
        name: String,
        kind: AskTraceSpanKind,
        attributes: [AskTraceSpan.Attribute],
        function: String,
        fileID: String,
        line: Int
    ) -> AskTraceContext? {
        let opened: AskTraceContext? = state.withLock { turns in
            guard var running = turns[parent.turnID] else { return nil }
            let span = AskTraceSpan(
                id: UUID(),
                parentID: parent.spanID,
                name: name,
                kind: kind,
                function: function,
                fileID: fileID,
                line: line,
                start: Self.offset(since: running.clockStart),
                end: nil,
                status: .ok,
                attributes: attributes,
                result: nil,
                events: [],
                model: nil
            )
            running.indexByID[span.id] = running.turn.spans.count
            running.turn.spans.append(span)
            if kind == .model {
                running.openModelSpans.append(span.id)
            }
            turns[parent.turnID] = running
            return AskTraceContext(turnID: parent.turnID, spanID: span.id)
        }
        if kind == .userWait, let turnID = opened?.turnID {
            checkpoint(turnID)
        }
        return opened
    }

    func endSpan(_ context: AskTraceContext, status: AskTraceSpan.Status) {
        update(context) { span, running in
            span.end = Self.offset(since: running.clockStart)
            span.status = status
            running.openModelSpans.removeAll { $0 == span.id }
        }
        checkpoint(context.turnID)
    }

    /// The newest open model span in any running turn. Parent of last resort for tool calls Foundation Models
    /// runs on its own task, where the task-local is not set.
    func openModelContext() -> AskTraceContext? {
        state.withLock { turns in
            turns.values
                .compactMap { running -> (ContinuousClock.Instant, AskTraceContext)? in
                    guard let spanID = running.openModelSpans.last else { return nil }
                    return (running.clockStart, AskTraceContext(turnID: running.turn.id, spanID: spanID))
                }
                .max { $0.0 < $1.0 }?
                .1
        }
    }

    func addEvent(_ context: AskTraceContext, kind: AskTraceEvent.Kind, message: String) {
        update(context) { span, running in
            span.events.append(AskTraceEvent(offset: Self.offset(since: running.clockStart), kind: kind, message: message))
        }
    }

    func setAttribute(_ context: AskTraceContext, key: String, value: String) {
        update(context) { span, _ in
            if let index = span.attributes.firstIndex(where: { $0.key == key }) {
                span.attributes[index].value = value
            } else {
                span.attributes.append(.init(key: key, value: value))
            }
        }
    }

    func setResult(_ context: AskTraceContext, value: String) {
        update(context) { span, _ in span.result = value }
    }

    func attachModel(_ context: AskTraceContext, call: AskTraceModelCall) {
        update(context) { span, _ in span.model = call }
    }

    private func checkpoint(_ turnID: UUID) {
        let snapshot: AskTraceTurn? = state.withLock { turns in
            guard var running = turns[turnID] else { return nil }
            running.turn.duration = Self.offset(since: running.clockStart)
            return running.turn
        }
        if let snapshot {
            onTurnCheckpoint(snapshot)
        }
    }

    private func update(_ context: AskTraceContext, _ change: (inout AskTraceSpan, inout Running) -> Void) {
        state.withLockUnchecked { turns in
            guard var running = turns[context.turnID],
                  let index = running.indexByID[context.spanID] else { return }
            var span = running.turn.spans[index]
            change(&span, &running)
            running.turn.spans[index] = span
            turns[context.turnID] = running
        }
    }

    private static func offset(since start: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
}
#endif

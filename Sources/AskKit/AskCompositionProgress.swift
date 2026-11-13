import Foundation
import Observation
import os

/// One step while a generative card is being composed.
/// The order is fixed. A later event does not return to an earlier step.
public enum AskCompositionPhase: String, Sendable, Codable, CaseIterable, Identifiable {
    /// The turn has started, or a specialist is choosing before a tool runs.
    case understanding
    /// A tool call is in flight. Maps from ``AskChatPhase/tool``.
    case lookingUp
    /// Facts are in hand and the writer is producing the line. Maps from ``AskChatPhase/writing``.
    case preparing
    /// The card tree is being composed.
    case composing

    public var id: String { rawValue }

    /// The line shown beside the step.
    public var title: String {
        switch self {
        case .understanding: "Understand request"
        case .lookingUp: "Search"
        case .preparing: "Prepare data"
        case .composing: "Write layout"
        }
    }

    public var symbolName: String {
        switch self {
        case .understanding: "text.magnifyingglass"
        case .lookingUp: "magnifyingglass"
        case .preparing: "tray.full"
        case .composing: "rectangle.3.group"
        }
    }

    /// Pipeline order. Index 0 is first.
    public static let sequence: [AskCompositionPhase] = [.understanding, .lookingUp, .preparing, .composing]

    public var order: Int {
        Self.sequence.firstIndex(of: self) ?? 0
    }

    /// Existing chat and tool activity, when this run is already open.
    /// Thinking and choosing stay on Understand request. A tool call is Search. Writing is Prepare data.
    /// Write layout is started by the compose session itself.
    public init?(chat phase: AskChatPhase) {
        switch phase {
        case .thinking, .choosing: self = .understanding
        case .tool: self = .lookingUp
        case .writing: self = .preparing
        }
    }
}

/// Whether a composition step is still ahead, running, done, or was not needed.
public enum AskCompositionStepState: String, Sendable, Equatable, Codable {
    case waiting
    case active
    case finished
    case skipped
}

/// One row in the composition checklist, including how long it ran once it finishes.
public struct AskCompositionStep: Sendable, Equatable, Identifiable, Codable {
    public var phase: AskCompositionPhase
    public var state: AskCompositionStepState
    public var duration: TimeInterval?
    public var id: AskCompositionPhase { phase }

    public init(phase: AskCompositionPhase, state: AskCompositionStepState, duration: TimeInterval? = nil) {
        self.phase = phase
        self.state = state
        self.duration = duration
    }

    /// Short timing for a finished step, such as `0.4s`. Nil until the step finishes.
    public var timingLabel: String? {
        guard state == .finished, let duration else { return nil }
        return AskCompositionTiming.label(seconds: duration)
    }

    /// VoiceOver line for the row.
    public var accessibilityLabel: String {
        switch state {
        case .waiting:
            return "\(phase.title), waiting"
        case .active:
            return "\(phase.title), in progress"
        case .skipped:
            return "\(phase.title), skipped"
        case .finished:
            if let duration {
                return "\(phase.title), finished, \(AskCompositionTiming.spoken(seconds: duration))"
            }
            return "\(phase.title), finished"
        }
    }
}

/// The checklist a compose run is showing, plus the durations recorded so far.
public struct AskCompositionSnapshot: Sendable, Equatable, Codable {
    public var steps: [AskCompositionStep]
    public var records: [AskCompositionRecord]
    public var isRunning: Bool

    public init(steps: [AskCompositionStep], records: [AskCompositionRecord], isRunning: Bool) {
        self.steps = steps
        self.records = records
        self.isRunning = isRunning
    }

    public static let waiting = AskCompositionSnapshot(
        steps: AskCompositionPhase.sequence.map {
            AskCompositionStep(phase: $0, state: .waiting, duration: nil)
        },
        records: [],
        isRunning: false
    )

    public func step(_ phase: AskCompositionPhase) -> AskCompositionStep? {
        steps.first { $0.phase == phase }
    }
}

/// A finished phase and how long it stayed active.
public struct AskCompositionRecord: Sendable, Equatable, Codable {
    public var phase: AskCompositionPhase
    public var duration: TimeInterval

    public init(phase: AskCompositionPhase, duration: TimeInterval) {
        self.phase = phase
        self.duration = duration
    }
}

/// Formats a phase duration for the checklist. The value itself stays on ``AskCompositionRecord``.
public enum AskCompositionTiming {
    public static func label(seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 0.05 { return "<0.1s" }
        if seconds >= 10 {
            return "\(Int(seconds.rounded()))s"
        }
        let tenths = Int((seconds * 10).rounded())
        let whole = tenths / 10
        let fraction = abs(tenths % 10)
        return "\(whole).\(fraction)s"
    }

    public static func spoken(seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 0.05 { return "under 0.1 seconds" }
        let tenths = Int((seconds * 10).rounded())
        let whole = tenths / 10
        let fraction = abs(tenths % 10)
        if fraction == 0 {
            return whole == 1 ? "1 second" : "\(whole) seconds"
        }
        return "\(whole).\(fraction) seconds"
    }
}

/// Value type for one compose run. Tests advance it with a fixed clock.
/// Phases only move forward. A tool event after Write layout has started does not reopen Search.
public struct AskCompositionState: Sendable, Equatable {
    public private(set) var snapshot: AskCompositionSnapshot
    private var active: AskCompositionPhase?
    private var startedAt: Date?

    public init() {
        snapshot = .waiting
        active = nil
        startedAt = nil
    }

    /// Opens the run on Understand request. A second call does nothing.
    @discardableResult
    public mutating func start(now: Date) -> [AskCompositionRecord] {
        guard !snapshot.isRunning else { return [] }
        snapshot.isRunning = true
        begin(.understanding, now: now)
        return []
    }

    /// Moves forward to `phase`. Phases in between that never started are skipped.
    /// Returns the phases that finished on this call, in order.
    @discardableResult
    public mutating func advance(to phase: AskCompositionPhase, now: Date) -> [AskCompositionRecord] {
        guard snapshot.isRunning, let current = active else { return [] }
        if phase.order < current.order || phase == current { return [] }
        var finished: [AskCompositionRecord] = []
        finished.append(completeActive(now: now))
        for skipped in AskCompositionPhase.sequence where skipped.order > current.order && skipped.order < phase.order {
            set(skipped, state: .skipped, duration: nil)
        }
        begin(phase, now: now)
        return finished
    }

    /// Feeds an existing chat or tool phase into the checklist.
    @discardableResult
    public mutating func note(chat phase: AskChatPhase, now: Date) -> [AskCompositionRecord] {
        guard let mapped = AskCompositionPhase(chat: phase) else { return [] }
        return advance(to: mapped, now: now)
    }

    /// Finishes the active step and marks anything still waiting as skipped.
    @discardableResult
    public mutating func finish(now: Date) -> [AskCompositionRecord] {
        guard snapshot.isRunning else { return [] }
        var finished: [AskCompositionRecord] = []
        if active != nil {
            finished.append(completeActive(now: now))
        }
        for phase in AskCompositionPhase.sequence where snapshot.step(phase)?.state == .waiting {
            set(phase, state: .skipped, duration: nil)
        }
        active = nil
        startedAt = nil
        snapshot.isRunning = false
        return finished
    }

    private mutating func begin(_ phase: AskCompositionPhase, now: Date) {
        active = phase
        startedAt = now
        set(phase, state: .active, duration: nil)
    }

    private mutating func completeActive(now: Date) -> AskCompositionRecord {
        let phase = active ?? .understanding
        let duration = max(0, now.timeIntervalSince(startedAt ?? now))
        set(phase, state: .finished, duration: duration)
        active = nil
        startedAt = nil
        let record = AskCompositionRecord(phase: phase, duration: duration)
        snapshot.records.append(record)
        return record
    }

    private mutating func set(_ phase: AskCompositionPhase, state: AskCompositionStepState, duration: TimeInterval?) {
        guard let index = snapshot.steps.firstIndex(where: { $0.phase == phase }) else { return }
        snapshot.steps[index].state = state
        snapshot.steps[index].duration = duration
    }
}

/// In-process log of finished composition phases. Nothing is sent off the device.
public enum AskCompositionMetrics {
    private typealias RecordHook = @Sendable (AskCompositionRecord) -> Void
    private static let storage = OSAllocatedUnfairLock(initialState: [AskCompositionRecord]())
    private static let hook = OSAllocatedUnfairLock<RecordHook?>(initialState: nil)
    private static let logger = Logger(subsystem: "com.studio45.askkit", category: "Composition")

    /// Called after each record is stored. Do not call ``record(_:)`` from this hook.
    public static var onRecord: (@Sendable (AskCompositionRecord) -> Void)? {
        get { hook.withLock { $0 } }
        set { hook.withLock { $0 = newValue } }
    }

    public static func record(_ record: AskCompositionRecord) {
        storage.withLock { $0.append(record) }
        let seconds = String(format: "%.3f", record.duration)
        logger.info("phase=\(record.phase.rawValue, privacy: .public) duration=\(seconds, privacy: .public)")
        let notify = hook.withLock { $0 }
        notify?(record)
    }

    public static func records() -> [AskCompositionRecord] {
        storage.withLock { $0 }
    }

    public static func reset() {
        storage.withLock { $0.removeAll() }
        hook.withLock { $0 = nil }
    }
}

/// Observable compose run. ``updates()`` yields the same snapshots the checklist reads.
/// ``shared`` is the run AskKit opens around a generated card. A gallery preview uses its own instance.
@MainActor
@Observable
public final class AskCompositionProgress {
    public static let shared: AskCompositionProgress = {
        let progress = AskCompositionProgress()
        progress.recordsMetrics = true
        return progress
    }()

    public private(set) var snapshot: AskCompositionSnapshot = .waiting
    /// When true, finished phases are appended to ``AskCompositionMetrics``.
    public var recordsMetrics = false

    private var state = AskCompositionState()
    private let streams = OSAllocatedUnfairLock(
        initialState: [UUID: AsyncStream<AskCompositionSnapshot>.Continuation]()
    )

    public init() {}

    public var isRunning: Bool { snapshot.isRunning }

    public var records: [AskCompositionRecord] { snapshot.records }

    /// Yields the current snapshot, then each later one. The current value is first.
    public func updates() -> AsyncStream<AskCompositionSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: AskCompositionSnapshot.self)
        let id = UUID()
        streams.withLock { $0[id] = continuation }
        continuation.yield(snapshot)
        let streams = self.streams
        continuation.onTermination = { _ in
            streams.withLock { $0[id] = nil }
        }
        return stream
    }

    /// Starts Understand request when no run is open. Returns false when one is already open.
    @discardableResult
    public func begin(now: Date = Date()) -> Bool {
        guard !isRunning else { return false }
        state = AskCompositionState()
        forward(state.start(now: now))
        publish()
        return true
    }

    public func advance(to phase: AskCompositionPhase, now: Date = Date()) {
        guard isRunning else { return }
        forward(state.advance(to: phase, now: now))
        publish()
    }

    /// Tool calls and writer activity, from ``AskChatActivity`` and ``AskProfileHooks``.
    public func note(chat phase: AskChatPhase, now: Date = Date()) {
        guard isRunning else { return }
        forward(state.note(chat: phase, now: now))
        publish()
    }

    public func finish(now: Date = Date()) {
        guard isRunning else { return }
        forward(state.finish(now: now))
        publish()
    }

    private func forward(_ records: [AskCompositionRecord]) {
        guard recordsMetrics else { return }
        for record in records {
            AskCompositionMetrics.record(record)
        }
    }

    private func publish() {
        snapshot = state.snapshot
        let value = snapshot
        let continuations = streams.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(value)
        }
    }
}

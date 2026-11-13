import Foundation

/// How long one card composition took. A slow run is not a failure. Callers log `duration` themselves.
public struct AskCardComposeMeasurement: Sendable, Equatable {
    public var duration: Duration
    /// False when the measured work threw.
    public var succeeded: Bool

    public init(duration: Duration, succeeded: Bool) {
        self.duration = duration
        self.succeeded = succeeded
    }
}

/// The value from a measured call, or nil when it threw. `measurement` is set either way.
public struct AskCardMeasureResult<Value: Sendable>: Sendable {
    public var value: Value?
    public var measurement: AskCardComposeMeasurement

    public init(value: Value?, measurement: AskCardComposeMeasurement) {
        self.value = value
        self.measurement = measurement
    }
}

/// Times a compose, or any other async piece of card work, without a deadline.
public enum AskCardComposeMeter {
    public static func measure<T: Sendable>(
        _ work: () async throws -> T
    ) async -> AskCardMeasureResult<T> {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let value = try await work()
            return AskCardMeasureResult(
                value: value,
                measurement: AskCardComposeMeasurement(
                    duration: start.duration(to: clock.now),
                    succeeded: true
                )
            )
        } catch {
            return AskCardMeasureResult(
                value: nil,
                measurement: AskCardComposeMeasurement(
                    duration: start.duration(to: clock.now),
                    succeeded: false
                )
            )
        }
    }
}

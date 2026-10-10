import Foundation

/// Progress for an on-device Vision index pass.
public struct PhotoIndexProgress: Sendable, Equatable {
    public var completed: Int
    public var total: Int
    /// Entries stored after this update.
    public var indexedCount: Int
    public var isFinished: Bool

    public init(completed: Int, total: Int, indexedCount: Int, isFinished: Bool) {
        self.completed = completed
        self.total = total
        self.indexedCount = indexedCount
        self.isFinished = isFinished
    }

    public var fractionComplete: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(completed) / Double(total))
    }
}

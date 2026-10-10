#if DEBUG
import Combine
import Foundation
import SwiftUI
import UIKit

struct AskTraceNode: Equatable {
    var span: AskTraceSpan
    var children: [AskTraceNode]
}

struct AskTraceRow: Identifiable, Equatable {
    let id: UUID
    let depth: Int
    let span: AskTraceSpan
    /// Same-name `.model` child folded into this function row (Tree / Timeline).
    let inlinedModel: AskTraceSpan?
    let hasChildren: Bool
    let isExpanded: Bool
    let isParallel: Bool
}

struct AskTraceBar: Identifiable, Equatable {
    let id: UUID
    let depth: Int
    let span: AskTraceSpan
    let x: Double
    let width: Double
}

struct AskTraceSummary: Equatable {
    var modelCalls = 0
    var toolCalls = 0
    var decisions = 0
    var errors = 0
    var routedVia: String?
    var specialists: String?
    var userWait: TimeInterval = 0
    var peakContext: AskTraceContextUsage?
    var totalTokens = 0
}

struct AskTraceShare: Identifiable {
    let id = UUID()
    let file: URL?
    let text: String
    let image: UIImage?

    var items: [Any] {
        var items: [Any] = []
        if let image { items.append(image) }
        items.append(text)
        if let file { items.append(file) }
        return items
    }
}

@MainActor
final class AskTraceViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case story = "Story"
        case tree = "Tree"
        case timeline = "Timeline"
        var id: String { rawValue }
    }

    private let store: AskTraceStore
    private let notifications: NotificationCenter
    /// Rebuilds the cards from the chat turn that matches this trace. Nil when no chat is open.
    let snippetCards: (@MainActor (AskTraceTurn) async -> [AnyView])?

    @Published private(set) var turns: [AskTraceTurn] = []
    /// Dropped traces. They are not written to the store.
    @Published private(set) var viewing: [AskTraceTurn] = []
    @Published private(set) var expanded: Set<UUID> = []
    @Published private(set) var tab: Tab = .story
    @Published private(set) var compressUserWaits = true
    @Published private(set) var share: AskTraceShare?
    @Published private(set) var isGuidePresented = false

    private var seededTurns: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    private let darwinWatch = AskTraceDarwinWatch()

    init(
        store: AskTraceStore,
        notifications: NotificationCenter = .default,
        snippetCards: (@MainActor (AskTraceTurn) async -> [AnyView])? = nil
    ) {
        self.store = store
        self.notifications = notifications
        self.snippetCards = snippetCards
    }

    func turn(_ id: UUID) -> AskTraceTurn? {
        viewing.first { $0.id == id } ?? turns.first { $0.id == id }
    }

    func span(_ spanID: UUID, in turnID: UUID) -> AskTraceSpan? {
        turn(turnID)?.spans.first { $0.id == spanID }
    }

    func rows(for turnID: UUID) -> [AskTraceRow] {
        guard let turn = turn(turnID) else { return [] }
        return Self.visibleRows(tree: Self.buildTree(spans: turn.spans), expanded: expanded)
    }

    func bars(for turnID: UUID) -> [AskTraceBar] {
        guard let turn = turn(turnID) else { return [] }
        return Self.timelineBars(turn: turn, compressWaits: compressUserWaits)
    }

    func summary(for turn: AskTraceTurn) -> AskTraceSummary {
        Self.summary(turn: turn)
    }

    func onAppear() {
        reload()
        guard cancellables.isEmpty else { return }
        notifications.publisher(for: .askTraceDidRecord)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        darwinWatch.onRecord = { [weak self] in self?.reload() }
        darwinWatch.start()
    }

    func onForeground() { reload() }

    func onTurnAppear(_ turnID: UUID) {
        guard !seededTurns.contains(turnID), let turn = turn(turnID) else { return }
        seededTurns.insert(turnID)
        expanded.formUnion(turn.spans.map(\.id))
    }

    func onToggle(_ spanID: UUID) {
        if expanded.contains(spanID) { expanded.remove(spanID) } else { expanded.insert(spanID) }
    }

    func onExpandAll(_ turnID: UUID) {
        guard let turn = turn(turnID) else { return }
        expanded.formUnion(turn.spans.map(\.id))
    }

    func onCollapseAll(_ turnID: UUID) {
        guard let turn = turn(turnID) else { return }
        let root = turn.spans.first { $0.parentID == nil }?.id
        expanded.subtract(turn.spans.map(\.id).filter { $0 != root })
    }

    func onTabChanged(_ tab: Tab) { self.tab = tab }
    func onCompressWaitsChanged(_ compress: Bool) { compressUserWaits = compress }

    func onDeleteTurn(_ turnID: UUID) {
        store.delete(turnID)
        reload()
    }

    func onClearTapped() {
        store.clear()
        reload()
    }

    func onShareTapped(_ turnID: UUID) {
        guard let turn = turn(turnID) else { return }
        share = AskTraceShare(
            file: store.exportFile(turn),
            text: AskTraceFormatter.exportText(turn),
            image: AskTracePoster.image(for: turn)
        )
    }

    /// Opens dropped trace JSON for viewing. Does not save it. Returns false when nothing in the data is a trace.
    @discardableResult
    func onImport(_ data: Data) -> Bool {
        let decoded = AskTraceImport.turns(in: data)
        guard !decoded.isEmpty else { return false }
        var known = Set(viewing.map(\.id)).union(turns.map(\.id))
        var fresh: [AskTraceTurn] = []
        for turn in decoded where known.insert(turn.id).inserted {
            fresh.append(turn)
        }
        if !fresh.isEmpty {
            viewing.insert(contentsOf: fresh, at: 0)
        }
        return true
    }

    func onDrop(urls: [URL]) -> Bool {
        var accepted = false
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            if onImport(data) { accepted = true }
        }
        return accepted
    }

    func onDismissViewing(_ turnID: UUID) {
        viewing.removeAll { $0.id == turnID }
    }

    func onShareDismissed() { share = nil }
    func onInfoTapped() { isGuidePresented = true }
    func onGuideDismissed() { isGuidePresented = false }

    private func reload() {
        let loaded = store.loadAll()
        guard loaded != turns else { return }
        turns = loaded
    }
}

private final class AskTraceDarwinWatch: @unchecked Sendable {
    var onRecord: @MainActor () -> Void = {}
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let watch = Unmanaged<AskTraceDarwinWatch>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in watch.onRecord() }
            },
            AskTraceNotifications.darwinName as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stop() {
        guard started else { return }
        started = false
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(AskTraceNotifications.darwinName as CFString),
            nil
        )
    }

    deinit { stop() }
}

extension AskTraceViewModel {
    nonisolated static func buildTree(spans: [AskTraceSpan]) -> [AskTraceNode] {
        let ids = Set(spans.map(\.id))
        let childrenByParent = Dictionary(grouping: spans.filter { $0.parentID.map(ids.contains) == true }) { $0.parentID }
        func node(_ span: AskTraceSpan) -> AskTraceNode {
            let children = (childrenByParent[span.id] ?? []).sorted { $0.start < $1.start }
            return AskTraceNode(span: span, children: children.map(node))
        }
        return spans
            .filter { $0.parentID.map(ids.contains) != true }
            .sorted { $0.start < $1.start }
            .map(node)
    }

    /// A function whose only same-name model child is folded into the parent row.
    nonisolated static func inlinedModel(of node: AskTraceNode) -> AskTraceNode? {
        guard node.span.kind == .function else { return nil }
        let models = node.children.filter { $0.span.kind == .model && $0.span.name == node.span.name }
        guard models.count == 1 else { return nil }
        return models[0]
    }

    /// Children shown under a row after collapsing a same-name model into the parent.
    nonisolated static func displayChildren(of node: AskTraceNode) -> [AskTraceNode] {
        guard let model = inlinedModel(of: node) else { return node.children }
        let others = node.children.filter { $0.span.id != model.span.id }
        return (others + model.children).sorted { $0.span.start < $1.span.start }
    }

    nonisolated static func visibleRows(tree: [AskTraceNode], expanded: Set<UUID>) -> [AskTraceRow] {
        var rows: [AskTraceRow] = []
        func walk(_ nodes: [AskTraceNode], depth: Int) {
            for node in nodes {
                let inlined = inlinedModel(of: node)
                let children = displayChildren(of: node)
                let isExpanded = expanded.contains(node.span.id)
                rows.append(AskTraceRow(
                    id: node.span.id,
                    depth: depth,
                    span: node.span,
                    inlinedModel: inlined?.span,
                    hasChildren: !children.isEmpty,
                    isExpanded: isExpanded,
                    isParallel: overlapsSibling(node.span, siblings: nodes.map(\.span))
                ))
                if isExpanded { walk(children, depth: depth + 1) }
            }
        }
        walk(tree, depth: 0)
        return rows
    }

    nonisolated static func overlapsSibling(_ span: AskTraceSpan, siblings: [AskTraceSpan]) -> Bool {
        guard let end = span.end, end > span.start else { return false }
        return siblings.contains { other in
            guard other.id != span.id, let otherEnd = other.end, otherEnd > other.start else { return false }
            return span.start < otherEnd && other.start < end
        }
    }

    nonisolated static func timelineBars(turn: AskTraceTurn, compressWaits: Bool) -> [AskTraceBar] {
        let rows = visibleRows(tree: buildTree(spans: turn.spans), expanded: Set(turn.spans.map(\.id)))
        let turnEnd = turn.duration ?? turn.spans.compactMap(\.end).max() ?? 0
        let waits = compressWaits ? mergedWaits(turn.spans) : []
        func axis(_ time: TimeInterval) -> TimeInterval {
            time - waits.reduce(0) { total, wait in total + max(0, min(time, wait.end) - wait.start) }
        }
        let total = axis(turnEnd)
        guard total > 0 else {
            return rows.map { AskTraceBar(id: $0.id, depth: $0.depth, span: $0.span, x: 0, width: 0) }
        }
        return rows.map { row in
            let start = axis(row.span.start)
            let end = axis(row.span.end ?? turnEnd)
            return AskTraceBar(
                id: row.id,
                depth: row.depth,
                span: row.span,
                x: min(1, max(0, start / total)),
                width: min(1, max(0, (end - start) / total))
            )
        }
    }

    nonisolated static func mergedWaits(_ spans: [AskTraceSpan]) -> [(start: TimeInterval, end: TimeInterval)] {
        let intervals = spans
            .filter { $0.kind == .userWait }
            .compactMap { span in span.end.map { (start: span.start, end: $0) } }
            .sorted { $0.start < $1.start }
        var merged: [(start: TimeInterval, end: TimeInterval)] = []
        for interval in intervals {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// `routedVia` keeps the last value written, so a fallback replaces an earlier model attempt.
    nonisolated static func summary(turn: AskTraceTurn) -> AskTraceSummary {
        var summary = AskTraceSummary()
        for span in turn.spans {
            switch span.kind {
            case .model: summary.modelCalls += 1
            case .tool: summary.toolCalls += 1
            case .turn, .function, .userWait: break
            }
            summary.decisions += span.events.filter { $0.kind == .decision }.count
            if case .threw = span.status { summary.errors += 1 }
            if let via = span.attributes.last(where: { $0.key == "routedVia" })?.value {
                summary.routedVia = via
            }
            if let specialists = span.attributes.last(where: { $0.key == "specialists" })?.value {
                summary.specialists = specialists
            }
            if let context = span.model?.context {
                summary.totalTokens += context.usedTokens
                if context.fraction > (summary.peakContext?.fraction ?? -1) {
                    summary.peakContext = context
                }
            }
        }
        summary.userWait = mergedWaits(turn.spans).reduce(0) { $0 + ($1.end - $1.start) }
        return summary
    }
}
#endif

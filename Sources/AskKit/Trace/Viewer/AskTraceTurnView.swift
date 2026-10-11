#if DEBUG
import SwiftUI
import UIKit

struct AskTraceTurnView: View {
    @ObservedObject var viewModel: AskTraceViewModel
    let turnID: UUID
    @State private var liveCards: [AnyView]?

    var body: some View {
        VStack(spacing: 0) {
            if let turn = viewModel.turn(turnID) {
                if viewModel.tab != .story { header(turn) }
                Picker("View", selection: Binding(get: { viewModel.tab }, set: viewModel.onTabChanged)) {
                    ForEach(AskTraceViewModel.Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                switch viewModel.tab {
                case .story: story(turn)
                case .tree: tree
                case .timeline: AskTraceTimelineView(viewModel: viewModel, turnID: turnID)
                }
            } else {
                ContentUnavailableView("Trace deleted", systemImage: "trash")
            }
        }
        .navigationTitle("Turn")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Expand all") { viewModel.onExpandAll(turnID) }
                    Button("Collapse all") { viewModel.onCollapseAll(turnID) }
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .accessibilityLabel("Expand or collapse")
                Button { viewModel.onShareTapped(turnID) } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share trace")
                AskTraceInfoButton(action: viewModel.onInfoTapped)
            }
        }
        .sheet(item: Binding(get: { viewModel.share }, set: { if $0 == nil { viewModel.onShareDismissed() } })) { share in
            AskTraceActivityView(items: share.items)
        }
        .task(id: turnID) { await loadSnippetCards() }
        .onAppear { viewModel.onTurnAppear(turnID) }
    }

    private func loadSnippetCards() async {
        guard let turn = viewModel.turn(turnID), let load = viewModel.snippetCards else { return }
        liveCards = await load(turn)
    }

    private func story(_ turn: AskTraceTurn) -> some View {
        List {
            ForEach(Array(AskTraceFormatter.story(for: turn).enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 8) {
                    Text(line.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if line.title == "Snippet" {
                        snippet(line)
                    } else {
                        Text(line.text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .combine)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func snippet(_ line: AskTraceFormatter.StoryLine) -> some View {
        if let liveCards, !liveCards.isEmpty {
            ForEach(liveCards.indices, id: \.self) { index in
                liveCards[index]
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if viewModel.snippetCards != nil && liveCards == nil {
            EmptyView()
        } else if line.cards.isEmpty {
            Text(line.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(line.cards.indices, id: \.self) { index in
                AskTraceSnippetCard(card: line.cards[index])
            }
        }
    }

    private func header(_ turn: AskTraceTurn) -> some View {
        let summary = viewModel.summary(for: turn)
        let primary = [
            AskTraceFormatter.duration(turn.duration),
            "\(summary.modelCalls) model",
            "\(summary.toolCalls) tool",
            "\(summary.decisions) decisions"
        ].joined(separator: " · ")
        let secondary = [
            summary.routedVia.map(AskTraceFormatter.routeWords),
            summary.specialists,
            summary.peakContext.map { "peak \(AskTraceFormatter.contextBadge($0))" },
            summary.totalTokens > 0 ? "\(AskTraceFormatter.tokens(summary.totalTokens)) tokens" : nil,
            summary.userWait > 0 ? "waited \(AskTraceFormatter.duration(summary.userWait))" : nil
        ].compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(turn.question)
            } icon: {
                Image(systemName: AskTraceFormatter.entrySymbol(turn.entry))
                    .symbolRenderingMode(.monochrome)
            }
            .font(.headline)
            .lineLimit(3)
            Text(primary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var tree: some View {
        List(viewModel.rows(for: turnID)) { row in
            AskTraceTreeRow(row: row, onToggle: { viewModel.onToggle(row.id) })
                .background(
                    NavigationLink {
                        AskTraceSpanDetailView(viewModel: viewModel, turnID: turnID, spanID: row.id)
                    } label: { EmptyView() }
                    .opacity(0)
                )
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 12))
        }
        .listStyle(.plain)
    }
}

private struct AskTraceSnippetCard: View {
    var card: AskTracePosterCard

    private var lines: [String] {
        card.body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if card.title.caseInsensitiveCompare("Web") == .orderedSame,
           AskWebMetadata.pageAddress(in: lines) != nil {
            AskWebCard(lines: lines)
        } else {
            recorded
        }
    }

    /// Title and text kept for a turn whose card has no page image.
    private var recorded: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !card.body.isEmpty {
                Text(card.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .askCardSurface()
    }
}

private struct AskTraceTreeRow: View {
    let row: AskTraceRow
    let onToggle: () -> Void

    private var decisions: [AskTraceEvent] {
        row.span.events.filter { $0.kind == .decision }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold))
                        .frame(width: 14)
                        .opacity(row.hasChildren ? 1 : 0)
                }
                .buttonStyle(.borderless)
                .disabled(!row.hasChildren)
                .accessibilityLabel(row.isExpanded ? "Collapse" : "Expand")
                Image(systemName: AskTraceFormatter.kindSymbol(row.span.kind))
                    .foregroundStyle(AskTraceStyle.color(row.span.kind))
                    .frame(width: 18)
                Text(row.span.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if row.inlinedModel != nil {
                    Image(systemName: AskTraceFormatter.kindSymbol(.model))
                        .font(.caption2)
                        .foregroundStyle(AskTraceStyle.color(.model))
                        .accessibilityLabel("Includes model call")
                }
                if row.isParallel {
                    Text("∥")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Runs in parallel")
                }
                if case .threw = row.span.status {
                    Image(systemName: "xmark.octagon").foregroundStyle(.red).accessibilityLabel("Threw an error")
                }
                if row.span.status == .unfinished {
                    Image(systemName: "hourglass").foregroundStyle(.secondary).accessibilityLabel("Unfinished")
                }
                Spacer(minLength: 8)
                if let context = row.inlinedModel?.model?.context ?? row.span.model?.context {
                    AskTraceContextBadge(usage: context)
                }
                Text(AskTraceFormatter.duration(row.span.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Group {
                if let result = row.span.result {
                    Text("→ \(result)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ForEach(Array(decisions.prefix(2).enumerated()), id: \.offset) { _, event in
                    Label(event.message, systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                }
                if decisions.count > 2 {
                    Text("+\(decisions.count - 2) more")
                }
                if let status = AskTraceFormatter.statusText(row.span.status) {
                    Text(status).foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 44)
        }
        .padding(.leading, CGFloat(row.depth) * 12)
    }
}

struct AskTraceContextBadge: View {
    let usage: AskTraceContextUsage

    var body: some View {
        Text(AskTraceFormatter.contextBadge(usage))
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(AskTraceStyle.color(AskTraceFormatter.contextLevel(usage)))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
            .accessibilityLabel("Context \(AskTraceFormatter.contextSummary(usage))")
    }
}

enum AskTraceStyle {
    static func color(_ level: AskTraceFormatter.ContextLevel) -> Color {
        switch level {
        case .normal: return Color(.secondaryLabel)
        case .high: return Color(.systemOrange)
        case .critical: return Color(.systemRed)
        }
    }

    static func color(_ kind: AskTraceSpanKind) -> Color {
        switch kind {
        case .turn: return Color(.label)
        case .function: return Color(.systemBlue)
        case .model: return Color(.systemPurple)
        case .tool: return Color(.systemOrange)
        case .userWait: return Color(.systemGray)
        }
    }
}

struct AskTraceActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

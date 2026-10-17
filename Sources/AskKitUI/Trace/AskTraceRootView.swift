#if DEBUG
import AskKit
import AskKitIntents
import SwiftUI

struct AskTraceRootView: View {
    @ObservedObject var viewModel: AskTraceViewModel
    let showsClose: Bool
    let turnID: UUID?
    @State private var focusedTurn: UUID?
    @State private var didFocus = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: AskTraceViewModel, showsClose: Bool, turnID: UUID? = nil) {
        self.viewModel = viewModel
        self.showsClose = showsClose
        self.turnID = turnID
    }

    var body: some View {
        List {
            if viewModel.viewing.isEmpty && viewModel.turns.isEmpty {
                ContentUnavailableView(
                    "No traces yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Send a question in the chat, or drop a trace JSON here to view it. Dropped traces are not saved.")
                )
            }
            if !viewModel.viewing.isEmpty {
                Section {
                    rows(viewModel.viewing, onDelete: viewModel.onDismissViewing)
                } header: {
                    Text("Viewing")
                } footer: {
                    Text("These stay on this screen until you swipe them away. They are not saved with the last 20.")
                }
            }
            if !viewModel.turns.isEmpty {
                if viewModel.viewing.isEmpty {
                    rows(viewModel.turns, onDelete: viewModel.onDeleteTurn)
                } else {
                    Section {
                        rows(viewModel.turns, onDelete: viewModel.onDeleteTurn)
                    } header: {
                        Text("Traces")
                    }
                }
            }
        }
#if !os(tvOS) && !os(watchOS)
        .dropDestination(for: URL.self) { (urls: [URL], _: CGPoint) -> Bool in
            viewModel.onDrop(urls: urls)
        }
        .dropDestination(for: Data.self) { payloads, _ in
            var accepted = false
            for data in payloads where viewModel.onImport(data) {
                accepted = true
            }
            return accepted
        }
#endif
        .navigationDestination(item: $focusedTurn) { id in
            AskTraceTurnView(viewModel: viewModel, turnID: id)
        }
        .task {
            guard !didFocus, let turnID else { return }
            didFocus = true
            if viewModel.turns.isEmpty { viewModel.onAppear() }
            focusedTurn = turnID
        }
        .navigationTitle("Ask Trace")
        .askInlineTitle()
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .askLeading) {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .askTrailing) {
                AskTraceInfoButton(action: viewModel.onInfoTapped)
            }
            ToolbarItem(placement: .askTrailing) {
                Button(role: .destructive, action: viewModel.onClearTapped) {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.turns.isEmpty)
                .accessibilityLabel("Clear all traces")
            }
        }
        .sheet(isPresented: Binding(get: { viewModel.isGuidePresented }, set: { if !$0 { viewModel.onGuideDismissed() } })) {
            AskTraceGuideView()
        }
        .onAppear(perform: viewModel.onAppear)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.onForeground() }
        }
    }

    private func rows(_ turns: [AskTraceTurn], onDelete: @escaping (UUID) -> Void) -> some View {
        ForEach(turns) { turn in
            NavigationLink {
                AskTraceTurnView(viewModel: viewModel, turnID: turn.id)
            } label: {
                AskTraceTurnRow(turn: turn, summary: viewModel.summary(for: turn))
            }
        }
        .onDelete { offsets in
            offsets.map { turns[$0].id }.forEach(onDelete)
        }
    }
}

private struct AskTraceTurnRow: View {
    let turn: AskTraceTurn
    let summary: AskTraceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: AskTraceFormatter.entrySymbol(turn.entry))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.tint)
                Text(turn.question)
                    .font(.body)
                    .lineLimit(2)
            }
            Text(AskTraceFormatter.listSentence(for: turn))
                .font(.caption)
                .foregroundStyle(.secondary)
            if summary.errors > 0 {
                Label("\(summary.errors)", systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(summary.errors) errors")
            }
        }
        .padding(.vertical, 2)
    }
}
#endif

#if DEBUG
import SwiftUI

struct AskTraceTimelineView: View {
    @ObservedObject var viewModel: AskTraceViewModel
    let turnID: UUID

    var body: some View {
        let bars = viewModel.bars(for: turnID)
        List {
            Section {
                Toggle(
                    "Compress waits",
                    isOn: Binding(get: { viewModel.compressUserWaits }, set: viewModel.onCompressWaitsChanged)
                )
                .font(.footnote)
                AskTraceTimelineAxis(total: axisTotal)
            }
            Section {
                ForEach(bars) { bar in
                    NavigationLink {
                        AskTraceSpanDetailView(viewModel: viewModel, turnID: turnID, spanID: bar.id)
                    } label: {
                        AskTraceTimelineRow(bar: bar)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var axisTotal: TimeInterval? {
        guard let turn = viewModel.turn(turnID), let duration = turn.duration else { return nil }
        let summary = viewModel.summary(for: turn)
        return viewModel.compressUserWaits ? duration - summary.userWait : duration
    }
}

private struct AskTraceTimelineAxis: View {
    let total: TimeInterval?

    var body: some View {
        HStack {
            ForEach(0..<5) { tick in
                Text(label(Double(tick) / 4))
                    .frame(maxWidth: .infinity, alignment: tick == 0 ? .leading : (tick == 4 ? .trailing : .center))
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func label(_ fraction: Double) -> String {
        guard let total else { return "" }
        return AskTraceFormatter.duration(total * fraction)
    }
}

private struct AskTraceTimelineRow: View {
    let bar: AskTraceBar
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: AskTraceFormatter.rowSymbol(bar.span))
                    .foregroundStyle(AskTraceStyle.color(AskTraceFormatter.recordedSymbol(bar.span) == nil ? bar.span.kind : .model))
                Text(bar.span.name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(AskTraceFormatter.duration(bar.span.duration)).foregroundStyle(.secondary)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.leading, CGFloat(min(bar.depth, 8)) * 8)
            GeometryReader { proxy in
                let isWait = bar.span.kind == .userWait
                let isError: Bool = {
                    if case .threw = bar.span.status { return true }
                    return false
                }()
                RoundedRectangle(cornerRadius: 3)
                    .fill(AskTraceStyle.color(bar.span.kind).opacity(isWait ? 0.35 : 0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(isError ? Color(.systemRed) : .clear, lineWidth: 1.5)
                    )
                    .frame(width: max(3, proxy.size.width * bar.width), height: barHeight)
                    .offset(x: min(proxy.size.width - 3, proxy.size.width * bar.x))
            }
            .frame(height: barHeight)
            .background(Color(.quaternarySystemFill).clipShape(RoundedRectangle(cornerRadius: 3)))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
#endif

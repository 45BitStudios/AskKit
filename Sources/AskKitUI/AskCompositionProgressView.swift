#if !os(watchOS)
import AskKit
import SwiftUI

/// Checklist for a generative card run: Understand request, Search, Prepare data, Write layout.
/// Finished rows show how long that step took. Reduce Motion keeps the active mark still.
public struct AskCompositionProgressView: View {
    public var snapshot: AskCompositionSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(snapshot: AskCompositionSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.steps) { step in
                AskCompositionStepRow(step: step, reduceMotion: reduceMotion)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AskCompositionStepRow: View {
    var step: AskCompositionStep
    var reduceMotion: Bool

    var body: some View {
        HStack(spacing: 8) {
            marker
            Text(step.phase.title)
                .font(.subheadline.weight(step.state == .active ? .semibold : .regular))
                .foregroundStyle(isQuiet ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
            Spacer(minLength: 8)
            if let timing = step.timingLabel {
                Text(timing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.accessibilityLabel)
    }

    private var isQuiet: Bool {
        step.state == .waiting || step.state == .skipped
    }

    @ViewBuilder
    private var marker: some View {
        Group {
            switch step.state {
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .active:
                if reduceMotion {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            case .skipped:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
            case .waiting:
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// Redacted stand-in for a generative card. Shown until the composed tree replaces it.
/// It is the real card layout, so the placeholder is the same size as the card that replaces it.
/// Reduce Motion leaves the shimmer off. VoiceOver hears one Loading label.
public struct AskGeneratedCardPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    public init() {}

    public var body: some View {
        AskGeneratedCardView(root: Self.standIn, title: "Card")
            .redacted(reason: .placeholder)
            .overlay { shimmer }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
            .onAppear(perform: startShimmer)
            .onChange(of: reduceMotion) { _, _ in
                startShimmer()
            }
    }

    /// Same kinds the renderer draws: a mark, a hero, and a line. Redaction hides the words.
    private static let standIn = AskCardNode(
        kind: "vstack",
        children: [
            AskCardNode(kind: "badge", text: "Card"),
            AskCardNode(kind: "stat", text: "00", detail: "Detail"),
            AskCardNode(kind: "text", text: "Line")
        ]
    )

    @ViewBuilder
    private var shimmer: some View {
        if !reduceMotion {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.18), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * 0.45)
                .offset(x: phase * proxy.size.width)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func startShimmer() {
        phase = -0.6
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            phase = 1.35
        }
    }
}
#endif

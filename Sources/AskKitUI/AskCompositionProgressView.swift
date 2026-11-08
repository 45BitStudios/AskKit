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
/// Reduce Motion leaves the bars still.
public struct AskGeneratedCardPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.askCardStyle) private var style
    @State private var phase: CGFloat = -0.6

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: style.contentSpacing) {
            HStack(spacing: 8) {
                Text("Card")
                    .font(.caption.weight(.semibold))
                Text("Title")
                    .font(.caption.weight(.semibold))
            }
            Text("00")
                .font(style.displayFont)
            Text("A detail line from the facts")
                .font(style.detailFont)
            Text("Another short line")
                .font(style.detailFont)
        }
        .redacted(reason: .placeholder)
        .askCardSurface()
        .overlay { shimmer }
        .clipShape(AskCardStyle.shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Creating the card")
        .onAppear(perform: startShimmer)
        .onChange(of: reduceMotion) { _, _ in
            startShimmer()
        }
    }

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

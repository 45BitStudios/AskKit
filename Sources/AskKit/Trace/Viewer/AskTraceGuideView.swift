#if DEBUG
import SwiftUI

struct AskTraceInfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
        }
        .accessibilityLabel("How tracing works")
    }
}

struct AskTraceGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 30

    var body: some View {
        NavigationStack {
            List {
                ForEach(AskTraceGuide.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            row(item)
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if let footer = section.footer { Text(footer) }
                    }
                }
            }
            .navigationTitle("How tracing works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ item: AskTraceGuide.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let symbol = item.symbol {
                AskTraceGuideSymbol(symbol: symbol)
                    .frame(minWidth: symbolWidth, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct AskTraceGuideSymbol: View {
    let symbol: AskTraceGuide.Symbol

    var body: some View {
        switch symbol {
        case .entry(let entry):
            Image(systemName: AskTraceFormatter.entrySymbol(entry))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.tint)
        case .kind(let kind):
            Image(systemName: AskTraceFormatter.kindSymbol(kind))
                .foregroundStyle(AskTraceStyle.color(kind))
        case .system(let name, let tint):
            Image(systemName: name).foregroundStyle(color(tint))
        case .glyph(let text):
            Text(text).font(.body.weight(.bold)).foregroundStyle(.secondary)
        case .contextBadge(let usage):
            AskTraceContextBadge(usage: usage).fixedSize()
        }
    }

    private func color(_ tint: AskTraceGuide.Tint) -> Color {
        switch tint {
        case .accent: return .accentColor
        case .secondary: return Color(.secondaryLabel)
        case .red: return Color(.systemRed)
        case .purple: return Color(.systemPurple)
        }
    }
}
#endif

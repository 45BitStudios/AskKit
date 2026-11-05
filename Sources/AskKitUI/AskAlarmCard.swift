#if !os(watchOS)
import AskKit
import AskKitIntents
import Foundation
import SwiftUI

struct AskAlarmCard: View {
    var item: AskAlarmLine.Item

    private var customized: Bool {
        if let label = item.label, !label.isEmpty { return true }
        if let symbol = item.symbol, !symbol.isEmpty { return true }
        return false
    }

    private var buttonSymbol: String {
        item.symbol ?? "bell.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AskCardMark(
                title: customized ? "Custom" : "Alarm",
                symbol: customized ? buttonSymbol : "alarm.fill",
                tint: .orange
            )
            Text(item.time)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            if item.repeats != "once" {
                Text(item.repeats)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if item.state == "paused" {
                Text("paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let label = item.label, !label.isEmpty {
                Label(label, systemImage: buttonSymbol)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .accessibilityLabel("Alarm button, \(label)")
            } else if let symbol = item.symbol, !symbol.isEmpty {
                Label("Custom", systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.16), in: Capsule())
                    .accessibilityLabel("Alarm button, custom symbol \(symbol)")
            }
        }
        .askCardSurface()
        .accessibilityElement(children: .combine)
    }
}
#endif

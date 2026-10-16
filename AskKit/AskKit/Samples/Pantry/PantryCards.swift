import AskKit
import SwiftUI

struct DinnerCard: View {
    let name: String
    let minutes: String
    let servings: String
    let onHand: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AskCardMark(title: "Dinner", symbol: "fork.knife", tint: .orange)
            Text(name)
                .font(.headline)
            Text("\(minutes) min")
                .font(.title2.weight(.semibold))
            Text("Serves \(servings) · \(onHand)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .askCardSurface()
    }
}

struct StockCard: View {
    let onHand: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AskCardMark(title: "Pantry", symbol: "shippingbox.fill", tint: .green)
            Text("On hand")
                .font(.title2.weight(.semibold))
            Text(onHand.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .askCardSurface()
    }
}

struct ShoppingCard: View {
    let missing: String
    let market: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AskCardMark(title: "Shopping list", symbol: "cart.fill", tint: .orange)
            Text(missing.capitalized)
                .font(.title2.weight(.semibold))
            Text(market.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .askCardSurface()
    }
}

import SwiftUI

struct DinnerCard: View {
    let name: String
    let minutes: String
    let servings: String
    let onHand: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text("\(minutes) min")
                .font(.title2.weight(.semibold))
            Text("Serves \(servings) · \(onHand)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StockCard: View {
    let onHand: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pantry")
                .font(.headline)
            Text("On hand")
                .font(.title2.weight(.semibold))
            Text(onHand.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ShoppingCard: View {
    let missing: String
    let market: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shopping list")
                .font(.headline)
            Text(missing.capitalized)
                .font(.title2.weight(.semibold))
            Text(market.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

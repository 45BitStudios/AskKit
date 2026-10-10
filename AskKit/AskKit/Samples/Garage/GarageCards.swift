import SwiftUI

struct ChargeCard: View {
    let vehicle: String
    let battery: String
    let minutesTo80: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vehicle)
                .font(.headline)
            Text(battery)
                .font(.title2.weight(.semibold))
            Text("Charging at home · \(minutesTo80) min to 80%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RangeCard: View {
    let vehicle: String
    let range: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vehicle)
                .font(.headline)
            Text(range)
                .font(.title2.weight(.semibold))
            Text("Eco mode is on")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ChargerCard: View {
    let name: String
    let distance: String
    let openStalls: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
            Text(distance)
                .font(.title2.weight(.semibold))
            Text("150 kW · \(openStalls) stalls open")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ClimateCard: View {
    let vehicle: String
    let cabin: String
    let departure: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vehicle)
                .font(.headline)
            Text(cabin)
                .font(.title2.weight(.semibold))
            Text("Ready at \(departure)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

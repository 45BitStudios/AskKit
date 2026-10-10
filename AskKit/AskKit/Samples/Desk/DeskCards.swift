import SwiftUI

struct PassCard: View {
    let guest: String
    let host: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Visitor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(guest)
                .font(.title2.weight(.semibold))
            Text("Host \(host) · valid today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RoomCard: View {
    let room: String
    let freeUntil: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meeting room")
                .font(.headline)
            Text(room)
                .font(.title2.weight(.semibold))
            Text("Free until \(freeUntil)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

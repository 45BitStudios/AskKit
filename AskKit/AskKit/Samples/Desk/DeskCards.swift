import AskKit
import SwiftUI

struct PassCard: View {
    let guest: String
    let host: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AskCardMark(title: "Visitor", symbol: "person.fill", tint: .blue)
            Text(guest)
                .font(.title2.weight(.semibold))
            Text("Host \(host) · valid today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .askCardSurface()
    }
}

struct RoomCard: View {
    let room: String
    let freeUntil: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AskCardMark(title: "Meeting room", symbol: "door.left.hand.open", tint: .indigo)
            Text(room)
                .font(.title2.weight(.semibold))
            Text("Free until \(freeUntil)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .askCardSurface()
    }
}

import AskKit
import SwiftUI

/// One card layout for the extra sample skills.
struct SampleFactCard: View {
    let title: String
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AskCardMark(title: title, symbol: "sparkles", tint: .indigo)
            Text(headline)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .askCardSurface()
    }
}

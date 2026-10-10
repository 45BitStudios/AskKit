import SwiftUI

/// One card layout for the extra sample skills.
struct SampleFactCard: View {
    let title: String
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                    Text(title)
                        .lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(red: 0.28, green: 0.24, blue: 0.52))
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(Color(.secondarySystemBackground))
                    Capsule().fill(Color.indigo.opacity(0.22))
                }
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

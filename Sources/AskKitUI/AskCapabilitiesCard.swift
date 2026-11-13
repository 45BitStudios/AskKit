#if !os(watchOS)
import AskKit
import AskKitIntents
import Foundation
import SwiftUI

/// The card under a capabilities answer. The bubble above it is a separate sentence.
/// Layout follows ``AskCardStyle`` so snippet, chat, and full screen stay one card that zooms.
public struct AskCapabilitiesCard: View {
    public var groups: [AskCapabilityGroup]

    @Environment(\.askCardStyle) private var style
    @Environment(\.askTint) private var askTint

    public init(groups: [AskCapabilityGroup]) {
        self.groups = groups
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: style == .fullScreen ? 14 : 10) {
            AskCardMark(title: "Help", symbol: "sparkles", tint: askTint ?? .accentColor)
            ForEach(style == .fullScreen ? groups : Array(groups.prefix(1))) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                    ForEach(group.items) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.subheadline)
                            if !item.detail.isEmpty, style == .fullScreen {
                                Text(item.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .askCardSurface()
    }
}
#endif

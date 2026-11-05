#if !os(watchOS)
import AskKit
import AskKitIntents
import Foundation
import SwiftUI

/// Page title, address, and summary, with the preview image and the site icon when they can be loaded.
struct AskWebCard: View {
    var lines: [String]

    @State private var hero: AskPlatformImage?
    @State private var icon: AskPlatformImage?
    @Environment(\.askCardStyle) private var style

    private var title: String {
        lines.first ?? "Web"
    }

    private var detail: String {
        lines.dropFirst().joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AskCardMark(title: "Web", symbol: "globe", tint: .blue)
            if style == .fullScreen, let hero {
                Image(askImage: hero)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 8) {
                if let icon {
                    Image(askImage: icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(style == .fullScreen ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(style == .fullScreen ? nil : 2)
            }
        }
        .askCardSurface()
        .task(id: AskWebMetadata.pageAddress(in: lines) ?? "") {
            await load()
        }
    }

    private func load() async {
        let address = AskWebMetadata.pageAddress(in: lines) ?? ""
        let cached = await AskWebPictures.pictures(for: address)
        if let url = cached?.image {
            hero = Self.image(await AskWebPictures.imageData(at: url))
        }
        if let url = cached?.icon {
            icon = Self.image(await AskWebPictures.imageData(at: url))
        }
        guard hero == nil || icon == nil, !Task.isCancelled else { return }
        let page = cached?.page ?? Self.pageURL(address)
        guard let page else { return }
        let fetched = await AskWebPictures.presentation(for: page)
        if hero == nil {
            hero = Self.image(fetched.image)
        }
        if icon == nil {
            icon = Self.image(fetched.icon)
        }
    }

    private static func image(_ data: Data?) -> AskPlatformImage? {
        guard let data, data.count > 32, data.count <= 3_000_000 else { return nil }
        return AskPlatformImage(data: data)
    }

    private static func pageURL(_ address: String) -> URL? {
        guard let url = URL(string: address), AskWebMetadata.allowed(url) else { return nil }
        return url
    }
}
#endif

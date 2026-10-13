import SwiftUI

/// Recursive SwiftUI renderer for ``AskCardNode`` trees.
/// Layout follows ``AskCardStyle`` so snippet, chat, and full screen stay one card that zooms.
public struct AskGeneratedCardView: View {
    public var root: AskCardNode
    /// Used for the type badge tint when the tree includes a badge.
    public var title: String

    @Environment(\.askCardStyle) private var style

    public init(root: AskCardNode, title: String = "") {
        self.root = root
        self.title = title
    }

    public var body: some View {
        nodeView(root)
            .askCardSurface(tint: AskCardSymbol.tint(for: title.isEmpty ? badgeTitle : title))
    }

    private var badgeTitle: String {
        firstBadge(in: root) ?? title
    }

    @ViewBuilder
    private func nodeView(_ node: AskCardNode) -> some View {
        switch AskCardNodeKind.parse(node.kind) ?? .text {
        case .vstack:
            VStack(alignment: .leading, spacing: style.contentSpacing) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    nodeView(child)
                }
            }
        case .hstack:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    if AskCardNodeKind.parse(child.kind) == .stat || AskCardNodeKind.parse(child.kind) == .text {
                        nodeView(child)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        nodeView(child)
                    }
                }
            }
        case .text:
            Text(node.text)
                .font(style.detailFont)
                .foregroundStyle(.secondary)
                .lineLimit(style.detailLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .stat:
            VStack(alignment: .leading, spacing: 2) {
                Text(node.text)
                    .font(style.valueFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !node.detail.isEmpty {
                    Text(node.detail)
                        .font(style.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(style.detailLineLimit)
                }
            }
        case .badge:
            AskCardBadge(
                title: node.text,
                symbol: AskCardSymbol.symbol(for: node.text),
                tint: AskCardSymbol.tint(for: node.text)
            )
        case .divider:
            Divider()
        case .spacer:
            Spacer(minLength: style.contentSpacing)
        case .row:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(node.text)
                    .font(style.detailFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(node.detail)
                    .font(style.detailFont.weight(.semibold))
            }
        case .action:
            EmptyView()
        }
    }

    private func firstBadge(in node: AskCardNode) -> String? {
        if AskCardNodeKind.parse(node.kind) == .badge {
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        for child in node.children {
            if let found = firstBadge(in: child) { return found }
        }
        return nil
    }
}

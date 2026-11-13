#if !os(watchOS)
import AskKit
import AskKitIntents
import SwiftUI

/// Recursive SwiftUI renderer for ``AskCardNode`` trees.
/// Layout follows ``AskCardStyle`` so snippet, chat, and full screen stay one card that zooms.
public struct AskGeneratedCardView: View {
    public var root: AskCardNode
    /// Used for the type badge tint when the tree includes a badge.
    public var title: String

    public init(root: AskCardNode, title: String = "") {
        self.root = root
        self.title = title
    }

    @Environment(\.askCardStyle) private var style
    @Environment(\.tint) private var hostTint: Color?

    private var accent: Color { hostTint ?? .accentColor }

    public var body: some View {
        VStack(alignment: .leading, spacing: style.contentSpacing) {
            AskCardMark(title: markTitle, symbol: markSymbol, tint: markTint)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(markTitle)
            if let shown = presented(root, compact: style != .fullScreen) {
                AskGeneratedNodeView(node: shown)
            }
        }
        .askCardSurface()
    }

    private var markTitle: String {
        AskGeneratedCardAccessibility.badge(firstBadge(in: root) ?? "", title: title)
    }

    private var markSymbol: String {
        if let plate = first(kind: .plate, in: root), let name = AskCardSymbol.systemName(for: plate) {
            return name
        }
        return AskCardSymbol.symbol(for: markTitle)
    }

    private var markTint: Color {
        AskCardSymbol.tint(for: markSymbol == "sparkles" ? markTitle : markSymbol, accent: accent)
    }

    /// Chat keeps the hero. Full screen keeps the figures and rows. The plate and badge are the mark.
    private func presented(_ node: AskCardNode, compact: Bool) -> AskCardNode? {
        guard let kind = AskCardNodeKind.parse(node.kind) else { return nil }
        if kind == .plate || kind == .badge || kind == .action { return nil }
        if compact, kind == .symbol || kind == .figure || kind == .row { return nil }
        if kind == .vstack || kind == .hstack {
            let children = node.children.compactMap { presented($0, compact: compact) }
            guard !children.isEmpty else { return nil }
            if children.count == 1, kind == .hstack { return children[0] }
            return AskCardNode(kind: kind.rawValue, children: children)
        }
        return node
    }

    private func first(kind: AskCardNodeKind, in node: AskCardNode) -> String? {
        if AskCardNodeKind.parse(node.kind) == kind {
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        for child in node.children {
            if let found = first(kind: kind, in: child) { return found }
        }
        return nil
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

/// One DSL node. A separate view so a child can be the same type without an opaque function calling itself.
private struct AskGeneratedNodeView: View {
    var node: AskCardNode

    @Environment(\.askCardStyle) private var style

    var body: some View {
        switch AskCardNodeKind.parse(node.kind) ?? .text {
        case .vstack:
            VStack(alignment: centersStack ? .center : .leading, spacing: style.contentSpacing) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    AskGeneratedNodeView(node: child)
                }
            }
        case .hstack:
            HStack(alignment: centersStack ? .center : .firstTextBaseline, spacing: 12) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    AskGeneratedNodeRow(node: child)
                }
            }
        case .text:
            AskGeneratedText(text: node.text, font: style.detailFont, lineLimit: style.detailLineLimit)
        case .eyebrow:
            Text(node.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .stat:
            VStack(alignment: .leading, spacing: 2) {
                Text(node.text)
                    .modifier(AskCardScaledFont(
                        base: style.displayMetric.base,
                        relativeTo: style.displayMetric.relativeTo
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !node.detail.isEmpty {
                    Text(node.detail)
                        .font(style.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(style.detailLineLimit)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AskGeneratedCardAccessibility.stat(text: node.text, detail: node.detail))
        case .figure:
            VStack(alignment: .center, spacing: 2) {
                Text(node.text)
                    .font(style.titleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !node.detail.isEmpty {
                    Text(node.detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AskGeneratedCardAccessibility.figure(text: node.text, detail: node.detail))
        case .quote:
            Text(node.text)
                .font(style.quoteFont)
                .foregroundStyle(.primary)
                .lineLimit(style == .snippet ? 3 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .badge:
            EmptyView()
        case .plate:
            if let name = AskCardSymbol.systemName(for: node.text) {
                AskGeneratedPlate(
                    name: name,
                    base: style.plateMetric.base,
                    relativeTo: style.plateMetric.relativeTo
                )
            }
        case .symbol:
            if let name = AskCardSymbol.systemName(for: node.text) {
                let metric = node.detail.lowercased() == "mini" ? style.miniMetric : style.heroMetric
                AskGeneratedGlyph(name: name, base: metric.base, relativeTo: metric.relativeTo)
            }
        case .divider:
            Divider()
        case .spacer:
            Spacer(minLength: style.contentSpacing)
        case .row:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(node.text)
                    .font(style.detailFont.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(node.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AskGeneratedCardAccessibility.row(text: node.text, detail: node.detail))
        case .action:
            EmptyView()
        }
    }

    /// A symbol or plate in the stack should sit on the center axis, like a widget tile.
    private var centersStack: Bool {
        node.children.contains { child in
            switch AskCardNodeKind.parse(child.kind) {
            case .plate, .symbol: true
            default: false
            }
        }
    }
}

/// Stat and text rows take the remaining width. Other children stay at their natural size.
private struct AskGeneratedNodeRow: View {
    var node: AskCardNode

    var body: some View {
        switch AskCardNodeKind.parse(node.kind) {
        case .stat, .text, .figure, .quote, .eyebrow, .vstack:
            AskGeneratedNodeView(node: node)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            AskGeneratedNodeView(node: node)
        }
    }
}

/// Rounded artwork tile. The symbol is font-sized so multicolor marks stay painted.
private struct AskGeneratedPlate: View {
    var name: String
    @ScaledMetric var size: CGFloat
    @Environment(\.tint) private var hostTint: Color?

    init(name: String, base: CGFloat, relativeTo: Font.TextStyle) {
        self.name = name
        _size = ScaledMetric(wrappedValue: base, relativeTo: relativeTo)
    }

    var body: some View {
        let tint = AskCardSymbol.tint(for: name, accent: hostTint ?? .accentColor)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint, tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: name)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            .accessibilityHidden(true)
    }
}

/// Palette SF Symbol. Font size, not a resized image, so weather marks keep their colors.
private struct AskGeneratedGlyph: View {
    var name: String
    @ScaledMetric var size: CGFloat
    @Environment(\.tint) private var hostTint: Color?

    init(name: String, base: CGFloat, relativeTo: Font.TextStyle) {
        self.name = name
        _size = ScaledMetric(wrappedValue: base, relativeTo: relativeTo)
    }

    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                AskGeneratedGlyphInk.primary(name, accent: hostTint ?? .accentColor),
                AskGeneratedGlyphInk.secondary(name, accent: hostTint ?? .accentColor)
            )
            .font(.system(size: size))
            .accessibilityHidden(true)
    }
}

private enum AskGeneratedGlyphInk {
    static func primary(_ name: String, accent: Color) -> Color {
        let key = name.lowercased()
        if key.contains("moon") || (key.contains("sun") && !key.contains("cloud")) { return .yellow }
        if key.contains("cloud") { return Color.gray }
        return AskCardSymbol.tint(for: name, accent: accent)
    }

    static func secondary(_ name: String, accent: Color) -> Color {
        let key = name.lowercased()
        if key.contains("moon") { return .indigo }
        if key.contains("sun") { return .orange }
        if key.contains("rain") || key.contains("drizzle") { return .blue }
        if key.contains("snow") { return .cyan }
        if key.contains("bolt") { return .yellow }
        return AskCardSymbol.tint(for: name, accent: accent).opacity(0.7)
    }
}

/// Hero type at `base` for the default content size. `relativeTo` is what Dynamic Type scales.
private struct AskCardScaledFont: ViewModifier {
    var weight: Font.Weight
    var design: Font.Design
    @ScaledMetric var size: CGFloat

    init(
        base: CGFloat,
        relativeTo: Font.TextStyle,
        weight: Font.Weight = .semibold,
        design: Font.Design = .rounded
    ) {
        self.weight = weight
        self.design = design
        _size = ScaledMetric(wrappedValue: base, relativeTo: relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

/// Kinds ``AskGeneratedNodeView`` has a case for.
/// The primitive test fails when a ``AskCardNodeKind`` is missing here.
enum AskGeneratedCardRender {
    static func draws(_ kind: AskCardNodeKind) -> Bool {
        switch kind {
        case .vstack, .hstack, .text, .eyebrow, .stat, .figure, .quote, .badge, .plate, .symbol, .divider, .spacer, .row, .action:
            true
        }
    }
}

private struct AskGeneratedText: View {
    var text: String
    var font: Font
    var lineLimit: Int?

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

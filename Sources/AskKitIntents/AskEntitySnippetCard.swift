#if !os(watchOS)
import AppIntents
import AskKit
import SwiftUI

extension AskSnippetAccent {
    /// The accent drawn on the symbol plate and the buttons.
    var snippetColor: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// The Siri card for one `AskSnippetCard`.
///
/// watchOS does not compile this view. AskKitUI is already left out of that build, and this card follows it.
/// Siri supplies the card chrome, so this view does not paint its own fill.
public struct AskEntitySnippetCard: View {
    public var card: AskSnippetCard

    public init(card: AskSnippetCard) {
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch card.shape {
            case .detail:
                detail
            case .list:
                list
            case .row:
                row
            }
            if card.showsActions {
                actionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                mark(side: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.headline)
                        .lineLimit(card.titleLineLimit)
                    if let subtitle = card.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(card.subtitleLineLimit)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            ForEach(card.primaryFields) { field in
                fieldLine(field, prominent: true)
            }
            ForEach(card.secondaryFields) { field in
                fieldLine(field, prominent: false)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let symbol = card.symbolName {
                    Image(systemName: symbol)
                        .foregroundStyle(card.accent.snippetColor)
                        .accessibilityHidden(true)
                }
                Text(card.title)
                    .font(.headline)
                    .lineLimit(card.titleLineLimit)
            }
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(card.subtitleLineLimit)
            }
            ForEach(card.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: row.symbolName ?? "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(card.accent.snippetColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.subheadline)
                            .lineLimit(card.bodyLineLimit)
                        if let subtitle = row.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(card.bodyLineLimit)
                        }
                    }
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            mark(side: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(card.titleLineLimit)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(card.subtitleLineLimit)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func mark(side: CGFloat) -> some View {
        if card.showsImage, let imageName = card.imageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        } else if let symbol = card.symbolName {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(card.accent.snippetColor)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: side * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(card.accent.snippetColor)
                .frame(width: 4, height: side)
                .accessibilityHidden(true)
        }
    }

    private func fieldLine(_ field: AskSnippetField, prominent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol = field.symbolName {
                Image(systemName: symbol)
                    .foregroundStyle(prominent ? AnyShapeStyle(card.accent.snippetColor) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
            if !field.title.isEmpty {
                Text(field.title)
                    .foregroundStyle(.secondary)
            }
            Text(field.value)
                .fontWeight(prominent ? .semibold : .regular)
                .foregroundStyle(prominent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .font(.subheadline)
        .lineLimit(card.bodyLineLimit)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ForEach(card.actions) { action in
                actionControl(action)
            }
        }
        .buttonStyle(.bordered)
        .font(.caption)
        .tint(card.accent.snippetColor)
    }

    @ViewBuilder
    private func actionControl(_ action: AskSnippetAction) -> some View {
        let request = AskSnippetActionRequest(
            entityType: card.entityType,
            entityID: card.entityID,
            actionID: action.id,
            role: action.role
        )
        let label = Label(action.title, systemImage: action.resolvedSymbolName)
        if action.role == .open {
            Button(intent: AskSnippetOpenIntent(request: request)) {
                label
            }
        } else {
            Button(intent: AskSnippetButtonIntent(request: request)) {
                label
            }
        }
    }
}
#endif

#if !os(watchOS)
import AppIntents
import AskKit
import AskKitIntents
import AskKitSurface
import Foundation
import MapKit
import SwiftUI

/// Title, value, and detail via the card DSL renderer. Same shape as the sample fact cards.
struct AskAppleFactCard: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        AskGeneratedCardView(
            root: AskGeneratedCard.factTree(title: title, value: value, detail: detail),
            title: title
        )
    }
}

/// One person. Phone and email both stay on the card.
struct AskContactCard: View {
    var person: AskContactLine.Person

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AskCardMark(title: "Contact", symbol: "person.fill", tint: monogram)
            HStack(alignment: .top, spacing: 14) {
            Text(initials)
                .font(.headline)
                .foregroundStyle(monogram)
                .frame(width: 56, height: 56)
                .background(monogram.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(person.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !person.phone.isEmpty {
                    contactAction(
                        title: person.phone,
                        symbol: "phone.fill",
                        intent: AskCallTap(phone: person.phone),
                        accessibilityLabel: Text("Call \(person.name)"),
                        secondary: false
                    )
                }
                if !person.email.isEmpty {
                    contactAction(
                        title: person.email,
                        symbol: "envelope.fill",
                        intent: AskEmailTap(email: person.email),
                        accessibilityLabel: Text("Email \(person.name)"),
                        secondary: true
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .askCardSurface()
    }

    private func contactAction<I: AppIntent>(
        title: String,
        symbol: String,
        intent: I,
        accessibilityLabel: Text,
        secondary: Bool
    ) -> some View {
        Button(intent: intent) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(secondary ? Color.secondary : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var initials: String {
        let letters = person.name.split(separator: " ").prefix(2).compactMap(\.first)
        let text = String(letters).uppercased()
        return text.isEmpty ? "?" : text
    }

    /// Stable across launches. `hashValue` is not.
    private var monogram: Color {
        let palette: [Color] = [.blue, .teal, .indigo, .purple, .orange, .pink]
        let sum = person.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// The location card. The map is the answer. Coordinates stay hidden until the question asked for them.
struct AskLocationMapCard: View {
    var title: String
    var places: [AskLocationPin.Place]
    var showsCoordinates: Bool

    @Environment(\.askSnippet) private var snippet
    @Environment(\.askCardStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AskCardMark(title: "Place", symbol: "mappin.and.ellipse", tint: .green)
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            map
            ForEach(places) { place in
                AskLocationPlaceRow(
                    place: place,
                    showsCoordinates: showsCoordinates,
                    inlineDirections: places.count > 1
                )
            }
        }
        .askCardSurface()
    }

    @ViewBuilder
    private var map: some View {
        let label = places.map(\.shortName).joined(separator: ", ")
        if snippet.isSnippet {
            // A MapKit snapshot here never returns to Siri, so the dialog disappears with it.
            AskSnippetMapPicture(label: label)
        } else {
            Map(initialPosition: .region(AskLocationRegion.region(for: places))) {
                ForEach(places) { place in
                    Marker(place.shortName, coordinate: place.coordinate)
                }
            }
            .mapStyle(.standard)
            .frame(height: style == .fullScreen ? 320 : 120)
            .clipShape(RoundedRectangle(cornerRadius: AskCardRadius.large, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityLabel(label)
        }
    }
}

/// Place row for the shortcut. MapKit's snapshot call does not return while Siri is waiting, so this stays a symbol and the name.
struct AskSnippetMapPicture: View {
    var label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(AskPlatform.secondaryFill, in: RoundedRectangle(cornerRadius: AskCardRadius.large, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One place under the map, with its own directions button. Several places keep the button beside the name.
struct AskLocationPlaceRow: View {
    var place: AskLocationPin.Place
    var showsCoordinates: Bool
    var inlineDirections: Bool

    var body: some View {
        if inlineDirections {
            HStack(alignment: .center, spacing: 12) {
                AskLocationPlaceText(place: place, showsCoordinates: showsCoordinates, splitsAddress: true)
                directions(title: "Directions", expands: false, showsTitle: false)
                    .layoutPriority(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                AskLocationPlaceText(place: place, showsCoordinates: showsCoordinates, splitsAddress: false)
                directions(title: "Get Directions", expands: true, showsTitle: true)
            }
        }
    }

    private func directions(title: LocalizedStringKey, expands: Bool, showsTitle: Bool) -> some View {
        AskCardCTA(
            title: title,
            symbol: "arrow.triangle.turn.up.right.diamond.fill",
            intent: AskDirectionsTap(
                place: place.shortName,
                latitude: place.latitude,
                longitude: place.longitude
            ),
            accessibilityLabel: Text("Get directions to \(place.shortName)"),
            expands: expands,
            showsTitle: showsTitle
        )
    }
}

/// Place name, and the address under it when a card lists more than one place.
private struct AskLocationPlaceText: View {
    var place: AskLocationPin.Place
    var showsCoordinates: Bool
    var splitsAddress: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(splitsAddress ? place.shortName : place.label)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if splitsAddress, !place.address.isEmpty {
                Text(place.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsCoordinates {
                Text(AskLocationPin.format(place))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Each reminder. A circle completes it. The filled check opens it again.
struct AskReminderCard: View {
    var title: String
    var items: [AskReminderItem.Item]
    /// Sample cards skip Reminders. A live card reads which rows are already complete.
    var readsCompletion: Bool = true

    var body: some View {
        let _ = AskReminderChecks.shared.completed
        VStack(alignment: .leading, spacing: 12) {
            AskCardMark(title: title.isEmpty ? "Reminders" : title, symbol: "checklist", tint: .orange)
            ForEach(items) { item in
                AskReminderRow(item: item)
            }
        }
        .askCardSurface()
        .task(id: items.map(\.id)) {
            guard readsCompletion else { return }
            let found = await AskRemindersRead.completedIDs(items.map(\.id))
            guard !found.isEmpty else { return }
            AskReminderChecks.shared.adopt(found)
        }
    }
}

private struct AskReminderRow: View {
    var item: AskReminderItem.Item

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.askSnippet) private var snippet

    private var done: Bool {
        if snippet.isSnippet {
            return snippet.completedReminders.contains(item.id)
        }
        return AskReminderChecks.shared.completed.contains(item.id)
    }

    private var reminder: AskReminderEntity {
        AskReminderEntity(id: item.id, title: item.title)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(done ? .secondary : .primary)
                    .overlay { AskStrike(shown: done) }
                    .accessibilityLabel(done ? "\(item.title), completed" : item.title)
                if !item.due.isEmpty {
                    Text(item.due)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if done {
                Button(intent: AskReminderReopenTap(reminder: reminder)) {
                    reminderMark(systemName: "checkmark.circle.fill", tint: AnyShapeStyle(.green))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(item.title) incomplete")
            } else {
                Button(intent: AskReminderCompleteTap(reminder: reminder)) {
                    reminderMark(systemName: "circle", tint: AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(item.title)")
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: done)
    }

    private func reminderMark(systemName: String, tint: AnyShapeStyle) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(tint)
            .symbolEffect(.bounce, value: done)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

/// Draws across the title from the leading edge. Layout stays put, so the row does not shift.
private struct AskStrike: View {
    var shown: Bool

    var body: some View {
        Rectangle()
            .frame(maxWidth: .infinity)
            .frame(height: 1.5)
            .scaleEffect(x: shown ? 1 : 0.001, anchor: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif

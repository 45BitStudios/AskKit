import AppIntents
import SwiftUI
import UIKit

enum AskCardStyle {
    static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
}

/// Small type mark in the top-right of a card. The title itself stays plain text.
struct AskCardBadge: View {
    var title: String
    var symbol: String
    var tint: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AskCardBadgeInk.color(tint, scheme: scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(Color(.secondarySystemBackground))
            Capsule().fill(tint.opacity(scheme == .dark ? 0.42 : 0.22))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Full-width action inside a card. It pages with the card. Uses prominent Liquid Glass tinted to the card.
struct AskCardCTA<I: AppIntent>: View {
    var title: LocalizedStringKey
    var symbol: String
    var tint: Color
    var intent: I
    var accessibilityLabel: Text
    /// A full-width capsule. Off for a button that sits beside a label.
    var expands: Bool = true
    /// Off for the icon-only directions control beside a place.
    var showsTitle: Bool = true

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: showsTitle ? 8 : 0) {
                Image(systemName: symbol)
                    .font(showsTitle ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    .accessibilityHidden(true)
                if showsTitle {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: showsTitle ? nil : 44, minHeight: 44)
            .padding(.horizontal, showsTitle ? 16 : 0)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .buttonBorderShape(showsTitle ? .capsule : .circle)
        .frame(maxWidth: expands ? .infinity : nil)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Ink for the type chip. Light mode deepens the tint until it stays readable on the pale chip. Green and mint need to go darker than red or blue.
enum AskCardBadgeInk {
    static func color(_ tint: Color, scheme: ColorScheme) -> Color {
        guard scheme == .light else { return AskTintChrome.label(tint, scheme: scheme) }
        let resolved = UIColor(tint).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return Color(resolved)
        }
        let sat = min(max(saturation, 0.72), 1)
        let paper = mixed(resolved, amount: 0.22)
        var level = min(brightness, 0.55)
        var ink = UIColor(hue: hue, saturation: sat, brightness: level, alpha: 1)
        while level > 0.30, contrast(of: ink, against: paper) < 5.5 {
            level -= 0.03
            ink = UIColor(hue: hue, saturation: sat, brightness: level, alpha: 1)
        }
        return Color(ink)
    }

    /// Pale chip: white plus a little of the tint, matching the 22% wash on the system background.
    private static func mixed(_ tint: UIColor, amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        return UIColor(
            red: red * amount + (1 - amount),
            green: green * amount + (1 - amount),
            blue: blue * amount + (1 - amount),
            alpha: 1
        )
    }

    private static func contrast(of ink: UIColor, against paper: UIColor) -> CGFloat {
        let hi = max(luminance(ink), luminance(paper))
        let lo = min(luminance(ink), luminance(paper))
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

enum AskCardSymbol {
    static func symbol(for title: String) -> String {
        switch title.lowercased() {
        case "calendar": "calendar"
        case "reminders": "checklist"
        case "alarm", "alarms": "alarm.fill"
        case "contact": "person.fill"
        case "place", "location", "nearby": "mappin.and.ellipse"
        case "coordinates": "location.circle"
        case "steps": "figure.walk"
        case "heart rate": "heart.fill"
        case "song", "music", "music unavailable", "nothing playing": "music.note"
        case "album": "square.stack.fill"
        case "daily forecast", "weather", "no forecast": "cloud.sun.fill"
        case "hourly forecast": "clock.fill"
        case "web", "page": "globe"
        case "capabilities": "sparkles"
        case "charge", "skill": "bolt.fill"
        default: "sparkles"
        }
    }

    static func tint(for title: String) -> Color {
        switch title.lowercased() {
        case "calendar": .red
        case "reminders": .orange
        case "alarm", "alarms": .orange
        case "contact": .blue
        case "place", "location", "nearby", "coordinates": .green
        case "steps": .orange
        case "heart rate": .pink
        case "song", "music", "music unavailable", "nothing playing": .pink
        case "album": .indigo
        case "daily forecast", "hourly forecast", "weather", "no forecast": .blue
        case "web", "page": .blue
        case "capabilities": .indigo
        case "charge", "skill": .green
        default: .indigo
        }
    }
}

extension View {
    /// Shared answer-card surface. A tint wash sits on the gray fill. Cards stay solid because they scroll.
    func askCardSurface(tint: Color? = nil) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    AskCardStyle.shape.fill(.quaternary)
                    if let tint {
                        AskCardStyle.shape.fill(
                            LinearGradient(
                                colors: [tint.opacity(0.32), tint.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
            }
            .clipShape(AskCardStyle.shape)
    }
}

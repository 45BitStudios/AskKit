import SwiftUI

/// One calendar event on the card. Color and kind stay off the line the model reads.
package enum AskCalendarItem {
    static let marker = "\u{1F}"

    package enum Kind: String, Equatable {
        case timed
        case allDay
        case birthday
    }

    package struct Item: Identifiable, Equatable {
        package var id: String { line }
        var line: String
        package var day: String
        package var title: String
        package var when: String
        package var detail: String
        var colorHex: String
        var kind: Kind
        package var calendarName: String
        var writePrefix: String

        var shareLine: String { AskCalendarItem.plain(line) }
        package var color: Color { AskCalendarItem.color(from: colorHex) }
        package var isBirthday: Bool { kind == .birthday }
        package var isAllDay: Bool { kind == .allDay || kind == .birthday }
    }

    package static func line(
        day: String,
        title: String,
        when: String,
        detail: String = "",
        colorHex: String,
        kind: Kind,
        calendarName: String,
        prefix: String = ""
    ) -> String {
        let dayPart = day.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = when.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [prefix + dayPart, name.isEmpty ? "Event" : name]
        if !time.isEmpty { parts.append(time) }
        let extra = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { parts.append(extra) }
        let body = parts.joined(separator: " · ")
        let hex = normalizedHex(colorHex)
        let cal = AskAppleCopy.plain(calendarName, limit: 40)
            .replacingOccurrences(of: "|", with: " ")
        return body + marker + hex + "|" + kind.rawValue + "|" + cal
    }

    static func plain(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: marker) else { return trimmed }
        return trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the model may say. Color and kind stay on the card.
    static func forModel(_ output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .map { plain(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func parse(_ line: String) -> Item? {
        let body = plain(line)
        guard !body.isEmpty else { return nil }
        let meta = metadata(in: line)
        let parts = body.split(separator: "·", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }

        var writePrefix = ""
        var day = parts[0]
        for marker in [AskAppleCopy.addedPrefix, AskAppleCopy.updatedPrefix, AskAppleCopy.removedPrefix] {
            if day.hasPrefix(marker) {
                writePrefix = marker
                day = String(day.dropFirst(marker.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        guard !day.isEmpty else { return nil }

        let title: String
        let when: String
        let detail: String
        if parts.count == 2 {
            title = parts[1]
            when = "all day"
            detail = ""
            let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if folded.hasPrefix("nothing scheduled") || folded == "no birthdays." || folded == "not allowed." {
                return nil
            }
        } else {
            title = parts[1]
            when = parts[2]
            detail = parts.dropFirst(3).joined(separator: " · ")
        }
        guard !title.isEmpty else { return nil }

        let kind = meta.kind ?? inferredKind(title: title, when: when)
        let hex = meta.hex ?? defaultHex(for: kind)
        return Item(
            line: line,
            day: day,
            title: writePrefix + title,
            when: when,
            detail: detail,
            colorHex: hex,
            kind: kind,
            calendarName: meta.calendarName,
            writePrefix: writePrefix
        )
    }

    static func events(in lines: [String]) -> [Item] {
        lines.compactMap(parse)
    }

    static func hex(from cgColor: CGColor?) -> String {
        guard let cgColor else { return defaultHex(for: .timed) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let comps = converted.components,
              converted.numberOfComponents >= 3 else {
            return defaultHex(for: .timed)
        }
        return rgbHex(comps[0], comps[1], comps[2])
    }

    private static func rgbHex(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> String {
        String(
            format: "%02X%02X%02X",
            Int((min(max(red, 0), 1) * 255).rounded()),
            Int((min(max(green, 0), 1) * 255).rounded()),
            Int((min(max(blue, 0), 1) * 255).rounded())
        )
    }

    static func color(from hex: String) -> Color {
        let value = normalizedHex(hex)
        guard value.count == 6, let int = Int(value, radix: 16) else {
            return Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
        }
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }

    private static func metadata(in line: String) -> (hex: String?, kind: Kind?, calendarName: String) {
        guard let range = line.range(of: marker) else {
            return (nil, nil, "")
        }
        let raw = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = raw.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        let hex = pieces.first.flatMap { piece -> String? in
            let normalized = normalizedHex(piece)
            return normalized.count == 6 ? normalized : nil
        }
        let kind = pieces.count > 1 ? Kind(rawValue: pieces[1]) : nil
        let calendarName = pieces.count > 2 ? pieces[2] : ""
        return (hex, kind, calendarName)
    }

    private static func inferredKind(title: String, when: String) -> Kind {
        let foldedWhen = when.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let foldedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if foldedTitle.localizedStandardContains("birthday") { return .birthday }
        if foldedWhen == "all day" || foldedWhen == "all-day" { return .allDay }
        return .timed
    }

    private static func defaultHex(for kind: Kind) -> String {
        switch kind {
        case .birthday: "8E8E93"
        case .allDay, .timed: "0A84FF"
        }
    }

    private static func normalizedHex(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
    }
}

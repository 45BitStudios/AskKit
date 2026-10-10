import AskKit
import Foundation
import SwiftUI

enum SampleProject: String, CaseIterable, Identifiable {
    case garage
    case pantry
    case desk
    case open

    private static let selectionKey = "AskKit.selectedSample"

    /// The sample Ask uses. A shortcut reads this before any view appears.
    static var selected: SampleProject {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectionKey),
                  let project = SampleProject(rawValue: raw) else {
                return .garage
            }
            return project
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectionKey)
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .garage: "Ask Garage"
        case .pantry: "Ask Pantry"
        case .desk: "Ask Desk"
        case .open: "Open ended"
        }
    }

    var detail: String {
        switch self {
        case .garage: "Nineteen skills plus battery, cabin, and trip specialists with working titles."
        case .pantry: "Eighteen skills plus clock, pantry, and dinner specialists with working titles."
        case .desk: "Eighteen skills plus visitor, room, and package specialists with working titles."
        case .open: "Any question. Clock and photo-library specialists, plus Apple tools that are on."
        }
    }

    var symbol: String {
        switch self {
        case .garage: "bolt.car"
        case .pantry: "fork.knife"
        case .desk: "person.text.rectangle"
        case .open: "bubble.left.and.bubble.right"
        }
    }

    var appearance: AskChatAppearance {
        switch self {
        case .garage:
            AskChatAppearance(
                title: title,
                tint: Color(red: 0.05, green: 0.45, blue: 0.32),
                logo: .symbol(symbol),
                composerSymbol: "bolt.fill",
                emptyMessage: detail
            )
        case .pantry:
            AskChatAppearance(
                title: title,
                tint: Color(red: 0.72, green: 0.32, blue: 0.12),
                logo: .symbol(symbol),
                composerSymbol: "fork.knife",
                emptyMessage: detail
            )
        case .desk:
            AskChatAppearance(
                title: title,
                tint: Color(red: 0.22, green: 0.28, blue: 0.62),
                logo: .symbol(symbol),
                composerSymbol: "person.text.rectangle",
                emptyMessage: detail
            )
        case .open:
            AskChatAppearance(
                title: title,
                tint: Color(red: 0.42, green: 0.24, blue: 0.62),
                logo: .symbol(symbol),
                composerSymbol: "bubble.left.and.bubble.right",
                emptyMessage: detail
            )
        }
    }

    func assistant() throws -> AskAssistant {
        switch self {
        case .garage: return try GarageSample.assistant()
        case .pantry: return try PantrySample.assistant()
        case .desk: return try DeskSample.assistant()
        case .open: return try OpenSample.assistant()
        }
    }

    func makeAssistant() -> AskAssistant {
        do {
            return try assistant()
        } catch {
            fatalError("Sample could not open its store: \(error)")
        }
    }
}

import Foundation

/// sRGB components in 0...1. Used to pick black or white text on a host tint.
package struct AskSRGB: Equatable, Sendable {
    package var red: Double
    package var green: Double
    package var blue: Double

    package static let black = AskSRGB(red: 0, green: 0, blue: 0)
    package static let white = AskSRGB(red: 1, green: 1, blue: 1)

    /// WCAG relative luminance.
    package var luminance: Double {
        func channel(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            if clamped <= 0.04045 { return clamped / 12.92 }
            return pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio against another color. 1 is identical. 21 is black on white.
    package func contrast(against other: AskSRGB) -> Double {
        let lighter = max(luminance, other.luminance)
        let darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Ink that can sit on a host tint. Black or white, never a brand color.
package enum AskContrastInk: Equatable, Sendable {
    case black
    case white

    package var color: AskSRGB {
        switch self {
        case .black: .black
        case .white: .white
        }
    }
}

package enum AskContrast {
    /// WCAG AA for normal text. White on a light tint such as #B070FF is about 3.2:1 and fails this.
    package static let minimumTextRatio = 4.5

    /// The ink with the higher contrast. A tie uses black, which is the readable choice on a light tint.
    package static func label(on background: AskSRGB) -> AskContrastInk {
        let black = AskSRGB.black.contrast(against: background)
        let white = AskSRGB.white.contrast(against: background)
        return black >= white ? .black : .white
    }
}

#if !os(watchOS)
import AskKit
import AskKitIntents
import SwiftUI

/// Colors, logo, and copy for `AskChatView`.
///
/// Bubbles stay solid. Liquid Glass sits on the composer and the centered toolbar title.
/// Soft tint gradients wash the chat background behind both.
public struct AskChatAppearance {
    /// Shown in the toolbar. `nil` uses the assistant name.
    public var title: String?
    public var tint: Color
    /// Toolbar mark. The empty thread uses this unless `emptyLogo` is set.
    public var logo: AskChatLogo
    /// Empty-thread mark when `logo` is `.none`.
    public var composerSymbol: String
    public var userBubble: Color
    public var userForeground: Color
    public var assistantBubble: Color
    public var assistantForeground: Color
    public var placeholder: String
    /// Description under the centered empty-thread title.
    public var emptyMessage: String
    /// Centered title when the thread is empty. `nil` uses `title`, then the assistant name.
    public var emptyTitle: String?
    /// Centered mark when the thread is empty. `nil` uses `logo`.
    public var emptyLogo: AskChatLogo?
    public var thinkingTitle: String
    /// When false, the field shows Send and never the microphone.
    public var showsMicrophone: Bool
    /// Lobe colors for the listening glow, up to seven. Empty uses seven shades of `tint`.
    public var voiceColors: [Color]

    public init(
        title: String? = nil,
        tint: Color = .accentColor,
        logo: AskChatLogo = .symbol("sparkles"),
        composerSymbol: String = "sparkles",
        userBubble: Color? = nil,
        userForeground: Color = .white,
        assistantBubble: Color = AskChatAppearance.systemBubble,
        assistantForeground: Color = .primary,
        placeholder: String = "Ask",
        emptyMessage: String = "Ask a question, or start with a suggestion.",
        emptyTitle: String? = nil,
        emptyLogo: AskChatLogo? = nil,
        thinkingTitle: String = "Thinking",
        showsMicrophone: Bool = true,
        voiceColors: [Color] = []
    ) {
        self.title = title
        self.tint = tint
        self.logo = logo
        self.composerSymbol = composerSymbol
        self.userBubble = userBubble ?? tint
        self.userForeground = userForeground
        self.assistantBubble = assistantBubble
        self.assistantForeground = assistantForeground
        self.placeholder = placeholder
        self.emptyMessage = emptyMessage
        self.emptyTitle = emptyTitle
        self.emptyLogo = emptyLogo
        self.thinkingTitle = thinkingTitle
        self.showsMicrophone = showsMicrophone
        self.voiceColors = voiceColors
    }
}

extension AskChatAppearance {
    /// The speech-bubble fill this platform uses. The default for `assistantBubble`.
    public static var systemBubble: Color { AskPlatform.bubbleFill }
}

/// Lobe colors for the listening glow. A non-empty override replaces the tint family.
enum AskVoicePalette {
    static func colors(tint: Color, override: [Color]) -> [Color] {
        let custom = Array(override.prefix(7))
        if !custom.isEmpty { return custom }
        return family(of: tint)
    }

    /// Centre first, then pairs toward the edges, all near the tint's hue.
    private static func family(of tint: Color) -> [Color] {
        guard let parts = AskColorParts.hsb(tint) else {
            return Array(repeating: tint, count: 7)
        }
        let (hue, saturation, brightness) = parts
        let steps: [(CGFloat, CGFloat, CGFloat)] = [
            (0.00, 0.00, 0.10),
            (-0.035, 0.06, -0.10),
            (0.045, -0.08, 0.16),
            (-0.07, 0.04, -0.22),
            (0.08, -0.12, 0.04),
            (0.02, -0.18, 0.22),
            (-0.05, 0.10, -0.30),
        ]
        return steps.map { hueShift, saturationShift, brightnessShift in
            Color(
                hue: wrap(hue + hueShift),
                saturation: clamp(saturation + saturationShift, 0.45, 1),
                brightness: clamp(brightness + brightnessShift, 0.38, 1)
            )
        }
    }

    private static func wrap(_ value: CGFloat) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return Double(wrapped < 0 ? wrapped + 1 : wrapped)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> Double {
        Double(min(max(value, low), high))
    }
}

/// Suggestion capsules. A dim tint at low opacity disappears on black, so dark mode lifts it.
enum AskTintChrome {
    static func label(_ tint: Color, scheme: ColorScheme) -> Color {
        guard scheme == .dark else { return tint }
        return lifted(tint, minimumBrightness: 0.78)
    }

    static func capsule(_ tint: Color, scheme: ColorScheme) -> Color {
        label(tint, scheme: scheme).opacity(scheme == .dark ? 0.34 : 0.14)
    }

    private static func lifted(_ tint: Color, minimumBrightness: CGFloat) -> Color {
        guard let parts = AskColorParts.hsb(tint) else {
            return tint
        }
        let (hue, saturation, brightness) = parts
        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation, 0.45), 0.9)),
            brightness: Double(max(brightness, minimumBrightness))
        )
    }
}

/// Degrees to rotate BorderBeamKit's ocean palette onto the voice-color hue.
enum AskBeamTint {
    /// Circular mean of the ocean border blobs in `beam-spec.json`.
    static let oceanCenter = 236.76

    static func shift(tint: Color, override: [Color]) -> Double {
        guard let color = AskVoicePalette.colors(tint: tint, override: override).first else { return 0 }
        guard let hue = AskColorParts.hsb(color)?.hue else {
            return 0
        }
        return wrap((Double(hue) * 360) - oceanCenter)
    }

    private static func wrap(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}

public enum AskChatLogo {
    case symbol(String)
    case image(Image)
    case none
}

/// Soft color wash behind the transcript. Liquid Glass chrome reads against these blobs.
struct AskChatBackdrop: View {
    let tint: Color
    let voiceColors: [Color]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AskVoicePalette.colors(tint: tint, override: voiceColors)
        let depth = colorScheme == .dark ? 0.42 : 0.30
        ZStack {
            AskPlatform.background
            LinearGradient(
                colors: [
                    palette[safe: 0, else: tint].opacity(depth * 0.85),
                    palette[safe: 2, else: tint].opacity(depth * 0.35),
                    AskPlatform.background.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Ellipse()
                .fill(palette[safe: 1, else: tint].opacity(depth))
                .frame(width: 360, height: 300)
                .blur(radius: 72)
                .offset(x: -130, y: -260)
            Ellipse()
                .fill(palette[safe: 3, else: tint].opacity(depth * 0.9))
                .frame(width: 300, height: 260)
                .blur(radius: 68)
                .offset(x: 140, y: -80)
            Ellipse()
                .fill(palette[safe: 5, else: tint].opacity(depth * 0.75))
                .frame(width: 320, height: 280)
                .blur(radius: 80)
                .offset(x: 40, y: 320)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension Array where Element == Color {
    subscript(safe index: Int, else fallback: Color) -> Color {
        indices.contains(index) ? self[index] : fallback
    }
}
#endif

import SwiftUI
import UIKit

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
        assistantBubble: Color = Color(uiColor: .secondarySystemBackground),
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

/// Lobe colors for the listening glow. A non-empty override replaces the tint family.
enum AskVoicePalette {
    static func colors(tint: Color, override: [Color]) -> [Color] {
        let custom = Array(override.prefix(7))
        if !custom.isEmpty { return custom }
        return family(of: tint)
    }

    /// Centre first, then pairs toward the edges, all near the tint's hue.
    private static func family(of tint: Color) -> [Color] {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(tint).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return Array(repeating: tint, count: 7)
        }
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
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(tint).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return tint
        }
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
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
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
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: [
                    palette[safe: 0, else: tint].opacity(depth * 0.85),
                    palette[safe: 2, else: tint].opacity(depth * 0.35),
                    Color(uiColor: .systemBackground).opacity(0.15),
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

/// What the thinking orb is showing while a turn runs.
public enum AskChatPhase: Sendable {
    /// The turn has started and no profile has spoken yet.
    case thinking
    /// Choosing a skill, or a specialist is active before its tool runs.
    case choosing
    /// A specialist tool is running.
    case tool
    /// The writer is producing the answer.
    case writing
}

/// Status line beside the thinking orb. A skill can call `update` while its turn is running.
public enum AskChatActivity {
    @MainActor
    public static func update(_ title: String) {
        show(title)
    }

    @MainActor
    static func show(_ title: String, detail: String = "", phase: AskChatPhase = .thinking) {
        let center = AskChatActivityCenter.shared
        center.title = title
        center.detail = detail
        center.phase = phase
    }

    /// The reply text as the model writes it. Cleared when the turn is stored,
    /// and cleared early when the preview can no longer be the stored line.
    @MainActor
    public static func stream(_ text: String) {
        AskChatActivityCenter.shared.partial = text
        AskCue.streamAdvanced(to: text)
    }

    @MainActor
    public static func clearStream() {
        AskChatActivityCenter.shared.partial = ""
        AskCue.streamEnded()
    }
}

/// Whether answer text grows in the bubble while the model writes.
/// Off keeps the thinking row until the turn stores the line.
/// The key is `AskKit.stream` in standard `UserDefaults`. A missing key is off.
public enum AskStreamSelection: Sendable {
    public static let storageKey = "AskKit.stream"

    public static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}

/// Whether debug builds show a "Worked … · N step" pill above each answer.
/// Tap opens that turn's trace. The key is `AskKit.workedTrace` in standard `UserDefaults`.
/// A missing key is on.
public enum AskWorkedTraceSelection: Sendable {
    public static let storageKey = "AskKit.workedTrace"

    public static var isOn: Bool {
        get {
            guard UserDefaults.standard.object(forKey: storageKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: storageKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }
}

/// Shows a rewrite only while it can still be the stored line.
/// An empty snapshot leaves the current preview in place.
/// A second paragraph is ignored, so a background dump cannot replace a short line.
/// A partial longer than 600 characters, or one that adds an equals sign, is taken down.
/// A reply that must call a tool stays off the bubble until the turn stores the line.
/// Streaming off keeps every snapshot off the bubble.
/// Otherwise a discarded draft appears, clears, and the next specialist starts over.
@MainActor
enum AskReplyPreview {
    static func note(_ text: String, facts: String, holdsUntilTool: Bool = false) {
        guard AskStreamSelection.isOn else { return }
        guard !holdsUntilTool else { return }
        let partial = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty else { return }
        // Snapshots are the text so far. Once a blank line appears, every later
        // snapshot includes it, and the first paragraph stays on screen.
        if partial.range(of: #"\n[ \t]*\n"#, options: .regularExpression) != nil {
            return
        }
        guard AskGuide.acceptsReply(partial, facts: facts) else {
            AskChatActivity.clearStream()
            return
        }
        AskChatActivity.stream(partial)
    }
}

@MainActor
@Observable
final class AskChatActivityCenter {
    static let shared = AskChatActivityCenter()
    var title = ""
    var detail = ""
    var phase = AskChatPhase.thinking
    var partial = ""
}
